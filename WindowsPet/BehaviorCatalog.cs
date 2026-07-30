namespace MiaoXinxin.Windows;

public sealed record BehaviorDescriptor(
    string Mode,
    string AssetName,
    double Fps,
    int PlaybackLoops,
    bool IsSleep,
    double AutonomousWeight,
    string Label
);

public sealed record ToyReaction(string? BehaviorMode, bool TracksTarget = false);

public static class ToyReactionCatalog
{
    public static ToyReaction For(string kind) => kind switch
    {
        "ball" => new("play_toy"),
        "laser" => new(null, true),
        "wand" => new("belly_roll"),
        "box" => new("sleep_loaf"),
        "food" => new("eating"),
        "water" => new("drinking"),
        _ => new(null)
    };
}

public sealed class BehaviorCatalog
{
    private readonly AssetPack _pack;

    public BehaviorCatalog(AssetPack pack) => _pack = pack;

    public IReadOnlyList<BehaviorDescriptor> AvailableBehaviors => Defaults()
        .Select(ApplyManifestOverride)
        .Where(item => _pack.HasAnimation(item.AssetName))
        .ToArray();

    public BehaviorDescriptor? PetResponse => _pack.HasAnimation("pet_response")
        ? ApplyManifestOverride(new("pet_response", "pet_response", 2.2, 1, false, 0, "摸摸回应"))
        : null;

    public string SignatureAssetName => _pack.Manifest.Profile.Species.ToLowerInvariant() switch
    {
        "cat" => "pounce",
        "dog" => "tail_wag",
        "rabbit" => "binky",
        "ferret" => "war_dance",
        _ => "signature_move"
    };

    public double AutonomousWeight(BehaviorDescriptor behavior, PetLifeState life, int hour)
    {
        var personality = _pack.Manifest.Personality;
        var factor = behavior.Mode switch
        {
            "play_toy" or "signature_move" =>
                (.35 + personality.Playfulness * 1.4) * Math.Max(.15, life.Energy / 70) * (.45 + life.Curiosity / 75),
            "grooming" => .45 + personality.Calmness,
            "belly_roll" => (.3 + personality.Sociability) * (.4 + life.Mood / 85),
            "sleep_curled" or "sleep_side" or "sleep_loaf" =>
                (.45 + personality.Sleepiness) * (life.Energy < 35 ? 2.8 : .75) * (hour >= 22 || hour < 7 ? 2.2 : 1),
            "eating" => (.35 + personality.Appetite) * (life.Fullness < 35 ? 3.2 : .45),
            "drinking" => life.Hydration < 38 ? 3.5 : .5,
            _ => 1
        };
        return Math.Max(0, behavior.AutonomousWeight * factor);
    }

    private IEnumerable<BehaviorDescriptor> Defaults()
    {
        yield return new("play_toy", "play_toy", 2.2, 2, false, 1, "玩玩具");
        yield return new("grooming", "grooming", 2.5, 2, false, .8, GroomingLabel());
        yield return new("belly_roll", "belly_roll", 1.9, 1, false, .65, RollLabel());
        yield return new("sleep_curled", "sleep_curled", 1.4, 1, true, .7, "卷起来睡");
        yield return new("sleep_side", "sleep_side", 1.4, 1, true, .7, "侧躺睡");
        yield return new("sleep_loaf", "sleep_loaf", 1.4, 1, true, .7, "趴着睡");
        yield return new("eating", "eating", 2, 2, false, .65, "吃饭");
        yield return new("drinking", "drinking", 2, 2, false, .65, "喝水");
        yield return new("signature_move", SignatureAssetName, 2.4, 2, false, .8, SignatureLabel());
    }

    private BehaviorDescriptor ApplyManifestOverride(BehaviorDescriptor item)
    {
        if (!_pack.Manifest.Animations.Behaviors.TryGetValue(item.AssetName, out var spec)) return item;
        return item with
        {
            Fps = Math.Max(.1, spec.Fps),
            PlaybackLoops = Math.Max(1, spec.PlaybackLoops ?? item.PlaybackLoops),
            IsSleep = spec.Sleep ?? item.IsSleep,
            AutonomousWeight = Math.Max(0, spec.AutonomousWeight ?? item.AutonomousWeight)
        };
    }

    private string GroomingLabel() => _pack.Manifest.Profile.Species == "rabbit" ? "洗脸理毛" : "梳理毛发";

    private string RollLabel() => _pack.Manifest.Profile.Species switch
    {
        "dog" => "开心打滚",
        "rabbit" => "放松侧躺",
        "ferret" => "鳄鱼翻滚",
        _ => "翻肚皮"
    };

    private string SignatureLabel() => _pack.Manifest.Profile.Species switch
    {
        "cat" => "扑扑猎物",
        "dog" => "开心摇尾巴",
        "rabbit" => "开心蹦蹦",
        "ferret" => "雪貂战舞",
        _ => "招牌动作"
    };
}
