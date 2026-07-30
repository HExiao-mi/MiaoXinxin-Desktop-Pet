import CoreGraphics
import Foundation

enum PetSpecies: String, Codable, CaseIterable, Equatable {
    case cat
    case dog
    case rabbit
    case ferret
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        self = PetSpecies(rawValue: rawValue) ?? .other
    }
}

struct AssetManifest: Codable, Equatable {
    struct Personality: Codable, Equatable {
        var playfulness: Double
        var sociability: Double
        var calmness: Double
        var appetite: Double
        var sleepiness: Double
        var curiosity: Double

        static let balanced = Personality(
            playfulness: 0.65,
            sociability: 0.65,
            calmness: 0.55,
            appetite: 0.55,
            sleepiness: 0.55,
            curiosity: 0.7
        )

        enum CodingKeys: String, CodingKey {
            case playfulness, sociability, calmness, appetite, sleepiness, curiosity
        }

        init(playfulness: Double, sociability: Double, calmness: Double, appetite: Double, sleepiness: Double, curiosity: Double) {
            self.playfulness = Self.unit(playfulness)
            self.sociability = Self.unit(sociability)
            self.calmness = Self.unit(calmness)
            self.appetite = Self.unit(appetite)
            self.sleepiness = Self.unit(sleepiness)
            self.curiosity = Self.unit(curiosity)
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = Self.balanced
            self.init(
                playfulness: try values.decodeIfPresent(Double.self, forKey: .playfulness) ?? fallback.playfulness,
                sociability: try values.decodeIfPresent(Double.self, forKey: .sociability) ?? fallback.sociability,
                calmness: try values.decodeIfPresent(Double.self, forKey: .calmness) ?? fallback.calmness,
                appetite: try values.decodeIfPresent(Double.self, forKey: .appetite) ?? fallback.appetite,
                sleepiness: try values.decodeIfPresent(Double.self, forKey: .sleepiness) ?? fallback.sleepiness,
                curiosity: try values.decodeIfPresent(Double.self, forKey: .curiosity) ?? fallback.curiosity
            )
        }

        private static func unit(_ value: Double) -> Double { min(1, max(0, value)) }
    }

    struct ToyDefinition: Codable, Equatable {
        var id: String
        var kind: PetToyKind
        var label: String?
        var enabled: Bool

        init(id: String, kind: PetToyKind, label: String? = nil, enabled: Bool = true) {
            self.id = id
            self.kind = kind
            self.label = label
            self.enabled = enabled
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            kind = try values.decode(PetToyKind.self, forKey: .kind)
            label = try values.decodeIfPresent(String.self, forKey: .label)
            enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
    }

    struct ExtensionDefinition: Codable, Equatable {
        var id: String
        var kind: String
        var path: String
        var minimumAppVersion: String?

        enum CodingKeys: String, CodingKey {
            case id, kind, path
            case minimumAppVersion = "minimum_app_version"
        }
    }

    struct PetProfile: Codable, Equatable {
        var species: PetSpecies
        var breed: String?
        var bodyTraits: [String]
        var identityFeatures: [String]
        var motionNotes: [String]

        enum CodingKeys: String, CodingKey {
            case species
            case breed
            case bodyTraits = "body_traits"
            case identityFeatures = "identity_features"
            case motionNotes = "motion_notes"
        }

        static let genericCat = PetProfile(
            species: .cat,
            breed: nil,
            bodyTraits: [],
            identityFeatures: [],
            motionNotes: []
        )

        init(
            species: PetSpecies,
            breed: String? = nil,
            bodyTraits: [String] = [],
            identityFeatures: [String] = [],
            motionNotes: [String] = []
        ) {
            self.species = species
            self.breed = breed
            self.bodyTraits = bodyTraits
            self.identityFeatures = identityFeatures
            self.motionNotes = motionNotes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            species = try container.decodeIfPresent(PetSpecies.self, forKey: .species) ?? .cat
            breed = try container.decodeIfPresent(String.self, forKey: .breed)
            bodyTraits = try container.decodeIfPresent([String].self, forKey: .bodyTraits) ?? []
            identityFeatures = try container.decodeIfPresent([String].self, forKey: .identityFeatures) ?? []
            motionNotes = try container.decodeIfPresent([String].self, forKey: .motionNotes) ?? []
        }
    }

    struct StaticPoses: Codable, Equatable {
        var resting: String
        var held: String
        var dialogue: String
        var transition: String

        enum CodingKeys: String, CodingKey {
            case resting
            case held
            case dialogue
            case transition
        }

        enum LegacyCodingKeys: String, CodingKey {
            case stand
            case stretch
        }

        init(resting: String, held: String, dialogue: String, transition: String) {
            self.resting = resting
            self.held = held
            self.dialogue = dialogue
            self.transition = transition
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
            resting = try container.decodeIfPresent(String.self, forKey: .resting) ?? "poses/resting"
            held = try container.decodeIfPresent(String.self, forKey: .held) ?? "poses/held"
            dialogue = try container.decodeIfPresent(String.self, forKey: .dialogue)
                ?? legacyContainer.decodeIfPresent(String.self, forKey: .stand)
                ?? "poses/dialogue"
            transition = try container.decodeIfPresent(String.self, forKey: .transition)
                ?? legacyContainer.decodeIfPresent(String.self, forKey: .stretch)
                ?? "poses/transition"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(resting, forKey: .resting)
            try container.encode(held, forKey: .held)
            try container.encode(dialogue, forKey: .dialogue)
            try container.encode(transition, forKey: .transition)
        }
    }

    struct Animation: Codable, Equatable {
        var fps: Double
        var frames: [String]
        var playbackLoops: Int?
        var autonomousWeight: Double?
        var sleep: Bool?

        enum CodingKeys: String, CodingKey {
            case fps
            case frames
            case playbackLoops = "playback_loops"
            case autonomousWeight = "autonomous_weight"
            case sleep
        }

        init(
            fps: Double,
            frames: [String] = [],
            playbackLoops: Int? = nil,
            autonomousWeight: Double? = nil,
            sleep: Bool? = nil
        ) {
            self.fps = fps
            self.frames = frames
            self.playbackLoops = playbackLoops
            self.autonomousWeight = autonomousWeight
            self.sleep = sleep
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fps = max(0.1, try container.decodeIfPresent(Double.self, forKey: .fps) ?? 6)
            frames = try container.decodeIfPresent([String].self, forKey: .frames) ?? []
            playbackLoops = try container.decodeIfPresent(Int.self, forKey: .playbackLoops)
            autonomousWeight = try container.decodeIfPresent(Double.self, forKey: .autonomousWeight)
            sleep = try container.decodeIfPresent(Bool.self, forKey: .sleep)
        }
    }

    struct Animations: Codable, Equatable {
        var walk: Animation
        var behaviors: [String: Animation]

        init(walk: Animation, behaviors: [String: Animation] = [:]) {
            self.walk = walk
            self.behaviors = behaviors
        }

        enum CodingKeys: String, CodingKey {
            case walk
            case behaviors
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            walk = try container.decodeIfPresent(Animation.self, forKey: .walk)
                ?? Animation(fps: 3, frames: [])
            behaviors = try container.decodeIfPresent([String: Animation].self, forKey: .behaviors) ?? [:]
        }
    }

    struct AppIcons: Codable, Equatable {
        var sleep: String
        var empty: String
    }

    struct Anchor: Codable, Equatable {
        var x: Double
        var y: Double
    }

    var id: String
    var schemaVersion: Int
    var name: String
    var author: String
    var profile: PetProfile
    var canvasWidth: Int
    var canvasHeight: Int
    var defaultAnchor: Anchor
    var poses: StaticPoses
    var animations: Animations
    var appIcons: AppIcons? = nil
    var personality: Personality
    var toys: [ToyDefinition]
    var extensions: [ExtensionDefinition]

    enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion = "schema_version"
        case name
        case author
        case profile
        case canvasWidth = "canvas_width"
        case canvasHeight = "canvas_height"
        case defaultAnchor = "default_anchor"
        case poses
        case animations
        case appIcons = "app_icons"
        case personality
        case toys
        case extensions
    }

    init(
        id: String,
        schemaVersion: Int = 2,
        name: String,
        author: String,
        profile: PetProfile = .genericCat,
        canvasWidth: Int,
        canvasHeight: Int,
        defaultAnchor: Anchor,
        poses: StaticPoses,
        animations: Animations,
        appIcons: AppIcons? = nil,
        personality: Personality = .balanced,
        toys: [ToyDefinition] = PetToyKind.allCases.map { ToyDefinition(id: $0.rawValue, kind: $0) },
        extensions: [ExtensionDefinition] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.author = author
        self.profile = profile
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.defaultAnchor = defaultAnchor
        self.poses = poses
        self.animations = animations
        self.appIcons = appIcons
        self.personality = personality
        self.toys = toys
        self.extensions = extensions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        schemaVersion = max(1, try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decode(String.self, forKey: .author)
        profile = try container.decodeIfPresent(PetProfile.self, forKey: .profile) ?? .genericCat
        canvasWidth = try container.decode(Int.self, forKey: .canvasWidth)
        canvasHeight = try container.decode(Int.self, forKey: .canvasHeight)
        defaultAnchor = try container.decode(Anchor.self, forKey: .defaultAnchor)
        poses = try container.decodeIfPresent(StaticPoses.self, forKey: .poses)
            ?? StaticPoses(resting: "poses/resting", held: "poses/held", dialogue: "poses/dialogue", transition: "poses/transition")
        animations = try container.decodeIfPresent(Animations.self, forKey: .animations)
            ?? Animations(walk: Animation(fps: 3, frames: []))
        appIcons = try container.decodeIfPresent(AppIcons.self, forKey: .appIcons)
        personality = try container.decodeIfPresent(Personality.self, forKey: .personality) ?? .balanced
        toys = try container.decodeIfPresent([ToyDefinition].self, forKey: .toys)
            ?? PetToyKind.allCases.map { ToyDefinition(id: $0.rawValue, kind: $0) }
        extensions = try container.decodeIfPresent([ExtensionDefinition].self, forKey: .extensions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(name, forKey: .name)
        try container.encode(author, forKey: .author)
        try container.encode(profile, forKey: .profile)
        try container.encode(canvasWidth, forKey: .canvasWidth)
        try container.encode(canvasHeight, forKey: .canvasHeight)
        try container.encode(defaultAnchor, forKey: .defaultAnchor)
        try container.encode(poses, forKey: .poses)
        try container.encode(animations, forKey: .animations)
        try container.encodeIfPresent(appIcons, forKey: .appIcons)
        try container.encode(personality, forKey: .personality)
        try container.encode(toys, forKey: .toys)
        try container.encode(extensions, forKey: .extensions)
    }
}
