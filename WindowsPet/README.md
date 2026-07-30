# Miao Xinxin for Windows

Native Windows 10/11 desktop-pet client using .NET 8 WPF. It reads the same `manifest.json`, `poses/`, and `animations/` directories as the macOS app.

```powershell
dotnet build WindowsPet.csproj -c Release
dotnet run --project WindowsPet.csproj -- "C:\path\to\PetPack"
```

Without a pack argument, the project copies and loads the bundled Miao Xinxin assets from the macOS source tree. Right-click the transparent pet window to choose Random, Resting, Walking, any available behavior, or the species signature behavior. The menu also provides draggable toys/bowls, life status, quiet/fullscreen/reduced-motion/battery modes, launch at login and update checks. The selected state, life memory and last position persist under `%LOCALAPPDATA%\MiaoXinxin\settings.json`.

The app is Per-Monitor-V2 DPI aware and docks against the work area of the display it currently occupies. Package a self-contained portable ZIP with `./Package.ps1`; tagged GitHub releases also compile `installer.iss` into a current-user Setup EXE.

Run pack validation before loading a custom pet:

```powershell
python Tools\petpack.py validate C:\path\to\PetPack --strict
```

The source project can only be compiled on Windows with the .NET 8 SDK and Windows Desktop workload.
