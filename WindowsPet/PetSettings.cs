using System.IO;
using System.Text.Json;

namespace MiaoXinxin.Windows;

public sealed class PetSettings
{
    public string BehaviorMode { get; set; } = "random";
    public bool LifeSimulationEnabled { get; set; } = true;
    public bool NaturalScheduleEnabled { get; set; } = true;
    public bool QuietMode { get; set; }
    public bool ReducedMotion { get; set; }
    public bool BatterySaverEnabled { get; set; } = true;
    public bool HideDuringFullscreen { get; set; } = true;
    public bool LaunchAtLogin { get; set; }
    public bool DesktopToysEnabled { get; set; } = true;
    public bool AutomaticUpdateChecks { get; set; } = true;
    public DateTime? LastUpdateCheckDate { get; set; }
    public double? LastLeft { get; set; }
    public double? LastTop { get; set; }
    public PetLifeState Life { get; set; } = new();

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

public sealed class PetLifeState
{
    public double Energy { get; set; } = 82;
    public double Fullness { get; set; } = 78;
    public double Hydration { get; set; } = 80;
    public double Mood { get; set; } = 86;
    public double Affection { get; set; } = 50;
    public double Curiosity { get; set; } = 72;
    public DateTime LastUpdated { get; set; } = DateTime.Now;
    public DateTime AdoptionDate { get; set; } = DateTime.Now;
    public DateTime? LastInteractionDate { get; set; }
    public int Interactions { get; set; }
    public int PlayCount { get; set; }
    public int Meals { get; set; }
    public int Drinks { get; set; }
    public int Sleeps { get; set; }
    public string? FavoriteToy { get; set; }
    public Dictionary<string, int> ToyPlayCounts { get; set; } = [];

    public void Advance(bool sleeping)
    {
        var now = DateTime.Now;
        var hours = Math.Clamp((now - LastUpdated).TotalHours, 0, 24);
        if (sleeping)
        {
            Energy += hours * 13;
            Fullness -= hours * 1.3;
            Hydration -= hours * 1.6;
        }
        else
        {
            Energy -= hours * 3.2;
            Fullness -= hours * 2.1;
            Hydration -= hours * 2.6;
            Curiosity += hours * 1.1;
        }
        if (Fullness < 30 || Hydration < 30 || Energy < 20) Mood -= hours * 1.8;
        ClampAll();
        LastUpdated = now;
    }

    public void Apply(string action, string? toy = null)
    {
        LastInteractionDate = DateTime.Now;
        switch (action)
        {
            case "pet": Affection += 2.5; Mood += 4; Interactions++; break;
            case "play":
                Energy -= 5; Mood += 7; Curiosity -= 10; PlayCount++;
                if (toy is not null)
                {
                    ToyPlayCounts[toy] = ToyPlayCounts.GetValueOrDefault(toy) + 1;
                    FavoriteToy = ToyPlayCounts.OrderByDescending(pair => pair.Value).First().Key;
                }
                break;
            case "eat": Fullness += 34; Mood += 3; Meals++; break;
            case "drink": Hydration += 42; Mood += 2; Drinks++; break;
            case "sleep": Sleeps++; break;
            case "wake": Mood += 1; break;
        }
        ClampAll();
    }

    private void ClampAll()
    {
        Energy = Clamp(Energy); Fullness = Clamp(Fullness); Hydration = Clamp(Hydration);
        Mood = Clamp(Mood); Affection = Clamp(Affection); Curiosity = Clamp(Curiosity);
    }

    private static double Clamp(double value) => Math.Clamp(value, 5, 100);
}
