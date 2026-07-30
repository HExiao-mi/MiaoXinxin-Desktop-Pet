using System.IO;
using System.Text.Json;

namespace MiaoXinxin.Windows;

public sealed class AssetPack
{
    private static readonly string[] ImageExtensions = [".png", ".webp", ".jpg", ".jpeg"];

    public string RootPath { get; }
    public PetManifest Manifest { get; }

    private AssetPack(string rootPath, PetManifest manifest)
    {
        RootPath = rootPath;
        Manifest = manifest;
    }

    public static AssetPack Load(string rootPath)
    {
        var manifestPath = Path.Combine(rootPath, "manifest.json");
        if (!File.Exists(manifestPath))
            throw new FileNotFoundException("Pet pack is missing manifest.json", manifestPath);
        var manifest = JsonSerializer.Deserialize<PetManifest>(
            File.ReadAllText(manifestPath),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true }
        ) ?? throw new InvalidDataException("Pet manifest is invalid.");
        return new AssetPack(Path.GetFullPath(rootPath), manifest);
    }

    public IReadOnlyList<string> PoseFrames(string relativePath) => FramesAt(relativePath);

    public IReadOnlyList<string> AnimationFrames(string animationName) =>
        FramesAt(Path.Combine("animations", animationName));

    public bool HasAnimation(string animationName) => AnimationFrames(animationName).Count > 0;

    private IReadOnlyList<string> FramesAt(string relativePath)
    {
        var path = Path.Combine(RootPath, relativePath.Replace('/', Path.DirectorySeparatorChar));
        if (!Directory.Exists(path)) return [];
        return Directory.EnumerateFiles(path)
            .Where(file => ImageExtensions.Contains(Path.GetExtension(file).ToLowerInvariant()))
            .OrderBy(file => Path.GetFileName(file), StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }
}
