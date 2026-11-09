param(
    [string]$Version = (Get-Content "$PSScriptRoot/../VERSION" -Raw).Trim(),
    [switch]$SkipInstaller,
    [string]$ISCC
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected a numeric x.y.z version' }
if ($Version -ne (Get-Content "$PSScriptRoot/../VERSION" -Raw).Trim()) { throw 'Version must match reviewed source VERSION' }
Push-Location $PSScriptRoot
try {
    python -m unittest discover -s tests -v
    if ($LASTEXITCODE -ne 0) { throw 'Unit tests failed' }
    python packaging/metadata.py
    if ($LASTEXITCODE -ne 0) { throw 'Windows x64 metadata/license validation failed' }
    python -m PyInstaller --noconfirm --clean --windowed --onedir --name BLEClipboard `
        --icon resources/AppIcon.ico --add-data 'resources/AppIcon.ico;resources' `
        --collect-all bleak --collect-submodules winrt --add-data '../LICENSE;.' `
        --add-data '../NOTICE;.' --add-data '../VERSION;.' --add-data 'build/THIRD-PARTY.txt;.' `
        --exclude-module PIL --version-file build/version-info.txt launch.py
    if ($LASTEXITCODE -ne 0) { throw 'Application build failed' }
    $exe = Join-Path $PSScriptRoot 'dist/BLEClipboard/BLEClipboard.exe'
    python packaging/metadata.py $exe
    if ($LASTEXITCODE -ne 0) { throw 'Packaged executable is not x64' }
    if ((Get-Item $exe).VersionInfo.ProductVersion -ne $Version) { throw 'Packaged version mismatch' }
    $test = Start-Process -FilePath $exe -ArgumentList '--self-test' -Wait -PassThru
    if ($test.ExitCode -ne 0) { throw "Packaged app smoke test failed: $($test.ExitCode)" }
    $out = Join-Path $PSScriptRoot "dist/v$Version"
    New-Item -ItemType Directory -Force $out | Out-Null
    Copy-Item ../LICENSE, ../README.md $out
    Copy-Item build/THIRD-PARTY.txt "$out/WINDOWS-THIRD-PARTY.txt"
    Compress-Archive -Path dist/BLEClipboard -DestinationPath "$out/BLE-Clipboard-$Version-windows-x64-portable.zip" -Force
    if (-not $SkipInstaller) {
        if (-not $ISCC) {
            $ISCC = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
            if (-not (Test-Path $ISCC)) {
                $ISCC = (Get-Command ISCC.exe -ErrorAction Stop).Source
            }
        }
        & $ISCC "/DAppVersion=$Version" packaging/installer.iss
        if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }
    }
    Get-ChildItem $out -File | Where-Object { $_.Extension -in '.exe', '.zip' } | Sort-Object Name | ForEach-Object {
        $hash = Get-FileHash $_.FullName -Algorithm SHA256
        '{0}  {1}' -f $hash.Hash.ToLowerInvariant(), $_.Name
    } | Set-Content "$out/SHA256SUMS-windows.txt" -Encoding ascii
    Write-Output "Windows artifacts: $out"
} finally {
    Pop-Location
}
