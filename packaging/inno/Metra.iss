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
PrivilegesRequired=lowest
OutputDir=..\out
OutputBaseFilename=MetraSetup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UsePreviousAppDir=yes
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} setup
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
; Unsigned builds may show SmartScreen - document More info -> Run anyway.
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Checked by default on first install and upgrade (no "unchecked" flag).
Name: "runsetup"; Description: "Run Metra setup now"; GroupDescription: "After install:"

[Files]
; Staged product tree only - Build-MetraInstaller.ps1 excludes user state.
Source: "..\stage\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Metra Setup"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autoprograms}\Metra Setup"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
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
