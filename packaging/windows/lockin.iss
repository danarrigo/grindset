#ifndef BuildDir
  #error BuildDir must point to the complete Flutter Windows release directory.
#endif
#ifndef OutputDir
  #error OutputDir is required.
#endif
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId=app.lockin.lockin
AppName=Lockin
AppVersion={#AppVersion}
AppPublisher=app.lockin
DefaultDirName={localappdata}\Programs\Lockin
DefaultGroupName=Lockin
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
DisableProgramGroupPage=yes
DisableDirPage=auto
CloseApplications=force
RestartApplications=no
SetupMutex=Lockin.Installer
UninstallDisplayIcon={app}\lockin.exe
SetupIconFile={#BuildDir}\data\flutter_assets\assets\tray.ico
OutputDir={#OutputDir}
OutputBaseFilename=lockin-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Icons]
Name: "{group}\Lockin"; Filename: "{app}\lockin.exe"; AppUserModelID: "app.lockin.lockin"
Name: "{autodesktop}\Lockin"; Filename: "{app}\lockin.exe"; Tasks: desktopicon; AppUserModelID: "app.lockin.lockin"

[Run]
Filename: "{app}\lockin.exe"; Description: "Open Lockin"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Startup: String;
  Executable: String;
begin
  if CurUninstallStep = usUninstall then
    if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Lockin', Startup) then
    begin
      Executable := Lowercase(ExpandConstant('{app}\lockin.exe'));
      Startup := Lowercase(Startup);
      if (Startup = Executable) or (Pos(Executable + ' ', Startup) = 1) or
         (Pos('"' + Executable + '"', Startup) = 1) then
        RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'Lockin');
    end;
  // History and authentication live outside the installation directory.
  // Uninstall preserves them. Reset this device in Settings to clear data.
end;
