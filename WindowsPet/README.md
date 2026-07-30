# Miao Xinxin for Windows

Native Windows 10/11 desktop-pet client using .NET 8 WPF. It reads the same `manifest.json`, `poses/`, and `animations/` directories as the macOS app.

```powershell
dotnet build WindowsPet.csproj -c Release
dotnet run --project WindowsPet.csproj -- "C:\path\to\PetPack"
```

Without a pack argument, the project copies and loads the bundled Miao Xinxin assets from the macOS source tree. Right-click the transparent pet window to choose Random, Resting, Walking, any available behavior, or the species signature behavior. The selected state persists under `%LOCALAPPDATA%\MiaoXinxin\settings.json`.

Run pack validation before loading a custom pet:

```powershell
python Tools\petpack.py validate C:\path\to\PetPack --strict
```

The source project can only be compiled on Windows with the .NET 8 SDK and Windows Desktop workload.
