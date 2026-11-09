param([Parameter(Mandatory=$true)][string]$Installer)
$ErrorActionPreference = 'Stop'
$destination = Join-Path $env:RUNNER_TEMP 'BLEClipboard-install-check'
$data = Join-Path $env:RUNNER_TEMP 'BLEClipboard-test-appdata'
$env:APPDATA = $data
New-Item -ItemType Directory -Force "$data/BLE Clipboard" | Out-Null
$library = "$data/BLE Clipboard/macros.json"
'{"schemaVersion":1,"macros":[]}' | Set-Content $library -Encoding utf8
$original = (Get-FileHash $library).Hash
function Install-Candidate {
    $p = Start-Process -FilePath $Installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=`"$destination`"") -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Install failed: $($p.ExitCode)" }
    if ((Get-FileHash $library).Hash -ne $original) { throw 'Installer changed user library' }
}
Install-Candidate
$oldPath = $env:PATH
try {
    $env:PATH = "$env:SystemRoot/System32;$env:SystemRoot"
    $report = Join-Path $env:RUNNER_TEMP 'packaged-self-test.json'
    $p = Start-Process -FilePath "$destination/BLEClipboard.exe" -ArgumentList @('--self-test','--report',"`"$report`"") -Wait -PassThru
    if ($p.ExitCode -ne 0 -or -not (Get-Content $report -Raw | ConvertFrom-Json).ok) { throw 'Installed self-test without Python on PATH failed' }
} finally { $env:PATH = $oldPath }
Install-Candidate
$uninstall = Start-Process -FilePath "$destination/unins000.exe" -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -Wait -PassThru
if ($uninstall.ExitCode -ne 0) { throw 'Uninstall failed' }
if ((Get-FileHash $library).Hash -ne $original) { throw 'Uninstall removed user library' }
if (Test-Path "$destination/BLEClipboard.exe") { throw 'Uninstall left executable behind' }
Write-Output 'Clean install / no external Python / reinstall / library preservation / uninstall checks passed'
