using System.Text.Json.Serialization;

namespace MiaoXinxin.Windows;

public sealed class PetManifest
{
    [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } = 1;
    [JsonPropertyName("id")] public string Id { get; set; } = "pet";
    [JsonPropertyName("name")] public string Name { get; set; } = "Pet";
    [JsonPropertyName("author")] public string Author { get; set; } = "Unknown";
    [JsonPropertyName("profile")] public PetProfile Profile { get; set; } = new();
    [JsonPropertyName("canvas_width")] public int CanvasWidth { get; set; } = 1024;
    [JsonPropertyName("canvas_height")] public int CanvasHeight { get; set; } = 1024;
    [JsonPropertyName("poses")] public PosePaths Poses { get; set; } = new();
    [JsonPropertyName("animations")] public AnimationCollection Animations { get; set; } = new();
    [JsonPropertyName("personality")] public PetPersonality Personality { get; set; } = new();
    [JsonPropertyName("toys")] public List<ToyDefinition> Toys { get; set; } = ToyDefinition.Defaults();
    [JsonPropertyName("extensions")] public List<ExtensionDefinition> Extensions { get; set; } = [];
}

public sealed class PetPersonality
{
    [JsonPropertyName("playfulness")] public double Playfulness { get; set; } = .65;
    [JsonPropertyName("sociability")] public double Sociability { get; set; } = .65;
    [JsonPropertyName("calmness")] public double Calmness { get; set; } = .55;
    [JsonPropertyName("appetite")] public double Appetite { get; set; } = .55;
    [JsonPropertyName("sleepiness")] public double Sleepiness { get; set; } = .55;
    [JsonPropertyName("curiosity")] public double Curiosity { get; set; } = .7;
}

public sealed class ToyDefinition
{
    [JsonPropertyName("id")] public string Id { get; set; } = "toy";
    [JsonPropertyName("kind")] public string Kind { get; set; } = "ball";
    [JsonPropertyName("label")] public string? Label { get; set; }
    [JsonPropertyName("enabled")] public bool Enabled { get; set; } = true;

    public static List<ToyDefinition> Defaults() => ["ball", "laser", "wand", "box", "food", "water"]
        .Select(kind => new ToyDefinition { Id = kind, Kind = kind })
        .ToList();
}

public sealed class ExtensionDefinition
{
    [JsonPropertyName("id")] public string Id { get; set; } = "extension";
    [JsonPropertyName("kind")] public string Kind { get; set; } = "behavior-pack";
    [JsonPropertyName("path")] public string Path { get; set; } = "extensions";
    [JsonPropertyName("minimum_app_version")] public string? MinimumAppVersion { get; set; }
}

public sealed class PetProfile
{
    [JsonPropertyName("species")] public string Species { get; set; } = "cat";
    [JsonPropertyName("breed")] public string? Breed { get; set; }
    [JsonPropertyName("body_traits")] public List<string> BodyTraits { get; set; } = [];
    [JsonPropertyName("identity_features")] public List<string> IdentityFeatures { get; set; } = [];
    [JsonPropertyName("motion_notes")] public List<string> MotionNotes { get; set; } = [];
}

public sealed class PosePaths
{
    [JsonPropertyName("resting")] public string Resting { get; set; } = "poses/resting";
    [JsonPropertyName("held")] public string Held { get; set; } = "poses/held";
    [JsonPropertyName("dialogue")] public string Dialogue { get; set; } = "poses/dialogue";
    [JsonPropertyName("transition")] public string Transition { get; set; } = "poses/transition";
}

public sealed class AnimationCollection
{
    [JsonPropertyName("walk")] public AnimationSpec Walk { get; set; } = new() { Fps = 3 };
    [JsonPropertyName("behaviors")] public Dictionary<string, AnimationSpec> Behaviors { get; set; } = [];
}

public sealed class AnimationSpec
{
    [JsonPropertyName("fps")] public double Fps { get; set; } = 2;
    [JsonPropertyName("frames")] public List<string> Frames { get; set; } = [];
    [JsonPropertyName("playback_loops")] public int? PlaybackLoops { get; set; }
    [JsonPropertyName("autonomous_weight")] public double? AutonomousWeight { get; set; }
    [JsonPropertyName("sleep")] public bool? Sleep { get; set; }
}
