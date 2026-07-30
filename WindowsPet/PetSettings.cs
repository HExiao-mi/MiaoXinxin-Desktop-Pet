using System.IO;
using System.Text.Json;

namespace MiaoXinxin.Windows;

public sealed class PetSettings
{
    public string BehaviorMode { get; set; } = "random";

    private static string SettingsPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MiaoXinxin",
        "settings.json"
    );

    public static PetSettings Load()
    {
        try
        {
            return File.Exists(SettingsPath)
                ? JsonSerializer.Deserialize<PetSettings>(File.ReadAllText(SettingsPath)) ?? new()
                : new();
        }
        catch { return new(); }
    }

    public void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }
}
