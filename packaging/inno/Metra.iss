; Metra per-user installer (product distribution).
; AppId is permanent upgrade identity - never change across releases.
; Version is stamped by packaging/Build-MetraInstaller.ps1 via /DMyAppVersion=
; Source tree is a staged payload (packaging/stage) that excludes user state.

#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

#define MyAppName "Metra"
#define MyAppPublisher "Metra contributors"
#define MyAppURL "https://github.com/jaxnoth/Metra"
#define MyAppExeName "Metra-Setup.cmd"

[Setup]
AppId={{B7C8D9E0-1A2B-4C5D-8E9F-0A1B2C3D4E5F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={userdocs}\Metra
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Selected destination IS {app} - do not append \Metra under the chosen folder.
AppendDefaultDirName=no
PrivilegesRequired=lowest
OutputDir=..\out
OutputBaseFilename=MetraSetup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UsePreviousAppDir=yes
InfoBeforeFile=dir-readme.txt
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} setup
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
; Unsigned builds may show SmartScreen - document More info -> Run anyway.
SetupLogging=yes
SetupIconFile=..\..\docs\assets\metra.ico
UninstallDisplayIcon={app}\docs\assets\metra.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WizardSelectDir=Select Metra product folder
SelectDirDesc=Where should Metra product files live?
SelectDirLabel3=Select the Metra product folder (for example C:\Projects\_metra), not the portfolio parent (C:\Projects). The path below is the install root:

[Tasks]
; Checked by default on first install and upgrade (no "unchecked" flag).
Name: "runsetup"; Description: "Run Metra setup now"; GroupDescription: "After install:"

[Files]
; Staged product tree only - Build-MetraInstaller.ps1 excludes user state.
Source: "..\stage\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Metra Ops"; Filename: "{app}\Metra-Ops.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\docs\assets\metra.ico"
Name: "{autoprograms}\Metra Ops"; Filename: "{app}\Metra-Ops.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\docs\assets\metra.ico"
Name: "{group}\Metra Ops (console)"; Filename: "{app}\Metra-Ops-Console.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\docs\assets\metra.ico"
Name: "{group}\Metra Setup"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\docs\assets\metra.ico"
Name: "{autoprograms}\Metra Setup"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\docs\assets\metra.ico"
Name: "{group}\Uninstall Metra"; Filename: "{uninstallexe}"

[Run]
; Humans launch .cmd; .cmd launches PowerShell under process-scoped Bypass.
; -NoPause so the wizard post-install task does not wait for Enter.
Filename: "{app}\{#MyAppExeName}"; Parameters: "-NoPause"; WorkingDir: "{app}"; Description: "Run Metra setup now"; Flags: postinstall skipifsilent; Tasks: runsetup

[UninstallDelete]
; Do not delete user state (metra.config.json, projects.local.json, ledgers, local mdc).
; Only remove empty dirs Inno created if leftover.
Type: dirifempty; Name: "{app}\docs"
Type: dirifempty; Name: "{app}\scripts"
Type: dirifempty; Name: "{app}"

[Code]
function PathLeafName(const Dir: String): String;
var
  I: Integer;
begin
  Result := Dir;
  while (Length(Result) > 0) and ((Result[Length(Result)] = '\') or (Result[Length(Result)] = '/')) do
    SetLength(Result, Length(Result) - 1);
  I := Length(Result);
  while (I > 0) and (Result[I] <> '\') and (Result[I] <> '/') do
    I := I - 1;
  Result := Copy(Result, I + 1, MaxInt);
end;

function IsAllowedProductLeaf(const Leaf: String): Boolean;
var
  L: String;
begin
  L := LowerCase(Leaf);
  Result := (L = 'metra') or (L = '_metra') or (L = '_meta');
end;

function LooksLikePortfolioRoot(const Dir: String): Boolean;
begin
  Result := DirExists(AddBackslash(Dir) + 'TicketTracker') or
            DirExists(AddBackslash(Dir) + 'Solarwinds');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Dir, Leaf: String;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    Dir := WizardDirValue;
    Leaf := PathLeafName(Dir);
    if FileExists(AddBackslash(Dir) + 'metra.ps1') then
      Exit;
    if IsAllowedProductLeaf(Leaf) then
      Exit;
    if LooksLikePortfolioRoot(Dir) then
    begin
      MsgBox(
        'That folder looks like a portfolio parent (it contains TicketTracker or Solarwinds).' + #13#10 + #13#10 +
        'Choose the Metra product folder instead, for example:' + #13#10 +
        '  C:\Projects\_metra' + #13#10 +
        'or Documents\Metra.' + #13#10 + #13#10 +
        'Do not install into C:\Projects.',
        mbError, MB_OK);
      Result := False;
    end;
  end;
end;
