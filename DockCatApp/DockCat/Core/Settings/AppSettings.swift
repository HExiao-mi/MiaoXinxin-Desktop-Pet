import Foundation

enum CatActivityScope: String, Codable, Equatable, Hashable, CaseIterable {
    case dockEdge
    case desktop
}

enum PetBehaviorMode: String, Codable, Equatable, Hashable, CaseIterable {
    case random
    case resting
    case walking
    case playToy
    case grooming
    case bellyRoll
    case sleepCurled
    case sleepSide
    case sleepLoaf
    case eating
    case drinking
    case signatureMove
}

enum PetToyKind: String, Codable, Equatable, Hashable, CaseIterable {
    case ball
    case laser
    case wand
    case box
    case food
    case water
}

enum PetPreferenceToggle {
    case quietMode
    case reducedMotion
    case batterySaver
    case hideDuringFullscreen
    case launchAtLogin
}

enum PetLifeEvent {
    case pet
    case play
    case eat
    case drink
    case sleep
    case wake
}

/// A deliberately forgiving local simulation: low meters influence behavior but
/// never punish the user or make the pet ill/disappear.
struct PetLifeState: Codable, Equatable {
    var energy: Double = 82
    var fullness: Double = 78
    var hydration: Double = 80
    var mood: Double = 86
    var affection: Double = 50
    var curiosity: Double = 72
    var lastUpdated: Date = Date()
    var adoptionDate: Date = Date()
    var lastInteractionDate: Date? = nil
    var interactions: Int = 0
    var playCount: Int = 0
    var meals: Int = 0
    var drinks: Int = 0
    var sleeps: Int = 0
    var favoriteToy: PetToyKind? = nil
    var toyPlayCounts: [PetToyKind: Int] = [:]

    enum CodingKeys: String, CodingKey {
        case energy, fullness, hydration, mood, affection, curiosity
        case lastUpdated, adoptionDate, lastInteractionDate, interactions
        case playCount, meals, drinks, sleeps, favoriteToy, toyPlayCounts
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        energy = try values.decodeIfPresent(Double.self, forKey: .energy) ?? 82
        fullness = try values.decodeIfPresent(Double.self, forKey: .fullness) ?? 78
        hydration = try values.decodeIfPresent(Double.self, forKey: .hydration) ?? 80
        mood = try values.decodeIfPresent(Double.self, forKey: .mood) ?? 86
        affection = try values.decodeIfPresent(Double.self, forKey: .affection) ?? 50
        curiosity = try values.decodeIfPresent(Double.self, forKey: .curiosity) ?? 72
        lastUpdated = try values.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
        adoptionDate = try values.decodeIfPresent(Date.self, forKey: .adoptionDate) ?? Date()
        lastInteractionDate = try values.decodeIfPresent(Date.self, forKey: .lastInteractionDate)
        interactions = try values.decodeIfPresent(Int.self, forKey: .interactions) ?? 0
        playCount = try values.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        meals = try values.decodeIfPresent(Int.self, forKey: .meals) ?? 0
        drinks = try values.decodeIfPresent(Int.self, forKey: .drinks) ?? 0
        sleeps = try values.decodeIfPresent(Int.self, forKey: .sleeps) ?? 0
        favoriteToy = try values.decodeIfPresent(PetToyKind.self, forKey: .favoriteToy)
        toyPlayCounts = try values.decodeIfPresent([PetToyKind: Int].self, forKey: .toyPlayCounts) ?? [:]
        clampAll()
    }

    mutating func advance(to date: Date = Date(), sleeping: Bool) {
        let elapsedHours = max(0, min(24, date.timeIntervalSince(lastUpdated) / 3_600))
        guard elapsedHours > 0 else { return }
        if sleeping {
            energy += elapsedHours * 13
            fullness -= elapsedHours * 1.3
            hydration -= elapsedHours * 1.6
        } else {
            energy -= elapsedHours * 3.2
            fullness -= elapsedHours * 2.1
            hydration -= elapsedHours * 2.6
            curiosity += elapsedHours * 1.1
        }
        if fullness < 30 || hydration < 30 || energy < 20 { mood -= elapsedHours * 1.8 }
        clampAll()
        lastUpdated = date
    }

    mutating func apply(_ event: PetLifeEvent, toy: PetToyKind? = nil, at date: Date = Date()) {
        lastInteractionDate = date
        switch event {
        case .pet:
            affection += 2.5
            mood += 4
            interactions += 1
        case .play:
            energy -= 5
            mood += 7
            curiosity -= 10
            playCount += 1
            if let toy {
                toyPlayCounts[toy, default: 0] += 1
                favoriteToy = toyPlayCounts.max(by: { $0.value < $1.value })?.key
            }
        case .eat:
            fullness += 34
            mood += 3
            meals += 1
        case .drink:
            hydration += 42
            mood += 2
            drinks += 1
        case .sleep:
            sleeps += 1
        case .wake:
            mood += 1
        }
        clampAll()
    }

    private mutating func clampAll() {
        energy = Self.clamp(energy)
        fullness = Self.clamp(fullness)
        hydration = Self.clamp(hydration)
        mood = Self.clamp(mood)
        affection = Self.clamp(affection)
        curiosity = Self.clamp(curiosity)
    }

    private static func clamp(_ value: Double) -> Double { min(100, max(5, value)) }
}

struct AppSettings: Codable, Equatable {
    var language: AppLanguage
    var catName: String
    var catIdentifier: String
    var userSalutation: String
    var selectedAssetPackID: String
    var remindersEnabled: Bool
    var waterReminderInterval: TimeInterval
    var waterReminderMessageSuffix: String
    var movementReminderInterval: TimeInterval
    var movementReminderMessageSuffix: String
    var customReminderEnabled: Bool
    var customReminderInterval: TimeInterval
    var customReminderMessageSuffix: String
    var outingDepartureMessageSuffix: String
    var defaultOutingDuration: TimeInterval
    var restDurationMinimum: TimeInterval
    var restDurationMaximum: TimeInterval
    var walkDurationMinimum: TimeInterval
    var walkDurationMaximum: TimeInterval
    var walkBaseSpeed: Double
    var catScalePercent: Double
    var startPositionPercent: Double
    var catActivityScope: CatActivityScope
    var activityDisplayID: UInt32?
    var activeOutingEndDate: Date?
    var activeOutingDuration: TimeInterval?
    var petBehaviorMode: PetBehaviorMode
    var lifeSimulationEnabled: Bool
    var naturalScheduleEnabled: Bool
    var quietMode: Bool
    var reducedMotion: Bool
    var batterySaverEnabled: Bool
    var hideDuringFullscreen: Bool
    var launchAtLogin: Bool
    var desktopToysEnabled: Bool
    var automaticUpdateChecks: Bool
    var lastUpdateCheckDate: Date?
    var petLife: PetLifeState

    func reminderMessageSuffix(for type: ReminderType) -> String {
        switch type {
        case .water:
            return waterReminderMessageSuffix
        case .movement:
            return movementReminderMessageSuffix
        case .custom:
            return customReminderMessageSuffix
        }
    }

    mutating func applyLanguageChangePreservingCustomText(to newLanguage: AppLanguage) {
        let oldLanguage = language
        guard oldLanguage != newLanguage else { return }
        let oldDefaults = AppSettings.defaults(for: oldLanguage)
        let newDefaults = AppSettings.defaults(for: newLanguage)
        if waterReminderMessageSuffix == oldDefaults.waterReminderMessageSuffix {
            waterReminderMessageSuffix = newDefaults.waterReminderMessageSuffix
        }
        if movementReminderMessageSuffix == oldDefaults.movementReminderMessageSuffix {
            movementReminderMessageSuffix = newDefaults.movementReminderMessageSuffix
        }
        if customReminderMessageSuffix == oldDefaults.customReminderMessageSuffix {
            customReminderMessageSuffix = newDefaults.customReminderMessageSuffix
        }
        if outingDepartureMessageSuffix == oldDefaults.outingDepartureMessageSuffix {
            outingDepartureMessageSuffix = newDefaults.outingDepartureMessageSuffix
        }
        language = newLanguage
    }

    enum CodingKeys: String, CodingKey {
        case language
        case catName
        case catIdentifier
        case userSalutation
        case selectedAssetPackID
        case remindersEnabled
        case waterReminderInterval
        case waterReminderMessageSuffix
        case movementReminderInterval
        case movementReminderMessageSuffix
        case customReminderEnabled
        case customReminderInterval
        case customReminderMessageSuffix
        case outingDepartureMessageSuffix
        case defaultOutingDuration
        case restDurationMinimum
        case restDurationMaximum
        case walkDurationMinimum
        case walkDurationMaximum
        case walkBaseSpeed
        case catScalePercent
        case startPositionPercent
        case catActivityScope
        case activityDisplayID
        case activeOutingEndDate
        case activeOutingDuration
        case petBehaviorMode
        case lifeSimulationEnabled
        case naturalScheduleEnabled
        case quietMode
        case reducedMotion
        case batterySaverEnabled
        case hideDuringFullscreen
        case launchAtLogin
        case desktopToysEnabled
        case automaticUpdateChecks
        case lastUpdateCheckDate
        case petLife
    }

    enum LegacyCodingKeys: String, CodingKey {
        case standReminderInterval
        case outingDepartureMessageTemplate
    }

    static let defaults = AppSettings(
        language: .chinese,
        catName: "喵心心",
        catIdentifier: "MiaoXinxin",
        userSalutation: "主人",
        selectedAssetPackID: "default-lizz",
        remindersEnabled: true,
        waterReminderInterval: 30 * 60,
        waterReminderMessageSuffix: "该喝水啦",
        movementReminderInterval: 60 * 60,
        movementReminderMessageSuffix: "该起来走走啦",
        customReminderEnabled: false,
        customReminderInterval: 30 * 60,
        customReminderMessageSuffix: "休息一下吧",
        outingDepartureMessageSuffix: "工作要加油呀！",
        defaultOutingDuration: 25 * 60,
        restDurationMinimum: 2 * 60,
        restDurationMaximum: 5 * 60,
        walkDurationMinimum: 2 * 60,
        walkDurationMaximum: 5 * 60,
        walkBaseSpeed: 36,
        catScalePercent: 15,
        startPositionPercent: 75,
        catActivityScope: .dockEdge,
        activityDisplayID: nil,
        activeOutingEndDate: nil,
        activeOutingDuration: nil,
        petBehaviorMode: .random,
        lifeSimulationEnabled: true,
        naturalScheduleEnabled: true,
        quietMode: false,
        reducedMotion: false,
        batterySaverEnabled: true,
        hideDuringFullscreen: true,
        launchAtLogin: false,
        desktopToysEnabled: true,
        automaticUpdateChecks: true,
        lastUpdateCheckDate: nil,
        petLife: PetLifeState()
    )

    static func defaults(for language: AppLanguage) -> AppSettings {
        switch language {
        case .chinese:
            return .defaults
        case .english:
            return AppSettings(
                language: .english,
                catName: "Miao Xinxin",
                catIdentifier: "MiaoXinxin",
                userSalutation: "Friend",
                selectedAssetPackID: "default-lizz",
                remindersEnabled: true,
                waterReminderInterval: 30 * 60,
                waterReminderMessageSuffix: "time to drink some water.",
                movementReminderInterval: 60 * 60,
                movementReminderMessageSuffix: "time to stand up a bit.",
                customReminderEnabled: false,
                customReminderInterval: 30 * 60,
                customReminderMessageSuffix: "take a short break.",
                outingDepartureMessageSuffix: "Good luck with your work!",
                defaultOutingDuration: 25 * 60,
                restDurationMinimum: 2 * 60,
                restDurationMaximum: 5 * 60,
                walkDurationMinimum: 2 * 60,
                walkDurationMaximum: 5 * 60,
                walkBaseSpeed: 36,
                catScalePercent: 15,
                startPositionPercent: 75,
                catActivityScope: .dockEdge,
                activityDisplayID: nil,
                activeOutingEndDate: nil,
                activeOutingDuration: nil,
                petBehaviorMode: .random,
                lifeSimulationEnabled: true,
                naturalScheduleEnabled: true,
                quietMode: false,
                reducedMotion: false,
                batterySaverEnabled: true,
                hideDuringFullscreen: true,
                launchAtLogin: false,
                desktopToysEnabled: true,
                automaticUpdateChecks: true,
                lastUpdateCheckDate: nil,
                petLife: PetLifeState()
            )
        }
    }

    init(
        language: AppLanguage,
        catName: String,
        catIdentifier: String,
        userSalutation: String,
        selectedAssetPackID: String,
        remindersEnabled: Bool,
        waterReminderInterval: TimeInterval,
        waterReminderMessageSuffix: String,
        movementReminderInterval: TimeInterval,
        movementReminderMessageSuffix: String,
        customReminderEnabled: Bool,
        customReminderInterval: TimeInterval,
        customReminderMessageSuffix: String,
        outingDepartureMessageSuffix: String,
        defaultOutingDuration: TimeInterval,
        restDurationMinimum: TimeInterval,
        restDurationMaximum: TimeInterval,
        walkDurationMinimum: TimeInterval,
        walkDurationMaximum: TimeInterval,
        walkBaseSpeed: Double,
        catScalePercent: Double,
        startPositionPercent: Double,
        catActivityScope: CatActivityScope,
        activityDisplayID: UInt32?,
        activeOutingEndDate: Date?,
        activeOutingDuration: TimeInterval?,
        petBehaviorMode: PetBehaviorMode = .random,
        lifeSimulationEnabled: Bool = true,
        naturalScheduleEnabled: Bool = true,
        quietMode: Bool = false,
        reducedMotion: Bool = false,
        batterySaverEnabled: Bool = true,
        hideDuringFullscreen: Bool = true,
        launchAtLogin: Bool = false,
        desktopToysEnabled: Bool = true,
        automaticUpdateChecks: Bool = true,
        lastUpdateCheckDate: Date? = nil,
        petLife: PetLifeState = PetLifeState()
    ) {
        self.language = language
        self.catName = catName
        self.catIdentifier = catIdentifier
        self.userSalutation = userSalutation
        self.selectedAssetPackID = selectedAssetPackID
        self.remindersEnabled = remindersEnabled
        self.waterReminderInterval = waterReminderInterval
        self.waterReminderMessageSuffix = waterReminderMessageSuffix
        self.movementReminderInterval = movementReminderInterval
        self.movementReminderMessageSuffix = movementReminderMessageSuffix
        self.customReminderEnabled = customReminderEnabled
        self.customReminderInterval = customReminderInterval
        self.customReminderMessageSuffix = customReminderMessageSuffix
        self.outingDepartureMessageSuffix = outingDepartureMessageSuffix
        self.defaultOutingDuration = defaultOutingDuration
        self.restDurationMinimum = restDurationMinimum
        self.restDurationMaximum = restDurationMaximum
        self.walkDurationMinimum = walkDurationMinimum
        self.walkDurationMaximum = walkDurationMaximum
        self.walkBaseSpeed = walkBaseSpeed
        self.catScalePercent = catScalePercent
        self.startPositionPercent = startPositionPercent
        self.catActivityScope = catActivityScope
        self.activityDisplayID = activityDisplayID
        self.activeOutingEndDate = activeOutingEndDate
        self.activeOutingDuration = activeOutingDuration
        self.petBehaviorMode = petBehaviorMode
        self.lifeSimulationEnabled = lifeSimulationEnabled
        self.naturalScheduleEnabled = naturalScheduleEnabled
        self.quietMode = quietMode
        self.reducedMotion = reducedMotion
        self.batterySaverEnabled = batterySaverEnabled
        self.hideDuringFullscreen = hideDuringFullscreen
        self.launchAtLogin = launchAtLogin
        self.desktopToysEnabled = desktopToysEnabled
        self.automaticUpdateChecks = automaticUpdateChecks
        self.lastUpdateCheckDate = lastUpdateCheckDate
        self.petLife = petLife
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? AppSettings.defaults.language
        let defaults = AppSettings.defaults(for: language)
        catName = try container.decodeIfPresent(String.self, forKey: .catName) ?? defaults.catName
        catIdentifier = try container.decodeIfPresent(String.self, forKey: .catIdentifier) ?? defaults.catIdentifier
        userSalutation = try container.decodeIfPresent(String.self, forKey: .userSalutation) ?? defaults.userSalutation
        selectedAssetPackID = try container.decodeIfPresent(String.self, forKey: .selectedAssetPackID) ?? defaults.selectedAssetPackID
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? defaults.remindersEnabled
        waterReminderInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .waterReminderInterval) ?? defaults.waterReminderInterval
        waterReminderMessageSuffix = try container.decodeIfPresent(String.self, forKey: .waterReminderMessageSuffix) ?? defaults.waterReminderMessageSuffix
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        movementReminderInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .movementReminderInterval)
            ?? legacyContainer.decodeIfPresent(TimeInterval.self, forKey: .standReminderInterval)
            ?? defaults.movementReminderInterval
        movementReminderMessageSuffix = try container.decodeIfPresent(String.self, forKey: .movementReminderMessageSuffix) ?? defaults.movementReminderMessageSuffix
        customReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .customReminderEnabled) ?? defaults.customReminderEnabled
        customReminderInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .customReminderInterval) ?? defaults.customReminderInterval
        customReminderMessageSuffix = try container.decodeIfPresent(String.self, forKey: .customReminderMessageSuffix) ?? defaults.customReminderMessageSuffix
        let decodedOutingSuffix = try container.decodeIfPresent(String.self, forKey: .outingDepartureMessageSuffix)
            ?? legacyContainer.decodeIfPresent(String.self, forKey: .outingDepartureMessageTemplate)
        outingDepartureMessageSuffix = Self.normalizedOutingDepartureMessageSuffix(
            decodedOutingSuffix,
            language: language,
            fallback: defaults.outingDepartureMessageSuffix
        )
        defaultOutingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .defaultOutingDuration) ?? defaults.defaultOutingDuration
        restDurationMinimum = try container.decodeIfPresent(TimeInterval.self, forKey: .restDurationMinimum) ?? defaults.restDurationMinimum
        restDurationMaximum = try container.decodeIfPresent(TimeInterval.self, forKey: .restDurationMaximum) ?? defaults.restDurationMaximum
        walkDurationMinimum = try container.decodeIfPresent(TimeInterval.self, forKey: .walkDurationMinimum) ?? defaults.walkDurationMinimum
        walkDurationMaximum = try container.decodeIfPresent(TimeInterval.self, forKey: .walkDurationMaximum) ?? defaults.walkDurationMaximum
        walkBaseSpeed = try container.decodeIfPresent(Double.self, forKey: .walkBaseSpeed) ?? defaults.walkBaseSpeed
        catScalePercent = try container.decodeIfPresent(Double.self, forKey: .catScalePercent) ?? defaults.catScalePercent
        startPositionPercent = try container.decodeIfPresent(Double.self, forKey: .startPositionPercent) ?? defaults.startPositionPercent
        catActivityScope = try container.decodeIfPresent(CatActivityScope.self, forKey: .catActivityScope) ?? defaults.catActivityScope
        activityDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .activityDisplayID)
        activeOutingEndDate = try container.decodeIfPresent(Date.self, forKey: .activeOutingEndDate)
        activeOutingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .activeOutingDuration)
        petBehaviorMode = try container.decodeIfPresent(PetBehaviorMode.self, forKey: .petBehaviorMode) ?? defaults.petBehaviorMode
        lifeSimulationEnabled = try container.decodeIfPresent(Bool.self, forKey: .lifeSimulationEnabled) ?? defaults.lifeSimulationEnabled
        naturalScheduleEnabled = try container.decodeIfPresent(Bool.self, forKey: .naturalScheduleEnabled) ?? defaults.naturalScheduleEnabled
        quietMode = try container.decodeIfPresent(Bool.self, forKey: .quietMode) ?? defaults.quietMode
        reducedMotion = try container.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? defaults.reducedMotion
        batterySaverEnabled = try container.decodeIfPresent(Bool.self, forKey: .batterySaverEnabled) ?? defaults.batterySaverEnabled
        hideDuringFullscreen = try container.decodeIfPresent(Bool.self, forKey: .hideDuringFullscreen) ?? defaults.hideDuringFullscreen
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        desktopToysEnabled = try container.decodeIfPresent(Bool.self, forKey: .desktopToysEnabled) ?? defaults.desktopToysEnabled
        automaticUpdateChecks = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecks) ?? defaults.automaticUpdateChecks
        lastUpdateCheckDate = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheckDate)
        petLife = try container.decodeIfPresent(PetLifeState.self, forKey: .petLife) ?? defaults.petLife
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language, forKey: .language)
        try container.encode(catName, forKey: .catName)
        try container.encode(catIdentifier, forKey: .catIdentifier)
        try container.encode(userSalutation, forKey: .userSalutation)
        try container.encode(selectedAssetPackID, forKey: .selectedAssetPackID)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
        try container.encode(waterReminderInterval, forKey: .waterReminderInterval)
        try container.encode(waterReminderMessageSuffix, forKey: .waterReminderMessageSuffix)
        try container.encode(movementReminderInterval, forKey: .movementReminderInterval)
        try container.encode(movementReminderMessageSuffix, forKey: .movementReminderMessageSuffix)
        try container.encode(customReminderEnabled, forKey: .customReminderEnabled)
        try container.encode(customReminderInterval, forKey: .customReminderInterval)
        try container.encode(customReminderMessageSuffix, forKey: .customReminderMessageSuffix)
        try container.encode(outingDepartureMessageSuffix, forKey: .outingDepartureMessageSuffix)
        try container.encode(defaultOutingDuration, forKey: .defaultOutingDuration)
        try container.encode(restDurationMinimum, forKey: .restDurationMinimum)
        try container.encode(restDurationMaximum, forKey: .restDurationMaximum)
        try container.encode(walkDurationMinimum, forKey: .walkDurationMinimum)
        try container.encode(walkDurationMaximum, forKey: .walkDurationMaximum)
        try container.encode(walkBaseSpeed, forKey: .walkBaseSpeed)
        try container.encode(catScalePercent, forKey: .catScalePercent)
        try container.encode(startPositionPercent, forKey: .startPositionPercent)
        try container.encode(catActivityScope, forKey: .catActivityScope)
        try container.encodeIfPresent(activityDisplayID, forKey: .activityDisplayID)
        try container.encodeIfPresent(activeOutingEndDate, forKey: .activeOutingEndDate)
        try container.encodeIfPresent(activeOutingDuration, forKey: .activeOutingDuration)
        try container.encode(petBehaviorMode, forKey: .petBehaviorMode)
        try container.encode(lifeSimulationEnabled, forKey: .lifeSimulationEnabled)
        try container.encode(naturalScheduleEnabled, forKey: .naturalScheduleEnabled)
        try container.encode(quietMode, forKey: .quietMode)
        try container.encode(reducedMotion, forKey: .reducedMotion)
        try container.encode(batterySaverEnabled, forKey: .batterySaverEnabled)
        try container.encode(hideDuringFullscreen, forKey: .hideDuringFullscreen)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(desktopToysEnabled, forKey: .desktopToysEnabled)
        try container.encode(automaticUpdateChecks, forKey: .automaticUpdateChecks)
        try container.encodeIfPresent(lastUpdateCheckDate, forKey: .lastUpdateCheckDate)
        try container.encode(petLife, forKey: .petLife)
    }

    static func normalizedOutingDepartureMessageSuffix(
        _ rawValue: String?,
        language: AppLanguage,
        fallback: String
    ) -> String {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }

        let defaultTemplatePrefix: String
        switch language {
        case .chinese:
            defaultTemplatePrefix = "我出门啦，{salutation}"
        case .english:
            defaultTemplatePrefix = "I'm heading out, {salutation}. "
        }
        if value.hasPrefix(defaultTemplatePrefix) {
            value.removeFirst(defaultTemplatePrefix.count)
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
    }
}
