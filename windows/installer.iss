; Inno Setup script: packages the `flutter build windows` output into one
; installer .exe, the closest Flutter equivalent to a PyInstaller --onefile
; build (see Docs/future_work.md for why there's no literal single-binary
; option for Flutter desktop). Compiled by the "Windows" job in
; .github/workflows/build.yml using the Inno Setup CLI (ISCC.exe), which
; ships preinstalled on GitHub's windows-latest runners.

#define MyAppName "Quiz App AI"
#define MyAppExeName "quizapp.exe"
#define MyAppPublisher "SavePoint"

[Setup]
AppId={{B6E1F9F0-6F7B-4C1D-9C0B-5B7A1D9E2F3A}
AppName={#MyAppName}
AppVersion=0.1.0
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\QuizAppAI
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=installer_output
OutputBaseFilename=QuizAppAI-Windows-Setup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; The entire flutter build windows release bundle (exe + data\ + any
; plugin DLLs), copied recursively.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
