#ifndef SourceDir
  #define SourceDir "..\dist\MiaoXinxin-win-x64"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif
#ifndef AppVersion
  #define AppVersion "0.8.0"
#endif

[Setup]
AppId={{A5A7357B-2C8B-40AA-B64B-1CC73F738A1E}
AppName=Miao Xinxin Desktop Pet
AppVersion={#AppVersion}
AppPublisher=HExiao-mi
AppPublisherURL=https://github.com/HExiao-mi/MiaoXinxin-Desktop-Pet
DefaultDirName={localappdata}\Programs\MiaoXinxin
DefaultGroupName=Miao Xinxin
OutputDir={#OutputDir}
OutputBaseFilename=MiaoXinxin-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\MiaoXinxin.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Launch Miao Xinxin when I sign in"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Miao Xinxin"; Filename: "{app}\MiaoXinxin.exe"
Name: "{autodesktop}\Miao Xinxin"; Filename: "{app}\MiaoXinxin.exe"; Tasks: desktopicon
Name: "{userstartup}\Miao Xinxin"; Filename: "{app}\MiaoXinxin.exe"; Tasks: startup

[Run]
Filename: "{app}\MiaoXinxin.exe"; Description: "Launch Miao Xinxin"; Flags: nowait postinstall skipifsilent
