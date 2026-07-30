# Miao Xinxin Desktop Pet

This repository now ships native clients for macOS (Swift/AppKit) and Windows 10/11 (C#/.NET 8 WPF). Both clients load the same pet-pack format. A user can attach photos and videos of their own cat, dog, rabbit, ferret, or another pet in a Codex conversation and ask for a desktop pet; the repository workflow records the individual identity, generates species-appropriate actions, and validates the shared pack.

See [implementation and references](docs/IMPLEMENTATION.md) and the [change record from DockCat v0.7.0](docs/CHANGELOG_FROM_UPSTREAM.md) for architecture, attribution, original work, animation QA, and cited behavior sources.

This cross-platform macOS and Windows desktop pet stars Miao Xinxin, a grey-and-white Munchkin cat with round golden eyes and a turquoise-blue bead necklace with silver spacers. It is based on [Auwuua/DockCat](https://github.com/Auwuua/DockCat) v0.7.0 (upstream commit `9dd4c4b`).

In Random mode, Miao Xinxin plays with a felt ball, grooms, rolls onto her belly, eats, drinks, follows the nearby pointer with her head, and sleeps autonomously in three breathing poses. Her slower eight-frame short-legged gait replaces the old sliding walk. Right-click the cat or Dock icon to keep any behavior indefinitely, or choose Random to resume autonomous switching. Click the cat or choose “Pet Miao Xinxin” and she will lift her chin, close her eyes, and nuzzle before returning to the selected behavior.

The repository publishes auditable source and the shared pet pack rather than local ad-hoc binaries or private reference media. Build the macOS client with Xcode or the Windows 10/11 client with the .NET 8 SDK. GitHub Actions builds both platforms on every push.

This customization retains the upstream PolyForm Noncommercial License and is for noncommercial use only. See [LICENSE.txt](LICENSE.txt).

---

# Upstream DockCat Documentation

[中文](README.md) | English

DockCat is a desktop companion cat that lives by the macOS Dock.

It rests, stretches, and wanders along the Dock, and can gently remind you to drink water or stand up for a short walk. DockCat is meant to be a quiet little presence on your screen: soft, lightweight, and never too demanding. You can pet the cat to change its pose, or drag it to a cozy spot you like. When you need to focus or leave, you can let the cat play outside for a while, and it may come back with a tiny surprise.

<table>
  <tr>
    <td align="center"><img src="README_figs/stretch.jpg" alt="Stretch" width="260"></td>
    <td align="center"><img src="README_figs/walk.jpg" alt="Walk" width="260"></td>
    <td align="center"><img src="README_figs/water_reminder.jpg" alt="Water reminder" width="260"></td>
  </tr>
  <tr>
    <td align="center">Stretch</td>
    <td align="center">Walk</td>
    <td align="center">Water reminder</td>
  </tr>
</table>

Upstream v0.7.0 supports macOS 12 and later on Intel and Apple Silicon. This repository adds its own Windows 10/11 WPF client, which reads the same pet packs.

## Quick Start

If you'd like to let the cat move in, we recommend downloading `DockCat.zip` from GitHub Releases.

1. For the unmodified DockCat release, open the upstream [Releases](https://github.com/Auwuua/DockCat/releases) page.
2. Download the latest `DockCat.zip`.
3. Unzip it, then drag `DockCat.app` into Applications or any folder you prefer.
4. On first launch, right-click `DockCat.app`, choose Open, then confirm.
5. If macOS says it cannot verify the developer, allow the app in System Settings > Privacy & Security.

## Usage

- After launch, a cat will appear along the upper edge of the Dock.
- Right-click the cat or the app icon to open the menu.
- Choose any item under Keep behavior to hold that state indefinitely; choose Random (autonomous) to resume automatic switching.
- Settings let you change the cat's name, what it calls you, display scale, reminder intervals, and more.
- Custom cat asset packs are supported, so you can make DockCat look like your own cat.

The cat can switch between these states:

- Random: the cat switches among resting, walking, ball play, grooming, belly rolls, eating, drinking, and three sleep poses.
- Kept behavior: lock resting, walking, or any full animation; the selection survives dragging, reminders, and outings.
- Walking: the cat moves slowly along the Dock with an eight-frame alternating short-legged gait.
- Petting: click the cat or choose Pet Miao Xinxin for a cooperative nuzzle animation, then return to the selected behavior.
- Transitioning: the cat briefly stretches or yawns.
- Held: drag the cat with the left mouse button to move it.
- Dialogue: the cat faces you for reminders and outing conversations.
- Outing: the cat goes out for the duration you choose, then comes back with something funny. Please try it!

## Can I Customize The Cat?

Yes! Supporting custom cats was one of our original goals when designing DockCat.

To create artwork for your own cat:

- We share the prompts used for the default cat in [ImageGenerationPrompts.md](CustomizationGuide/ImageGenerationPrompts.md). You can pair them with photos of your own cat in your preferred AI image generation tool.
- You can also use the default cat images as pose references and ask an AI image generation tool to keep the pose while changing the breed, colors, and markings. Remember to include image size and file format requirements.
- We recommend starting with the standing dialogue pose, because it shows the cat's colors and markings most clearly.

Next, let DockCat load your cat asset pack. Please read the customization guide: [CatCustomization.md](CustomizationGuide/CatCustomization.md).

- To use your own cat in every scene, provide at least one image for each of these five state folders: resting, walking, transitioning, held, and dialogue.
- DockCat can load incomplete custom packs for preview. Missing or failed asset types automatically fall back to the default cat, so your little companion will not vanish from the screen.
- You can add as many images as you want to the same state folder. Whenever the cat enters a non-walking state, DockCat randomly picks one available image from that folder. Walking images are played in order as a looping animation.

If you need help creating or loading your own asset pack, you can find our contact information in [Support And Contact](#support-and-contact) below.

PS: Since DockCat can read any image, it does not strictly have to be a cat, right? 👀

## Build From Source

If you want to modify the cat's behavior or event resources, you can build from source.

Xcode build command:

```bash
git clone https://github.com/HExiao-mi/MiaoXinxin-Desktop-Pet.git
cd MiaoXinxin-Desktop-Pet
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -derivedDataPath DockCatApp/DerivedDataDebug build
open DockCatApp/DerivedDataDebug/Build/Products/Debug/DockCat.app
```

Windows 10/11 (.NET 8 SDK):

```powershell
dotnet build WindowsPet/WindowsPet.csproj -c Release
dotnet run --project WindowsPet/WindowsPet.csproj -- "C:\path\to\PetPack"
```

## Privacy And Local Data

DockCat runs completely locally on your Mac. It does not require network access, transmit data, or include ads.

It stores only the necessary app data on your Mac:

- Your custom settings, such as the cat's name, what it calls you, reminder intervals, and default outing duration.
- Your usage statistics, such as companion time, completed water and movement reminders, and collectables the cat brought home.
- Your custom cat asset packs.

When you update DockCat, it automatically reads the app's previous local data. If you use custom asset packs, we recommend keeping your own backup as an extra precaution.

## License

DockCat uses the PolyForm Noncommercial License. See [LICENSE.txt](LICENSE.txt) for the full terms. In short:

- You may freely read, copy, modify, and build your own version of DockCat from this source code.
- You may not use DockCat or modified versions of it for commercial purposes, including selling it, paid distribution, or bundling it with commercial products. Commercial use requires additional authorization.
- If you publicly distribute a modified version, you must keep the original license and copyright notice, provide a link to this project, and describe your changes.

## Support And Contact

DockCat is under active development. We plan to add more customizable functions and continue expanding the outing result list.

If you enjoy DockCat, please consider starring this project at the top right of this page, or [Buy Me a Coffee](https://buymeacoffee.com/auwuua).

If you need help while using DockCat, or want to support DockCat in another way, here is how to reach us:

- Email: tianmaizhang@gmail.com

We hope DockCat brings you the soft companionship you love.
