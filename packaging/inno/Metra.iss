; Metra per-user installer (product distribution).
; AppId is permanent upgrade identity - never change across releases.
; Version is stamped by packaging/Build-MetraInstaller.ps1 via /DMyAppVersion=
; Source tree is a staged payload (packaging/stage) that excludes user state.
; Operator copy follows docs/Brand.md Operator vocabulary.

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
; Always show Select Dir so the operator can change it; UsePreviousAppDir still prefills.
DisableDirPage=no
PrivilegesRequired=lowest
OutputDir=..\out
OutputBaseFilename=MetraSetup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UsePreviousAppDir=yes
DisableWelcomePage=no
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
WizardImageFile=wizard-image.bmp

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
BeveledLabel=Metra
WelcomeLabel1=Welcome to Metra
WelcomeLabel2=I'm Metra.%n%nWe'll choose where I live, how this machine fits into your desk, and a few preferences along the way.%n%nYou can change any of these later.
WizardSelectDir=Select Metra product folder
SelectDirDesc=Where should Metra product files live?
SelectDirLabel3=Select the Metra product folder (for example C:\Projects\_metra), not the portfolio parent (C:\Projects). The path below is the install root:
FinishedLabel=You're set.%n%nOpen Metra Ops from the Start Menu when you're ready.%nThat's where you'll work in Metra after this installer.

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
; Quiet setup for Standalone / HQ / Satellite only (Files only skips via Check).
; Runs during install (no Finished checkbox) - wizard already collected the answers.
; Transcript: {app}\docs\setup.local.log
Filename: "{app}\{#MyAppExeName}"; Parameters: "{code:GetSetupRunParams}"; WorkingDir: "{app}"; StatusMsg: "Setting up Metra (see docs\setup.local.log)..."; Flags: skipifsilent runhidden waituntilterminated; Check: ShouldRunQuietSetup

[UninstallDelete]
; Do not delete user state (metra.config.json, projects.local.json, ledgers, local mdc).
; Only remove empty dirs Inno created if leftover.
Type: dirifempty; Name: "{app}\docs"
Type: dirifempty; Name: "{app}\scripts"
Type: dirifempty; Name: "{app}"

[Code]
var
  RolePage: TInputOptionWizardPage;
  OpsUrlPage: TInputQueryWizardPage;
  NetPage: TWizardPage;
  FriendlyPage: TInputOptionWizardPage;
  AskPage: TInputOptionWizardPage;
  SummaryPage: TWizardPage;
  NetOpenLabel: TNewStaticText;
  NetOpenRec: TNewRadioButton;
  NetOpenLocal: TNewRadioButton;
  NetTsLabel: TNewStaticText;
  NetTsNo: TNewRadioButton;
  NetTsYes: TNewRadioButton;
  SummaryBody: TNewStaticText;

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

// Role radio order: 0 Standalone (default), 1 HQ, 2 Satellite, 3 Files only.
function IsFilesOnly: Boolean;
begin
  Result := RolePage.Values[3];
end;

function GetSelectedRole: String;
begin
  if RolePage.Values[0] then
    Result := 'Standalone'
  else if RolePage.Values[1] then
    Result := 'Hq'
  else if RolePage.Values[2] then
    Result := 'Satellite'
  else
    Result := 'FilesOnly';
end;

function IsHostRole: Boolean;
begin
  Result := RolePage.Values[0] or RolePage.Values[1];
end;

function ShouldRunQuietSetup: Boolean;
begin
  Result := not IsFilesOnly;
end;

function PreferFriendlySelected: Boolean;
begin
  if RolePage.Values[1] then
    Result := NetOpenRec.Checked
  else if RolePage.Values[0] then
    Result := FriendlyPage.Values[0]
  else
    Result := True;
end;

function BindTailscaleSelected: Boolean;
begin
  Result := RolePage.Values[1] and NetTsYes.Checked;
end;

function GetSetupRunParams(Param: String): String;
var
  Role, Url: String;
begin
  Role := GetSelectedRole;
  if CompareText(Role, 'FilesOnly') = 0 then
  begin
    Result := '';
    Exit;
  end;
  Result := '-NoPause -Quiet -Role ' + Role;
  if CompareText(Role, 'Satellite') = 0 then
  begin
    Url := Trim(OpsUrlPage.Values[0]);
    Result := Result + ' -OpsBaseUrl "' + Url + '"';
  end
  else
  begin
    if PreferFriendlySelected then
      Result := Result + ' -PreferFriendly'
    else
      Result := Result + ' -NoPreferFriendly';
    if BindTailscaleSelected then
      Result := Result + ' -BindTailscale';
    if AskPage.Values[0] then
      Result := Result + ' -AcceptAsk';
  end;
end;

procedure UpdateSummaryBody;
var
  Lines, RoleLabel, OpsLine, AskLine: String;
begin
  if RolePage.Values[0] then
    RoleLabel := 'Standalone'
  else if RolePage.Values[1] then
    RoleLabel := 'HQ (Main Metra machine)'
  else if RolePage.Values[2] then
    RoleLabel := 'Satellite'
  else
    RoleLabel := 'Files only';

  if RolePage.Values[3] then
  begin
    OpsLine := 'Setup: Not run - choose a role later via Metra Setup';
    AskLine := 'Ask assistant: Not installed';
  end
  else if RolePage.Values[2] then
  begin
    OpsLine := 'Main Metra machine: ' + Trim(OpsUrlPage.Values[0]);
    AskLine := 'Ask assistant: Not installed';
  end
  else
  begin
    if PreferFriendlySelected then
      OpsLine := 'Open Metra: Recommended (http://metra/)'
    else
      OpsLine := 'Open Metra: Local only (http://127.0.0.1:7380/)';
    if RolePage.Values[1] then
    begin
      if BindTailscaleSelected then
        OpsLine := OpsLine + #13#10 + 'Tailscale access: Yes'
      else
        OpsLine := OpsLine + #13#10 + 'Tailscale access: No';
    end;
    if AskPage.Values[0] then
      AskLine := 'Ask assistant: Installed'
    else
      AskLine := 'Ask assistant: Not installed';
  end;

  Lines :=
    'Role: ' + RoleLabel + #13#10 + #13#10 +
    OpsLine + #13#10 + #13#10 +
    AskLine + #13#10 + #13#10 +
    'Install folder: ' + WizardDirValue;
  SummaryBody.Caption := Lines;
end;

procedure InitializeWizard;
var
  TopY: Integer;
begin
  RolePage := CreateInputOptionPage(wpSelectDir,
    'Machine role', 'How should I show up on this PC?',
    'Choose how this machine fits into your Metra setup.' + #13#10 +
    'Standalone keeps everything on this PC (best for most people).' + #13#10 +
    'HQ is home base - other devices come here to work in Metra.' + #13#10 +
    'Satellite connects to your main Metra machine (laptops and secondary devices).' + #13#10 +
    'Standalone, HQ, and Satellite configure Metra after installation.' + #13#10 +
    'Files only installs Metra without choosing a role yet.',
    True, False);
  RolePage.Add('Standalone (Everything stays on this PC)');
  RolePage.Add('HQ (Main Metra machine)');
  RolePage.Add('Satellite (Connects to your main Metra machine)');
  RolePage.Add('Files only (Choose a role later)');
  RolePage.Values[0] := True;

  OpsUrlPage := CreateInputQueryPage(RolePage.ID,
    'Connect to your main Metra machine',
    'Enter the address you already use for Metra on another device.',
    'Example: https://metra.example.ts.net');
  OpsUrlPage.Add('Main Metra address:', False);

  NetPage := CreateCustomPage(OpsUrlPage.ID,
    'How you open Metra',
    'How should you open Metra on this machine?');
  TopY := ScaleY(8);
  NetOpenLabel := TNewStaticText.Create(NetPage);
  NetOpenLabel.Parent := NetPage.Surface;
  NetOpenLabel.Caption := 'How should you open Metra on this machine?';
  NetOpenLabel.Left := ScaleX(0);
  NetOpenLabel.Top := TopY;
  NetOpenLabel.Width := NetPage.SurfaceWidth;
  TopY := TopY + ScaleY(22);
  NetOpenRec := TNewRadioButton.Create(NetPage);
  NetOpenRec.Parent := NetPage.Surface;
  NetOpenRec.Caption := 'Recommended (http://metra/)';
  NetOpenRec.Left := ScaleX(0);
  NetOpenRec.Top := TopY;
  NetOpenRec.Width := NetPage.SurfaceWidth;
  NetOpenRec.Checked := True;
  TopY := TopY + ScaleY(22);
  NetOpenLocal := TNewRadioButton.Create(NetPage);
  NetOpenLocal.Parent := NetPage.Surface;
  NetOpenLocal.Caption := 'Local only (http://127.0.0.1:7380/)';
  NetOpenLocal.Left := ScaleX(0);
  NetOpenLocal.Top := TopY;
  NetOpenLocal.Width := NetPage.SurfaceWidth;
  TopY := TopY + ScaleY(36);
  NetTsLabel := TNewStaticText.Create(NetPage);
  NetTsLabel.Parent := NetPage.Surface;
  NetTsLabel.Caption := 'Allow access from other devices on Tailscale?';
  NetTsLabel.Left := ScaleX(0);
  NetTsLabel.Top := TopY;
  NetTsLabel.Width := NetPage.SurfaceWidth;
  TopY := TopY + ScaleY(22);
  NetTsNo := TNewRadioButton.Create(NetPage);
  NetTsNo.Parent := NetPage.Surface;
  NetTsNo.Caption := 'No (recommended)';
  NetTsNo.Left := ScaleX(0);
  NetTsNo.Top := TopY;
  NetTsNo.Width := NetPage.SurfaceWidth;
  NetTsNo.Checked := True;
  TopY := TopY + ScaleY(22);
  NetTsYes := TNewRadioButton.Create(NetPage);
  NetTsYes.Parent := NetPage.Surface;
  NetTsYes.Caption := 'Yes';
  NetTsYes.Left := ScaleX(0);
  NetTsYes.Top := TopY;
  NetTsYes.Width := NetPage.SurfaceWidth;

  FriendlyPage := CreateInputOptionPage(NetPage.ID,
    'How you open Metra',
    'How should you open Metra on this machine?',
    'Recommended uses http://metra/ when port 80 is free. Local only uses http://127.0.0.1:7380/.',
    True, False);
  FriendlyPage.Add('Recommended (http://metra/)');
  FriendlyPage.Add('Local only (http://127.0.0.1:7380/)');
  FriendlyPage.Values[0] := True;

  AskPage := CreateInputOptionPage(FriendlyPage.ID,
    'Ask assistant',
    'Install the recommended Ask assistant on this PC?',
    'Installs Ollama and a recommended model. This may require a large download and can take several minutes.' + #13#10 +
    'Satellites use Ask on the main Metra machine instead.',
    True, False);
  AskPage.Add('Yes');
  AskPage.Add('No');
  AskPage.Values[1] := True;

  SummaryPage := CreateCustomPage(AskPage.ID,
    'Here''s where we''re landing',
    'Looks right? Next we install.');
  SummaryBody := TNewStaticText.Create(SummaryPage);
  SummaryBody.Parent := SummaryPage.Surface;
  SummaryBody.Left := ScaleX(0);
  SummaryBody.Top := ScaleY(8);
  SummaryBody.Width := SummaryPage.SurfaceWidth;
  SummaryBody.Height := ScaleY(200);
  SummaryBody.AutoSize := False;
  SummaryBody.WordWrap := True;
  SummaryBody.Caption := '';
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = OpsUrlPage.ID then
    Result := not RolePage.Values[2]
  else if PageID = NetPage.ID then
    Result := not RolePage.Values[1]
  else if PageID = FriendlyPage.ID then
    Result := not RolePage.Values[0]
  else if PageID = AskPage.ID then
    Result := not IsHostRole
  else if PageID = SummaryPage.ID then
    Result := False;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = SummaryPage.ID then
    UpdateSummaryBody;
  if CurPageID = wpFinished then
  begin
    if IsFilesOnly then
      WizardForm.FinishedLabel.Caption :=
        'Product files are in place.' + #13#10 + #13#10 +
        'When you''re ready to choose a role and set up Metra, open Metra Setup from the Start Menu.'
    else
      WizardForm.FinishedLabel.Caption :=
        'You''re set.' + #13#10 + #13#10 +
        'Open Metra Ops from the Start Menu when you''re ready.' + #13#10 +
        'That''s where you''ll work in Metra after this installer.';
  end;
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
  end
  else if CurPageID = OpsUrlPage.ID then
  begin
    if Trim(OpsUrlPage.Values[0]) = '' then
    begin
      MsgBox(
        'Main Metra address is required for Satellite.' + #13#10 + #13#10 +
        'Enter the address you already use for Metra on another device (for example https://metra.example.ts.net), or go Back and pick another role.',
        mbError, MB_OK);
      Result := False;
    end;
  end;
end;
