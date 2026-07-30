import XCTest
@testable import DockCat

final class PetBehaviorCatalogTests: XCTestCase {
    func testLegacyManifestDefaultsToCatAndEmptyBehaviorOverrides() throws {
        let data = Data(#"""
        {
          "id": "legacy",
          "name": "Legacy Pet",
          "author": "Tester",
          "canvas_width": 512,
          "canvas_height": 512,
          "default_anchor": {"x": 0.5, "y": 0.88},
          "animations": {"walk": {"fps": 3, "frames": []}}
        }
        """#.utf8)

        let manifest = try JSONDecoder().decode(AssetManifest.self, from: data)

        XCTAssertEqual(manifest.profile.species, .cat)
        XCTAssertTrue(manifest.animations.behaviors.isEmpty)
        XCTAssertEqual(manifest.poses.resting, "poses/resting")
    }

    func testRabbitUsesBinkyAndManifestTimingOverride() throws {
        let animations = AssetManifest.Animations(
            walk: .init(fps: 4),
            behaviors: [
                "binky": .init(fps: 1.75, playbackLoops: 3, autonomousWeight: 1.25)
            ]
        )
        let catalog = PetBehaviorCatalog(
            profile: .init(species: .rabbit, breed: "Mini Rex"),
            animations: animations
        )

        let descriptor = try XCTUnwrap(catalog.descriptor(for: .signatureMove))

        XCTAssertEqual(descriptor.assetName, "binky")
        XCTAssertEqual(descriptor.fps, 1.75)
        XCTAssertEqual(descriptor.playbackLoops, 3)
        XCTAssertEqual(descriptor.autonomousWeight, 1.25)
    }

    func testSpeciesSpecificMenuTitles() {
        let chinese = AppStrings(language: .chinese)
        let english = AppStrings(language: .english)

        XCTAssertEqual(chinese.behaviorModeTitle(.signatureMove, species: .ferret), "雪貂战舞")
        XCTAssertEqual(chinese.behaviorModeTitle(.bellyRoll, species: .rabbit), "放松侧躺")
        XCTAssertEqual(english.behaviorModeTitle(.signatureMove, species: .dog), "Wag tail")
        XCTAssertEqual(english.behaviorModeTitle(.bellyRoll, species: .dog), "Roll over")
    }
}
