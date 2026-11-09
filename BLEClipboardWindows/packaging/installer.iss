#ifndef AppVersion
  #error AppVersion must be generated from VERSION by build.ps1
#endif

[Setup]
AppId={{C6B5CB95-77C4-44CD-88C5-F0C15C347644}
AppName=BLE Clipboard
AppVersion={#AppVersion}
AppPublisher=Oguzcan Unver
AppPublisherURL=https://github.com/otcan/ble-clipboard
DefaultDirName={localappdata}\Programs\BLE Clipboard
DefaultGroupName=BLE Clipboard
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
MinVersion=10.0.19041
UninstallDisplayIcon={app}\BLEClipboard.exe
SetupIconFile=..\resources\AppIcon.ico
LicenseFile=..\..\LICENSE
OutputDir=..\dist\v{#AppVersion}
OutputBaseFilename=BLE-Clipboard-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\dist\BLEClipboard\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BLE Clipboard"; Filename: "{app}\BLEClipboard.exe"
Name: "{autodesktop}\BLE Clipboard"; Filename: "{app}\BLEClipboard.exe"; Tasks: desktopicon

