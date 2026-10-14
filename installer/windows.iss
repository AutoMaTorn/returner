; Inno Setup script for Returner (Windows x64).
; Built by `dart run tool/package_windows.dart`, which passes:
;   /DAppVersion=<version from pubspec.yaml>
;   /DStageDir=<folder with the release build and bin\ipatool.exe, bin\ios.exe>
;   /DOutputDir=<where to put the installer>

;   /DDataDir=<folder>   optional, for testing only: the user-data folder the
;                        uninstaller offers to delete

#ifndef AppVersion
  #error AppVersion is not defined. Run tool/package_windows.dart instead of compiling this file directly.
#endif

; Where the app keeps the Apple ID session, downloaded packages, database,
; icons and log (path_provider's application support directory).
#ifndef DataDir
  #define DataDir "{userappdata}\ru.returner\returner"
#endif

[Setup]
; Never change AppId: it is how updates find the previous installation.
AppId={{6F2B3E0C-5C0E-4B6E-9D7B-3A2E7C1D8F41}
AppName=Returner
AppVersion={#AppVersion}
AppVerName=Returner {#AppVersion}
AppPublisher=Returner
DefaultDirName={autopf}\Returner
DefaultGroupName=Returner
DisableProgramGroupPage=yes
; Installs for the current user without administrator rights.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=returner-setup-{#AppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayName=Returner
UninstallDisplayIcon={app}\returner.exe
CloseApplications=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole release folder: the app, Flutter runtime, plugins, data, and
; bin\ with the bundled ipatool and go-ios.
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Returner"; Filename: "{app}\returner.exe"
Name: "{group}\{cm:UninstallProgram,Returner}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Returner"; Filename: "{app}\returner.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\returner.exe"; Description: "{cm:LaunchProgram,Returner}"; Flags: nowait postinstall skipifsilent

[CustomMessages]
russian.RemoveDataQuestion=Удалить также данные Returner?%n%nБудут удалены сессия Apple ID, скачанные приложения, настройки и журнал:%n%1%n%nВернуть их будет нельзя. Если собираетесь поставить Returner снова — выберите «Нет».
english.RemoveDataQuestion=Also delete Returner's data?%n%nThis removes the Apple ID session, downloaded apps, settings and the log:%n%1%n%nThis cannot be undone. Choose No if you plan to install Returner again.

[Code]
// The uninstaller removes the program. The user's data is kept unless they
// say otherwise: silently deleting someone's downloads would be a nasty
// surprise, and keeping them lets a reinstall pick up where it left off.
//
// Interactive uninstall asks, with "No" as the default.
// Silent uninstall keeps the data unless /PURGEDATA=1 is passed.

function WantsPurge(): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/PURGEDATA=1') = 0 then
      Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir, Parent: String;
  Remove: Boolean;
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;
  DataDir := ExpandConstant('{#DataDir}');
  if not DirExists(DataDir) then
    Exit;

  if UninstallSilent then
    Remove := WantsPurge()
  else
    Remove := MsgBox(FmtMessage(CustomMessage('RemoveDataQuestion'), [DataDir]),
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  if not Remove then
    Exit;

  DelTree(DataDir, True, True, True);
  // The vendor folder above it, if nothing else lives there.
  Parent := ExtractFileDir(DataDir);
  RemoveDir(Parent);
end;
