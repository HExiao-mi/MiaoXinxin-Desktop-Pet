import Foundation

struct PetBehaviorDescriptor: Equatable {
    var mode: PetBehaviorMode
    var assetName: String
    var fps: Double
    var playbackLoops: Int
    var isSleep: Bool
    var autonomousWeight: Double
}

struct PetBehaviorCatalog {
    let profile: AssetManifest.PetProfile
    let animations: AssetManifest.Animations

    func descriptor(for mode: PetBehaviorMode) -> PetBehaviorDescriptor? {
        guard let defaults = defaultDescriptor(for: mode) else { return nil }
        let override = animations.behaviors[defaults.assetName]
        return PetBehaviorDescriptor(
            mode: mode,
            assetName: defaults.assetName,
            fps: override?.fps ?? defaults.fps,
            playbackLoops: max(1, override?.playbackLoops ?? defaults.playbackLoops),
            isSleep: override?.sleep ?? defaults.isSleep,
            autonomousWeight: max(0, override?.autonomousWeight ?? defaults.autonomousWeight)
        )
    }

    var signatureAssetName: String {
        switch profile.species {
        case .cat: return "pounce"
        case .dog: return "tail_wag"
        case .rabbit: return "binky"
        case .ferret: return "war_dance"
        case .other: return "signature_move"
        }
    }

    private func defaultDescriptor(for mode: PetBehaviorMode) -> PetBehaviorDescriptor? {
        switch mode {
        case .random, .resting, .walking:
            return nil
        case .playToy:
            return .init(mode: mode, assetName: "play_toy", fps: 2.2, playbackLoops: 2, isSleep: false, autonomousWeight: 1)
        case .grooming:
            return .init(mode: mode, assetName: "grooming", fps: 2.5, playbackLoops: 2, isSleep: false, autonomousWeight: 0.8)
        case .bellyRoll:
            return .init(mode: mode, assetName: "belly_roll", fps: 1.9, playbackLoops: 1, isSleep: false, autonomousWeight: 0.65)
        case .sleepCurled:
            return .init(mode: mode, assetName: "sleep_curled", fps: 1.4, playbackLoops: 1, isSleep: true, autonomousWeight: 0.7)
        case .sleepSide:
            return .init(mode: mode, assetName: "sleep_side", fps: 1.4, playbackLoops: 1, isSleep: true, autonomousWeight: 0.7)
        case .sleepLoaf:
            return .init(mode: mode, assetName: "sleep_loaf", fps: 1.4, playbackLoops: 1, isSleep: true, autonomousWeight: 0.7)
        case .eating:
            return .init(mode: mode, assetName: "eating", fps: 2, playbackLoops: 2, isSleep: false, autonomousWeight: 0.65)
        case .drinking:
            return .init(mode: mode, assetName: "drinking", fps: 2, playbackLoops: 2, isSleep: false, autonomousWeight: 0.65)
        case .signatureMove:
            return .init(mode: mode, assetName: signatureAssetName, fps: signatureFPS, playbackLoops: 2, isSleep: false, autonomousWeight: 0.8)
        }
    }

    private var signatureFPS: Double {
        switch profile.species {
        case .cat: return 2.4
        case .dog: return 2.8
        case .rabbit: return 2.2
        case .ferret: return 2.6
        case .other: return 2.2
        }
    }
}
