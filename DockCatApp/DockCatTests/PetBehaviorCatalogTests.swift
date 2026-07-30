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
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.personality, .balanced)
        XCTAssertEqual(Set(manifest.toys.map(\.kind)), Set(PetToyKind.allCases))
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

    func testDesktopToysHaveDistinctSemanticReactions() {
        XCTAssertEqual(PetToyReactionCatalog.reaction(for: .ball), .behavior(.playToy))
        XCTAssertEqual(PetToyReactionCatalog.reaction(for: .laser), .trackTarget)
        XCTAssertEqual(PetToyReactionCatalog.reaction(for: .wand), .behavior(.bellyRoll))
        XCTAssertEqual(PetToyReactionCatalog.reaction(for: .box), .behavior(.sleepLoaf))
        XCTAssertEqual(PetToyReactionCatalog.reaction(for: .food), .behavior(.eating))
        XCTAssertEqual(PetToyReactionCatalog.reaction(for: .water), .behavior(.drinking))
    }

    func testLifeAndPersonalityChangeAutonomousPriorities() throws {
        let catalog = PetBehaviorCatalog(
            profile: .init(species: .cat),
            animations: .init(walk: .init(fps: 4))
        )
        var life = PetLifeState()
        life.energy = 18
        life.fullness = 20
        let sleep = try XCTUnwrap(catalog.descriptor(for: .sleepCurled))
        let food = try XCTUnwrap(catalog.descriptor(for: .eating))
        let play = try XCTUnwrap(catalog.descriptor(for: .playToy))
        let personality = AssetManifest.Personality(
            playfulness: 0.2, sociability: 0.5, calmness: 0.5,
            appetite: 1, sleepiness: 1, curiosity: 0.5
        )

        XCTAssertGreaterThan(catalog.autonomousWeight(for: sleep, life: life, personality: personality, hour: 23),
                             catalog.autonomousWeight(for: play, life: life, personality: personality, hour: 23))
        XCTAssertGreaterThan(catalog.autonomousWeight(for: food, life: life, personality: personality, hour: 12),
                             catalog.autonomousWeight(for: play, life: life, personality: personality, hour: 12))
    }

    func testLifeStateRemembersFavoriteToyAndRemainsForgiving() {
        var life = PetLifeState()
        life.energy = 6
        life.advance(to: Date().addingTimeInterval(24 * 3_600), sleeping: false)
        life.apply(.play, toy: .ball)
        life.apply(.play, toy: .ball)
        life.apply(.play, toy: .wand)

        XCTAssertGreaterThanOrEqual(life.energy, 5)
        XCTAssertEqual(life.favoriteToy, .ball)
        XCTAssertEqual(life.playCount, 3)
    }

    func testSemanticVersionComparison() {
        XCTAssertTrue(GitHubUpdateChecker.isNewer("v0.9.0", than: "0.8.2"))
        XCTAssertFalse(GitHubUpdateChecker.isNewer("v0.8.0", than: "0.8.0"))
        XCTAssertFalse(GitHubUpdateChecker.isNewer("v0.7.9", than: "0.8.0"))
    }
}
