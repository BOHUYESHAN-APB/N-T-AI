#ifndef MyAppName
  #define MyAppName "N-T-AI"
#endif
#ifndef MyAppExeName
  #define MyAppExeName "flutter_application.exe"
#endif
#ifndef MyAppPublisher
  #define MyAppPublisher "N-T-AI Team"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef MySourceDir
  #define MySourceDir "..\\flutter_application\\build\\windows\\x64\\runner\\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\\flutter_application\\build\\windows\\installer"
#endif
#ifndef MyLicenseFile
  #define MyLicenseFile "..\\LICENSE"
#endif
#ifndef MyIconFile
  #define MyIconFile "..\\flutter_application\\windows\\runner\\resources\\app_icon.ico"
#endif

[Setup]
AppId={{B0A7BB1E-7F52-4A8E-9A04-0E1F7C0C4F8C}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyAppName}-Setup-{#MyAppVersion}
SetupIconFile={#MyIconFile}
LicenseFile={#MyLicenseFile}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; Flags: unchecked
Name: "autorun"; Description: "Start on Windows login"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion createallsubdirs

[Icons]
Name: "{autoprograms}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"
Name: "{autodesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\\Microsoft\\Windows\\CurrentVersion\\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\\{#MyAppExeName}"""; Tasks: autorun

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
