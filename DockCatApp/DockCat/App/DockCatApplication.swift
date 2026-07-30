import AppKit
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class DockCatApplication: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let usageStatisticsStore = UsageStatisticsStore()
    private let collectableInventoryStore = CollectableInventoryStore()
    private let userDataBackupStore = UserDataBackupStore()
    private let outingCatalogLoader = OutingCatalogLoader()
    private let giftCodeRedeemer = GiftCodeRedeemer()
    private let outingWakeResolver = OutingWakeResolver()
    private let assetLoader = AssetPackLoader()
    private let stateScheduler = StateScheduler()
    private let dockObserver = DockObserver()
    private let appIconStore = AppIconStore()
    private let iconController = AppIconController()
    private let dockMenuController = DockMenuController()
    private let catMenuController = CatMenuController()
    private let walkAnimator = SpriteAnimator()
    private let idleActivityAnimator = SpriteAnimator()
    private let desktopToyController = DesktopToyController()
    private let updateChecker = GitHubUpdateChecker()

    private var settings: AppSettings = .defaults
    private var activitySpace = DockGeometry.currentActivitySpace(
        activityDisplayID: AppSettings.defaults.activityDisplayID,
        startPositionPercent: AppSettings.defaults.startPositionPercent
    )
    private var outingCatalog: OutingCatalog = .empty
    private var collectableInventory: CollectableInventory = .empty
    private var defaultAssetPack: CatAssetPack!
    private var assetPack: CatAssetPack!
    private var renderer: PoseRenderer!
    private var catWindow: CatWindowController!
    private var interactionController: CatInteractionController!
    private var stateMachine: CatStateMachine!
    private var reminderScheduler: ReminderScheduler!
    private var settingsWindowController: SettingsWindowController!
    private var usageSessionTracker: UsageSessionTracker!
    private var reminderTimer: Timer?
    private var outingTimer: Timer?
    private var startupTimer: Timer?
    private var walkMovementTimer: Timer?
    private var idleActivityTimer: Timer?
    private var idleActivityEndTimer: Timer?
    private var cursorTrackingTimer: Timer?
    private var laserReactionResumeTimer: Timer?
    private var lifeTimer: Timer?
    private var environmentTimer: Timer?
    private var stateEndDate: Date?
    private var walkDirection: CGFloat = 1
    private var isIdleActivityPlaying = false
    private var idleActivityCompletion: (() -> Void)?
    private var currentLookFrameIndex: Int?
    private var currentIdleActivity: IdleActivity?
    private var isTrackingLaser = false
    private var wasPetVisibleBeforeSuppression = false
    private var isEnvironmentSuppressed = false
    private var lastToyReactionDate = Date.distantPast
    private var pendingOutingDuration: TimeInterval?
    private var pendingOutingReturnReward: OutingReward?
    private var shouldUseStartPositionForNextTransition = false
    private var giftCodeInputWindow: NSWindow?
    private var giftCodeSuccessWindow: NSWindow?
    private var giftCodeCallbackTargets: [CallbackTarget] = []

    private var strings: AppStrings {
        AppStrings(language: settings.language)
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }

    private var behaviorCatalog: PetBehaviorCatalog {
        PetBehaviorCatalog(profile: assetPack.manifest.profile, animations: assetPack.manifest.animations)
    }

    private var allowsDefaultAnimationFallback: Bool {
        assetPack.id == defaultAssetPack.id
    }

    private var availableBehaviorModes: [PetBehaviorMode] {
        guard renderer != nil, assetPack != nil, defaultAssetPack != nil else {
            return [.random, .resting]
        }
        var modes: [PetBehaviorMode] = [.random, .resting]
        if renderer.hasAnimation(named: "walk", includeFallback: allowsDefaultAnimationFallback) {
            modes.append(.walking)
        }
        for mode in PetBehaviorMode.allCases where !modes.contains(mode) {
            guard let descriptor = behaviorCatalog.descriptor(for: mode) else { continue }
            if renderer.hasAnimation(named: descriptor.assetName, includeFallback: allowsDefaultAnimationFallback) {
                modes.append(mode)
            }
        }
        return modes
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RuntimeDiagnostics.record("applicationDidFinishLaunching")
        settings = settingsStore.load()
        activitySpace = currentActivitySpace()
        outingCatalog = outingCatalogLoader.loadCatalog()
        collectableInventory = collectableInventoryStore.load()
        configureUsageSessionTracker()
        assetLoader.prepareCustomPacksDirectory(refreshDefaultPackBackup: true)
        defaultAssetPack = assetLoader.loadDefaultPack()
        assetPack = assetLoader.loadSelectedPack(selectedID: settings.selectedAssetPackID)
        RuntimeDiagnostics.record("loaded assetPack id=\(assetPack.id) root=\(assetPack.rootURL.path)")
        iconController.updateIconSource(appIconStore.prepareActiveIconSource(selectedPack: assetPack))
        iconController.applyPersistentFileIconIfNeeded()
        renderer = PoseRenderer(pack: assetPack, fallbackPack: defaultAssetPack)
        reminderScheduler = ReminderScheduler(settings: settings)
        catWindow = CatWindowController()
        settingsWindowController = SettingsWindowController(
            store: settingsStore,
            settings: settings,
            usageStatistics: usageSessionTracker.snapshot,
            outingCatalog: outingCatalog,
            collectableInventory: collectableInventory,
            dialogueImage: renderer.randomPose(for: .dialogue).image
        )
        configureSettingsAssetPackActions()
        catWindow.setImageScale(percent: settings.catScalePercent)
        configureStateMachine()
        configureInteraction()
        configureMenus()
        configureApplicationMenu()
        configureDockObserver()
        configureCompanionEnvironment()
        RuntimeDiagnostics.record("activitySpace frame=\(activitySpace.screenFrame) visible=\(activitySpace.visibleFrame) edge=\(activitySpace.dockEdge) entrance=\(activitySpace.entrancePoint)")
        iconController.showSleepIcon()
        catWindow.hide()
#if DEBUG
        if showDebugCursorLookPreviewIfRequested() {
            startReminderPolling()
            return
        }
        if showDebugIdleActivityPreviewIfRequested() {
            startReminderPolling()
            return
        }
        if showDebugOutingGiftPreviewIfRequested() {
            startReminderPolling()
            return
        }
#endif
        if !restoreActiveOutingIfNeeded() {
            if settings.petBehaviorMode == .random {
                scheduleStartupStretch()
            } else {
                applyConfiguredBehaviorMode()
            }
        }
        if !stateMachine.state.isOuting {
            startReminderPolling()
        }
        startCompanionTimers()
        if !isRunningTests { checkForUpdatesIfDue() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        iconController.showSleepIcon()
        clearInterruptedOutingIfNeeded()
        startupTimer?.invalidate()
        reminderTimer?.invalidate()
        outingTimer?.invalidate()
        lifeTimer?.invalidate()
        environmentTimer?.invalidate()
        laserReactionResumeTimer?.invalidate()
        isTrackingLaser = false
        if settings.lifeSimulationEnabled {
            settings.petLife.advance(sleeping: currentIdleActivity?.isSleep == true)
        }
        settingsStore.save(settings)
        desktopToyController.clear()
        stopWalk()
        stopIdleBehaviors()
        usageSessionTracker.stop()
        removeUsageSessionObservers()
    }

    private func clearInterruptedOutingIfNeeded() {
        guard case .outing = stateMachine.state else {
            return
        }
        settings.activeOutingEndDate = nil
        settings.activeOutingDuration = nil
        settingsStore.save(settings)
        pendingOutingDuration = nil
        pendingOutingReturnReward = nil
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        dockMenuController.applicationDockMenu(sender)
    }

#if DEBUG
    private func showDebugCursorLookPreviewIfRequested() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--preview-cursor-look") else {
            return false
        }
        let point = startPositionAnchor()
        stateMachine.updateVisiblePosition(point)
        showRestingPose()
        startCursorTracking()
        RuntimeDiagnostics.record("debug cursor look preview")
        return true
    }

    private func showDebugIdleActivityPreviewIfRequested() -> Bool {
        guard let name = debugIdleActivityPreviewName(), let activity = IdleActivity.preview(named: name) else {
            return false
        }
        let point = startPositionAnchor()
        stateMachine.updateVisiblePosition(point)
        showRestingPose()
        playIdleActivity(activity)
        RuntimeDiagnostics.record("debug idle activity preview=\(name)")
        return true
    }

    private func debugIdleActivityPreviewName() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        let flag = "--preview-idle-activity"
        for (index, argument) in arguments.enumerated() {
            if argument == flag, arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            if argument.hasPrefix("\(flag)=") {
                let value = String(argument.dropFirst(flag.count + 1))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func showDebugOutingGiftPreviewIfRequested() -> Bool {
        guard let collectableID = debugOutingGiftPreviewID() else {
            return false
        }
        guard let collectable = outingCatalog.collectables.first(where: { $0.id == collectableID }) else {
            DockCatLog.app.warning("Debug outing gift preview collectable not found: \(collectableID)")
            return false
        }
        let pose = renderer.randomPose(for: .dialogue)
        let point = startPositionAnchor()
        stateMachine.updateVisiblePosition(point)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        catWindow.show(at: point)
        catWindow.showImageBubble(
            message: strings.outingReturnCollectable(salutation: settings.userSalutation),
            image: collectableImage(collectable),
            imageTitle: strings.collectableName(collectable),
            primaryTitle: strings.receiveGift,
            onPrimary: { [weak self] in
                self?.catWindow.hideBubble()
            }
        )
        RuntimeDiagnostics.record("debug outing gift preview collectableID=\(collectableID)")
        return true
    }

    private func debugOutingGiftPreviewID() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        let flag = "--preview-outing-gift"
        for (index, argument) in arguments.enumerated() {
            if argument == flag, arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            if argument.hasPrefix("\(flag)=") {
                let value = String(argument.dropFirst(flag.count + 1))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
#endif

    private func configureStateMachine() {
        stateMachine = CatStateMachine(
            initialPosition: startPositionAnchor(),
            entranceProvider: { [weak self] in
                guard let self else { return .zero }
                return self.startPositionAnchor()
            },
            walkingDurationRange: durationRange(
                minimum: settings.walkDurationMinimum,
                maximum: settings.walkDurationMaximum,
                fallback: AppSettings.defaults.walkDurationMinimum ... AppSettings.defaults.walkDurationMaximum
            ),
            restingDurationRange: durationRange(
                minimum: settings.restDurationMinimum,
                maximum: settings.restDurationMaximum,
                fallback: AppSettings.defaults.restDurationMinimum ... AppSettings.defaults.restDurationMaximum
            ),
            randomLongDurationState: { [weak self] in
                guard let self else { return .resting }
                if self.availableBehaviorModes.contains(.walking) {
                    return Bool.random() ? .walking : .resting
                }
                return .resting
            }
        )
        stateMachine.onTransition = { [weak self] _, newState in
            self?.stateScheduler.cancel()
            self?.stopWalk()
            self?.stopIdleBehaviors()
            self?.stateEndDate = nil
            self?.applyState(newState)
        }
        stateMachine.onDurationScheduled = { [weak self] state, duration in
            self?.stateEndDate = Date().addingTimeInterval(duration)
            self?.stateScheduler.schedule(after: duration) { [weak self] in
                guard let self else { return }
                self.stateMachine.finishScheduledState(state)
            }
        }
    }

    private func configureInteraction() {
        interactionController = CatInteractionController(catView: catWindow.catView)
        interactionController.onClick = { [weak self] _ in
            self?.petCat()
        }
        interactionController.onContextMenu = { [weak self] event in
            guard let self else { return }
            self.catMenuController.show(
                snapshot: self.statusSnapshot(),
                language: self.settings.language,
                currentSettings: self.settings,
                species: self.assetPack.manifest.profile.species,
                availableBehaviorModes: self.availableBehaviorModes,
                toys: self.assetPack.manifest.toys,
                at: event,
                in: self.catWindow.catView
            )
        }
        interactionController.onBeginDrag = { [weak self] in
            self?.stateMachine.beginDrag()
        }
        interactionController.onDrag = { [weak self] point in
            guard let self else { return }
            if case .outing(.leaving) = self.stateMachine.state {
                let outingPoint = self.outingWalkOutDragPoint(point)
                self.stateMachine.updateOutingWalkPosition(outingPoint)
                self.catWindow.setAnchor(outingPoint)
                self.catWindow.setMirrored(false)
                return
            }
            if case .outing(.returning) = self.stateMachine.state {
                return
            }
            let clamped = self.clampedCatPoint(point)
            self.stateMachine.updateVisiblePosition(clamped)
            self.catWindow.setAnchor(clamped)
        }
        interactionController.onEndDrag = { [weak self] point in
            guard let self else { return }
            if case .outing(.leaving) = self.stateMachine.state {
                let outingPoint = self.outingWalkOutDragPoint(point)
                self.stateMachine.updateOutingWalkPosition(outingPoint)
                self.catWindow.setAnchor(outingPoint)
                self.catWindow.setMirrored(false)
                return
            }
            if case .outing(.returning) = self.stateMachine.state {
                return
            }
            let clamped = self.clampedCatPoint(point)
            if case .dragged = self.stateMachine.state {
                self.stateMachine.endDrag(at: clamped, returningTo: self.configuredLongDurationState)
            } else {
                self.stateMachine.updateVisiblePosition(clamped)
                self.catWindow.setAnchor(clamped)
            }
        }
    }

    private func configureMenus() {
        catMenuController.onPet = { [weak self] in self?.petCat() }
        catMenuController.onBehaviorMode = { [weak self] mode in self?.selectBehaviorMode(mode) }
        catMenuController.onToy = { [weak self] kind in self?.placeToy(kind) }
        catMenuController.onClearToys = { [weak self] in self?.desktopToyController.clear() }
        catMenuController.onTogglePreference = { [weak self] preference in self?.togglePreference(preference) }
        catMenuController.onCheckUpdates = { [weak self] in self?.openReleasesPage() }
        catMenuController.onOuting = { [weak self] in self?.stateMachine.beginOutingPrompt() }
        catMenuController.onSettings = { [weak self] in self?.showSettings() }
        catMenuController.onSleep = { NSApplication.shared.terminate(nil) }

        dockMenuController.stateProvider = { [weak self] in self?.stateMachine.state ?? .resting }
        dockMenuController.statusProvider = { [weak self] in self?.statusSnapshot() }
        dockMenuController.settingsProvider = { [weak self] in self?.settings ?? .defaults }
        dockMenuController.speciesProvider = { [weak self] in self?.assetPack?.manifest.profile.species ?? .cat }
        dockMenuController.behaviorModesProvider = { [weak self] in self?.availableBehaviorModes ?? [.random, .resting] }
        dockMenuController.toysProvider = { [weak self] in self?.assetPack?.manifest.toys ?? [] }
        dockMenuController.onPet = { [weak self] in self?.petCat() }
        dockMenuController.onBehaviorMode = { [weak self] mode in self?.selectBehaviorMode(mode) }
        dockMenuController.onToy = { [weak self] kind in self?.placeToy(kind) }
        dockMenuController.onClearToys = { [weak self] in self?.desktopToyController.clear() }
        dockMenuController.onTogglePreference = { [weak self] preference in self?.togglePreference(preference) }
        dockMenuController.onCheckUpdates = { [weak self] in self?.openReleasesPage() }
        dockMenuController.onOuting = { [weak self] in self?.stateMachine.beginOutingPrompt() }
        dockMenuController.onRecall = { [weak self] in self?.showRecallConfirmation() }
        dockMenuController.onSettings = { [weak self] in self?.showSettings() }
        dockMenuController.onSleep = { NSApplication.shared.terminate(nil) }

        settingsWindowController.onSave = { [weak self] updated in
            guard let self else { return }
            let previousAssetPackID = self.settings.selectedAssetPackID
            let previousCatActivityScope = self.settings.catActivityScope
            let previousLanguage = self.settings.language
            let previousLaunchAtLogin = self.settings.launchAtLogin
            self.settings = updated
            self.reminderScheduler.updateSettings(updated)
            if updated.language != previousLanguage {
                self.configureApplicationMenu()
            }
            if updated.selectedAssetPackID != previousAssetPackID {
                self.reloadSelectedAssetPack()
                self.applyState(self.stateMachine.state)
            }
            self.catWindow.setImageScale(percent: updated.catScalePercent)
            self.activitySpace = self.currentActivitySpace()
            let shouldResetPosition = previousCatActivityScope == .desktop && updated.catActivityScope == .dockEdge
            let point = shouldResetPosition ? self.startPositionAnchor() : self.clampedCatPoint(self.stateMachine.position)
            self.updateCurrentPositionPreservingState(point)
            self.updateStateMachineParameters()
            if updated.launchAtLogin != previousLaunchAtLogin {
                self.updateLaunchAtLogin(enabled: updated.launchAtLogin)
            }
            self.updateEnvironmentVisibility()
            self.saveUserDataBackup()
        }
    }

    private func saveUserDataBackup() {
        userDataBackupStore.save(
            settings: settings,
            usageStatistics: usageSessionTracker.snapshot,
            collectableInventory: collectableInventory
        )
    }

    private func configureSettingsAssetPackActions() {
        settingsWindowController.assetPackIDsProvider = { [weak self] in
            guard let self else { return [] }
            return self.assetLoader.customPackIDs()
        }
        settingsWindowController.onOpenAssetPacksFolder = { [weak self] in
            guard let self else { return }
            self.assetLoader.prepareCustomPacksDirectory()
            NSWorkspace.shared.open(self.assetLoader.customPacksRoot())
        }
        settingsWindowController.onRestoreData = { [weak self] in
            self?.beginUserDataRestore()
        }
        settingsWindowController.onRedeemGiftCode = { [weak self] language in
            self?.beginGiftCodeRedemption(language: language)
        }
        settingsWindowController.onLoadAssetPack = { [weak self] selectedID in
            guard let self else {
                return AssetPackPreviewResult(
                    report: AssetPackValidationReport(
                        requestedID: selectedID,
                        pack: nil,
                        errorDescription: "喵心心尚未准备好资源包加载器。",
                        poseStatuses: [],
                        walkFrameCount: 0,
                        hasValidSleepIcon: false,
                        hasValidEmptyIcon: false
                    ),
                    dialogueImage: nil
                )
            }
            let report = self.assetLoader.validationReport(for: selectedID)
            let previewImage = report.pack.map {
                PoseRenderer(pack: $0, fallbackPack: self.defaultAssetPack).randomPose(for: .dialogue).image
            } ?? self.renderer.randomPose(for: .dialogue).image
            return AssetPackPreviewResult(report: report, dialogueImage: previewImage)
        }
    }

    private func beginUserDataRestore() {
        guard confirmUserDataRestore() else { return }

        let panel = NSOpenPanel()
        panel.title = strings.restoreDataChooseFileTitle
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = userDataBackupStore.backupDirectoryURL

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            let result = try userDataBackupStore.restoreData(from: url, outingCatalog: outingCatalog)
            applyUserDataRestore(result)
            showUserDataRestoreSuccess(skippedCollectableNames: result.skippedCollectableNames)
        } catch {
            DockCatLog.app.error("Failed to restore user data backup: \(error.localizedDescription)")
            showAlert(title: strings.restoreDataFailureTitle, message: strings.restoreDataInvalidFileMessage)
        }
    }

    private func confirmUserDataRestore() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strings.restoreDataConfirmTitle
        alert.informativeText = strings.restoreDataConfirmMessage
        alert.addButton(withTitle: strings.settingsRestoreData)
        alert.addButton(withTitle: strings.alertCancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func applyUserDataRestore(_ result: UserDataRestoreResult) {
        collectableInventory = result.collectableInventory
        collectableInventoryStore.save(result.collectableInventory)
        usageStatisticsStore.save(result.usageStatistics)
        usageSessionTracker.replaceStatistics(result.usageStatistics)
        settingsWindowController.update(usageStatistics: usageSessionTracker.snapshot)
        settingsWindowController.update(collectableInventory: collectableInventory)
        saveUserDataBackup()
    }

    private func showUserDataRestoreSuccess(skippedCollectableNames: [String]) {
        var message = strings.restoreDataSuccessMessage
        if !skippedCollectableNames.isEmpty {
            message += "\n\n\(strings.restoreDataSkippedCollectablesHeader)\n"
            message += skippedCollectableNames.map { "• \($0)" }.joined(separator: "\n")
        }
        showAlert(title: strings.restoreDataSuccessTitle, message: message)
    }

    private func beginGiftCodeRedemption(language: AppLanguage) {
        showGiftCodeInputWindow(language: language)
    }

    private func redeemGiftCode(_ code: String, language: AppLanguage) {
        let codeStrings = AppStrings(language: language)
        guard let collectableID = giftCodeRedeemer.collectableID(for: code, in: outingCatalog),
              let collectable = outingCatalog.collectables.first(where: { $0.id == collectableID })
        else {
            showAlert(title: codeStrings.giftCodeInvalidTitle, message: "", okTitle: codeStrings.assetPackAlertOK)
            return
        }

        _ = collectableInventory.recordCollectable(collectable.id)
        collectableInventoryStore.save(collectableInventory)
        settingsWindowController.update(collectableInventory: collectableInventory)
        saveUserDataBackup()
        showGiftCodeSuccess(collectable, language: language)
    }

    private func showGiftCodeInputWindow(language: AppLanguage) {
        giftCodeInputWindow?.close()
        giftCodeInputWindow = nil
        giftCodeCallbackTargets.removeAll()
        let codeStrings = AppStrings(language: language)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 292, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = codeStrings.settingsRedeemGiftCode
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces]
        window.center()

        let contentView = NSView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: codeStrings.giftCodeInputTitle)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.alignment = .center

        let subtitleLabel = NSTextField(labelWithString: codeStrings.giftCodeInputSubtitle)
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center

        let codeField = NSTextField(string: "")
        codeField.isEditable = true
        codeField.isSelectable = true
        codeField.usesSingleLineMode = true

        let cancelButton = NSButton(title: codeStrings.alertCancel, target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let submitButton = NSButton(title: codeStrings.giftCodeSubmit, target: nil, action: nil)
        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [cancelButton, submitButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 10

        for view in [titleLabel, subtitleLabel, codeField, buttonRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            codeField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 10),
            codeField.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            codeField.widthAnchor.constraint(equalToConstant: 176),
            buttonRow.topAnchor.constraint(equalTo: codeField.bottomAnchor, constant: 14),
            buttonRow.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            buttonRow.widthAnchor.constraint(equalToConstant: 184),
            buttonRow.heightAnchor.constraint(equalToConstant: 28)
        ])

        let cancelTarget = CallbackTarget {
            window.close()
            self.giftCodeInputWindow = nil
            self.giftCodeCallbackTargets.removeAll()
        }
        let submitTarget = CallbackTarget {
            let code = codeField.stringValue
            window.close()
            self.giftCodeInputWindow = nil
            self.giftCodeCallbackTargets.removeAll()
            self.redeemGiftCode(code, language: language)
        }
        giftCodeCallbackTargets = [cancelTarget, submitTarget]
        cancelButton.target = cancelTarget
        cancelButton.action = #selector(CallbackTarget.invoke)
        submitButton.target = submitTarget
        submitButton.action = #selector(CallbackTarget.invoke)

        giftCodeInputWindow = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(codeField)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }

    private func showGiftCodeSuccess(_ collectable: OutingCollectable, language: AppLanguage) {
        giftCodeSuccessWindow?.close()
        let codeStrings = AppStrings(language: language)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 204),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = codeStrings.settingsRedeemGiftCode
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces]
        window.center()

        let contentView = NSView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: codeStrings.giftCodeSuccessTitle)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.alignment = .center

        let imageView = NSImageView()
        imageView.image = collectableImage(collectable)
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let nameLabel = NSTextField(labelWithString: codeStrings.collectableName(collectable))
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1

        let okButton = NSButton(title: codeStrings.giftCodeDone, target: nil, action: nil)
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"

        for view in [titleLabel, imageView, nameLabel, okButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),
            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            okButton.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 16),
            okButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            okButton.widthAnchor.constraint(equalToConstant: 96)
        ])

        let okTarget = CallbackTarget {
            window.close()
            self.giftCodeSuccessWindow = nil
            self.giftCodeCallbackTargets.removeAll()
        }
        giftCodeCallbackTargets.append(okTarget)
        okButton.target = okTarget
        okButton.action = #selector(CallbackTarget.invoke)

        giftCodeSuccessWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }

    private func showAlert(title: String, message: String, okTitle: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        if !message.isEmpty {
            alert.informativeText = message
        }
        alert.addButton(withTitle: okTitle ?? strings.assetPackAlertOK)
        alert.runModal()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "喵心心")
        appMenu.addItem(menuItem(strings.menuPet, #selector(petFromMenu)))
        appMenu.addItem(menuItem(strings.menuGoOut, #selector(startOutingFromMenu)))
        appMenu.addItem(menuItem(strings.menuSettings, #selector(openSettingsFromMenu), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(menuItem(strings.menuSleep, #selector(quitFromMenu), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func menuItem(_ title: String, _ action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func configureUsageSessionTracker() {
        usageSessionTracker = UsageSessionTracker(
            statistics: usageStatisticsStore.load(),
            onChange: { [weak self] statistics in
                self?.usageStatisticsStore.save(statistics)
            }
        )
        usageSessionTracker.start()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self, selector: #selector(workspaceWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(workspaceDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(frontmostApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    private func removeUsageSessionObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.screensDidWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc private func workspaceWillSleep() {
        if settings.lifeSimulationEnabled {
            settings.petLife.advance(sleeping: currentIdleActivity?.isSleep == true)
        }
        settingsStore.save(settings)
        usageSessionTracker.screenDidSleep()
    }

    @objc private func workspaceDidWake() {
        if settings.lifeSimulationEnabled {
            settings.petLife.advance(sleeping: true)
            settings.petLife.apply(.wake)
        }
        settingsStore.save(settings)
        usageSessionTracker.screenDidWake()
        resolveActiveOutingAfterWake()
    }

    @objc private func screensDidSleep() {
        usageSessionTracker.screenDidSleep()
    }

    @objc private func screensDidWake() {
        usageSessionTracker.screenDidWake()
        resolveActiveOutingAfterWake()
    }

    @objc private func frontmostApplicationChanged() {
        updateEnvironmentVisibility()
    }

    private func showSettings() {
        RuntimeDiagnostics.record("showSettings requested")
        settingsWindowController.update(settings: settings)
        settingsWindowController.update(usageStatistics: usageSessionTracker.snapshot)
        settingsWindowController.update(collectableInventory: collectableInventory)
        settingsWindowController.update(dialogueImage: renderer.randomPose(for: .dialogue).image)
        DispatchQueue.main.async { [weak self] in
            RuntimeDiagnostics.record("showSettings presenting")
            self?.settingsWindowController.show()
        }
    }

    private func statusSnapshot() -> CatStatusSnapshot {
        CatStatusSnapshot(
            state: stateMachine.state,
            stateEndDate: stateEndDate,
            outingEndDate: settings.activeOutingEndDate,
            life: settings.petLife
        )
    }

    private func configureDockObserver() {
        dockObserver.onChange = { [weak self] in
            guard let self else { return }
            self.activitySpace = self.currentActivitySpace()
            let clamped = self.clampedCatPoint(self.stateMachine.position)
            let walkRange = self.activitySpace.walkRangeForContent(
                width: self.catWindow.catFrameSize.width,
                scope: self.settings.catActivityScope
            )
            RuntimeDiagnostics.record(
                "workspace changed state=\(self.stateMachine.state.description) position=\(self.stateMachine.position) clamped=\(clamped) walkRange=\(walkRange) speed=\(self.settings.walkBaseSpeed)"
            )
            self.stateMachine.updateVisiblePosition(clamped)
            self.catWindow.setAnchor(clamped)
            self.catWindow.refreshVisibilityAfterWorkspaceChange()
        }
        dockObserver.start()
    }

    private func currentActivitySpace() -> ActivitySpace {
        DockGeometry.currentActivitySpace(
            activityDisplayID: settings.activityDisplayID,
            startPositionPercent: settings.startPositionPercent
        )
    }

    private func applyState(_ state: CatState) {
        stopWalk()
        stopIdleBehaviors()
        switch state {
        case .transitioning:
            catWindow.hideBubble()
            iconController.showEmptyIcon()
            let pose = renderer.randomPose(for: .transition, fallback: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            let point: CGPoint
            if shouldUseStartPositionForNextTransition {
                point = startPositionAnchor()
                shouldUseStartPositionForNextTransition = false
            } else {
                point = clampedCatPoint(stateMachine.position)
            }
            stateMachine.updateVisiblePosition(point)
            catWindow.show(at: point)
        case .walking:
            catWindow.hideBubble()
            iconController.showEmptyIcon()
            startWalk()
        case .resting:
            catWindow.hideBubble()
            iconController.showEmptyIcon()
            let pose = renderer.randomPose(for: .resting, fallback: .dialogue)
            RuntimeDiagnostics.record("resting imageLoaded=\(pose.image != nil) mirrored=\(pose.mirrored) position=\(stateMachine.position)")
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            let point = clampedCatPoint(stateMachine.position)
            stateMachine.updateLongDurationPosition(point)
            catWindow.show(at: point)
            beginRestingBehaviors()
        case .dragged:
            catWindow.hideBubble()
            let pose = renderer.randomPose(for: .held, fallback: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
        case .dialogue(let type):
            let pose = renderer.randomPose(for: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            let point = clampedCatPoint(stateMachine.position)
            stateMachine.updateVisiblePosition(point)
            catWindow.show(at: point)
            showReminder(type)
        case .outing(let phase):
            iconController.showEmptyIcon()
            applyOutingPhase(phase)
        }
    }

    private func showReminder(_ type: ReminderType) {
        catWindow.showBubble(
            message: type.message(settings: settings),
            primaryTitle: strings.done,
            secondaryTitle: strings.snoozeFiveMinutes,
            onPrimary: { [weak self] in
                guard let self else { return }
                self.reminderScheduler.complete(type)
                self.usageSessionTracker.recordCompletedReminder(type)
                self.saveUserDataBackup()
                self.catWindow.hideBubble()
                self.stateMachine.finishReminder(returningTo: self.configuredLongDurationState)
            },
            onSecondary: { [weak self] in
                guard let self else { return }
                self.reminderScheduler.snooze(type)
                self.catWindow.hideBubble()
                self.stateMachine.finishReminder(returningTo: self.configuredLongDurationState)
            }
        )
    }

    private func applyOutingPhase(_ phase: OutingPhase) {
        switch phase {
        case .asking:
            let pose = renderer.randomPose(for: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            catWindow.show(at: clampedCatPoint(stateMachine.position))
            askOutingDuration()
        case .confirmingDeparture:
            catWindow.show(at: clampedCatPoint(stateMachine.position))
            showOutingDepartureResponse()
        case .leaving:
            startOutingWalkOut()
        case .away:
            catWindow.hide()
        case .returning:
            startOutingWalkIn()
        case .returned:
            let pose = renderer.randomPose(for: .dialogue)
            catWindow.setImage(pose.image, mirrored: pose.mirrored)
            showOutingReturnBubble()
        }
    }

    private func askOutingDuration() {
        catWindow.showInputBubble(
            message: strings.askOutingDuration(catName: settings.catName),
            value: "\(Int(settings.defaultOutingDuration / 60))",
            primaryTitle: strings.outingPrimary,
            secondaryTitle: strings.cancel,
            minuteUnit: strings.minuteUnit,
            onPrimary: { [weak self] value in
                self?.confirmOuting(minutesText: value)
            },
            onSecondary: { [weak self] in
                guard let self else { return }
                self.catWindow.hideBubble()
                self.applyConfiguredBehaviorMode()
            }
        )
    }

    private func confirmOuting(minutesText: String) {
        let minutes = max(1, Int(minutesText) ?? Int(settings.defaultOutingDuration / 60))
        pendingOutingDuration = TimeInterval(minutes * 60)
        stateMachine.confirmOuting()
    }

    private func showOutingDepartureResponse() {
        catWindow.showBubble(
            message: strings.outingDeparture(settings: settings),
            primaryTitle: strings.ok,
            onPrimary: { [weak self] in
                self?.startConfirmedOuting()
            }
        )
    }

    private func startConfirmedOuting() {
        guard let duration = pendingOutingDuration else { return }
        catWindow.hideBubble()
        settings.activeOutingEndDate = Date().addingTimeInterval(duration)
        settings.activeOutingDuration = duration
        settingsStore.save(settings)
        suspendRemindersForOuting()
        scheduleOutingReturn(after: duration, plannedDuration: duration)
        pendingOutingDuration = nil
        stateMachine.departOuting()
    }

    private func returnFromOuting(drawReward: Bool = false, forceEvent: Bool = false, plannedDuration: TimeInterval? = nil) {
        outingTimer?.invalidate()
        if forceEvent {
            prepareOutingReturnEvent()
        } else if drawReward {
            prepareOutingReturnReward(plannedDuration: plannedDuration ?? settings.activeOutingDuration ?? settings.defaultOutingDuration)
        } else {
            pendingOutingReturnReward = nil
        }
        settings.activeOutingEndDate = nil
        settings.activeOutingDuration = nil
        settingsStore.save(settings)
        stateMachine.returnFromOuting()
    }

    private func scheduleOutingReturn(after interval: TimeInterval, plannedDuration: TimeInterval) {
        outingTimer?.invalidate()
        outingTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, interval), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.returnFromOuting(drawReward: true, plannedDuration: plannedDuration)
            }
        }
    }

    private func prepareOutingReturnReward(plannedDuration: TimeInterval) {
        let generator = OutingRewardGenerator(catalog: outingCatalog)
        guard let reward = generator.reward(forOutingDuration: plannedDuration) else {
            pendingOutingReturnReward = nil
            return
        }

        recordOutingReward(reward)
    }

    private func prepareOutingReturnEvent() {
        let generator = OutingRewardGenerator(catalog: outingCatalog)
        guard let reward = generator.eventReward() else {
            pendingOutingReturnReward = nil
            return
        }

        recordOutingReward(reward)
    }

    private func recordOutingReward(_ reward: OutingReward) {
        pendingOutingReturnReward = reward
        switch reward {
        case .event:
            if collectableInventory.recentNewCollectableID != nil {
                collectableInventory.clearRecentNewMarker()
                collectableInventoryStore.save(collectableInventory)
            }
            usageSessionTracker.recordOutingEvent()
        case .collectable(let collectable):
            _ = collectableInventory.recordCollectable(collectable.id)
            collectableInventoryStore.save(collectableInventory)
            usageSessionTracker.recordOutingCollectable()
        }
    }

    private func showOutingReturnBubble() {
        switch pendingOutingReturnReward {
        case .event(let event):
            catWindow.showBubble(
                message: strings.outingReturnEvent(salutation: settings.userSalutation, event: event),
                primaryTitle: strings.welcomeBack,
                onPrimary: { [weak self] in
                    self?.finishOutingReturn()
                }
            )
        case .collectable(let collectable):
            catWindow.showImageBubble(
                message: strings.outingReturnCollectable(salutation: settings.userSalutation),
                image: collectableImage(collectable),
                imageTitle: strings.collectableName(collectable),
                primaryTitle: strings.receiveGift,
                onPrimary: { [weak self] in
                    self?.finishOutingReturn()
                }
            )
        case nil:
            catWindow.showBubble(
                message: strings.outingReturnPlain(salutation: settings.userSalutation),
                primaryTitle: strings.welcomeBack,
                onPrimary: { [weak self] in
                    self?.finishOutingReturn()
                }
            )
        }
    }

    private func finishOutingReturn() {
        pendingOutingReturnReward = nil
        catWindow.hideBubble()
        stateMachine.welcomeBack(returningTo: configuredLongDurationState)
        restartRemindersAfterOuting()
        saveUserDataBackup()
    }

    private func collectableImage(_ collectable: OutingCollectable) -> NSImage? {
        NSImage(contentsOf: outingCatalog.imageURL(for: collectable))
    }

    private func startReminderPolling() {
        guard reminderTimer == nil else { return }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let reminder = self.reminderScheduler.dueReminder(whenCatInLongDurationState: self.stateMachine.state.isLongDuration) {
                    _ = self.stateMachine.requestReminder(reminder)
                }
            }
        }
    }

    private func stopReminderPolling() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }

    private func suspendRemindersForOuting() {
        reminderScheduler.clear()
        stopReminderPolling()
    }

    private func restartRemindersAfterOuting() {
        reminderScheduler.restartTimersFromNow()
        if reminderScheduler.settings.remindersEnabled {
            startReminderPolling()
        }
    }

    private func scheduleStartupStretch() {
        startupTimer?.invalidate()
        startupTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.shouldUseStartPositionForNextTransition = true
                self.stateMachine.start()
            }
        }
    }

    private func restoreActiveOutingIfNeeded() -> Bool {
        guard settings.activeOutingEndDate != nil else {
            return false
        }

        suspendRemindersForOuting()
        stateMachine.restoreOutingAway()

        switch outingWakeResolver.resolution(
            endDate: settings.activeOutingEndDate,
            plannedDuration: settings.activeOutingDuration,
            defaultDuration: settings.defaultOutingDuration
        ) {
        case .noActiveOuting:
            return false
        case .reschedule(let remaining, let plannedDuration):
            scheduleOutingReturn(after: remaining, plannedDuration: plannedDuration)
        case .returnNow(let plannedDuration):
            returnFromOuting(drawReward: true, plannedDuration: plannedDuration)
        }
        return true
    }

    private func resolveActiveOutingAfterWake() {
        switch stateMachine.state {
        case .outing(.leaving), .outing(.away):
            break
        default:
            return
        }

        switch outingWakeResolver.resolution(
            endDate: settings.activeOutingEndDate,
            plannedDuration: settings.activeOutingDuration,
            defaultDuration: settings.defaultOutingDuration
        ) {
        case .noActiveOuting:
            return
        case .reschedule(let remaining, let plannedDuration):
            scheduleOutingReturn(after: remaining, plannedDuration: plannedDuration)
        case .returnNow(let plannedDuration):
            returnFromOuting(drawReward: true, plannedDuration: plannedDuration)
        }
    }

    private func startWalk() {
        let animation = renderer.animationFrames(\.walk)
        let sourceSize = stableWalkSourceSize()
        walkDirection = Bool.random() ? 1 : -1
        catWindow.setImage(animation.frames.first ?? renderer.firstImage(for: .dialogue), mirrored: walkDirection < 0, sourceSize: sourceSize)
        let start = clampedCatPoint(stateMachine.position)
        stateMachine.updateLongDurationPosition(start)
        catWindow.show(at: start)
        walkAnimator.start(animation: animation) { [weak self, animation] frameIndex in
            Task { @MainActor in
                guard let self else { return }
                self.catWindow.setImage(animation.frames[frameIndex], mirrored: self.walkDirection < 0, sourceSize: sourceSize)
            }
        }
        walkMovementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceWalk()
            }
        }
    }

    private func advanceWalk() {
        guard case .walking = stateMachine.state else { return }
        let speed = effectiveWalkSpeed
        let walkRange = activitySpace.walkRangeForContent(width: catWindow.catFrameSize.width, scope: settings.catActivityScope)
        var nextX = stateMachine.position.x + walkDirection * speed / 30.0
        if nextX <= walkRange.lowerBound {
            nextX = walkRange.lowerBound
            walkDirection = 1
        } else if nextX >= walkRange.upperBound {
            nextX = walkRange.upperBound
            walkDirection = -1
        }
        let point = clampedCatPoint(CGPoint(x: nextX, y: stateMachine.position.y))
        stateMachine.updateLongDurationPosition(point)
        catWindow.setAnchor(point)
        catWindow.setMirrored(walkDirection < 0)
    }

    private func startOutingWalkOut() {
        let animation = renderer.animationFrames(\.walk)
        let sourceSize = stableWalkSourceSize()
        catWindow.setImage(animation.frames.first ?? renderer.firstImage(for: .dialogue), mirrored: false, sourceSize: sourceSize)
        let start = clampedCatPoint(stateMachine.position)
        stateMachine.updateOutingWalkPosition(start)
        walkDirection = 1
        catWindow.show(at: start)
        walkAnimator.start(animation: animation) { [weak self, animation] frameIndex in
            Task { @MainActor in
                guard let self else { return }
                self.catWindow.setImage(animation.frames[frameIndex], mirrored: false, sourceSize: sourceSize)
            }
        }
        walkMovementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceOutingWalkOut()
            }
        }
    }

    private func advanceOutingWalkOut() {
        guard case .outing(.leaving) = stateMachine.state else { return }
        let speed = outingWalkSpeed
        let targetX = activitySpace.screenFrame.maxX + catWindow.catFrameSize.width
        var nextX = stateMachine.position.x + speed / 30.0
        if nextX >= targetX {
            nextX = targetX
            stopWalk()
            catWindow.hide()
            stateMachine.updateOutingWalkPosition(CGPoint(x: nextX, y: stateMachine.position.y))
            stateMachine.markAway()
            return
        }
        let point = CGPoint(x: nextX, y: stateMachine.position.y)
        stateMachine.updateOutingWalkPosition(point)
        catWindow.setAnchor(point)
        catWindow.setMirrored(false)
    }

    private func startOutingWalkIn() {
        let animation = renderer.animationFrames(\.walk)
        let sourceSize = stableWalkSourceSize()
        catWindow.setImage(animation.frames.first ?? renderer.firstImage(for: .dialogue), mirrored: true, sourceSize: sourceSize)
        let start = CGPoint(
            x: activitySpace.screenFrame.maxX + catWindow.catFrameSize.width,
            y: activitySpace.baselineY
        )
        stateMachine.updateOutingWalkPosition(start)
        walkDirection = -1
        catWindow.show(at: start)
        walkAnimator.start(animation: animation) { [weak self, animation] frameIndex in
            Task { @MainActor in
                guard let self else { return }
                self.catWindow.setImage(animation.frames[frameIndex], mirrored: true, sourceSize: sourceSize)
            }
        }
        walkMovementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceOutingWalkIn()
            }
        }
    }

    private func advanceOutingWalkIn() {
        guard case .outing(.returning) = stateMachine.state else { return }
        let speed = outingWalkSpeed
        let target = outingReturnTarget()
        var nextX = stateMachine.position.x - speed / 30.0
        if nextX <= target.x {
            nextX = target.x
            let point = CGPoint(x: nextX, y: activitySpace.baselineY)
            stateMachine.updateOutingWalkPosition(point)
            catWindow.setAnchor(point)
            catWindow.setMirrored(true)
            stopWalk()
            stateMachine.finishReturnWalk()
            return
        }
        let point = CGPoint(x: nextX, y: activitySpace.baselineY)
        stateMachine.updateOutingWalkPosition(point)
        catWindow.setAnchor(point)
        catWindow.setMirrored(true)
    }

    private func stopWalk() {
        walkAnimator.stop()
        walkMovementTimer?.invalidate()
        walkMovementTimer = nil
    }

    private func beginRestingBehaviors() {
        guard case .resting = stateMachine.state else { return }
        switch settings.petBehaviorMode {
        case .random:
            startCursorTracking()
            scheduleNextIdleActivity()
        case .resting:
            startCursorTracking()
        case .walking:
            return
        case .playToy:
            playIdleActivity(.playToy, continuous: true)
        case .grooming:
            playIdleActivity(.grooming, continuous: true)
        case .bellyRoll:
            playIdleActivity(.bellyRoll, continuous: true)
        case .sleepCurled:
            playIdleActivity(.sleepCurled, continuous: true)
        case .sleepSide:
            playIdleActivity(.sleepSide, continuous: true)
        case .sleepLoaf:
            playIdleActivity(.sleepLoaf, continuous: true)
        case .eating:
            playIdleActivity(.eating, continuous: true)
        case .drinking:
            playIdleActivity(.drinking, continuous: true)
        case .signatureMove:
            playIdleActivity(.signatureMove, continuous: true)
        }
    }

    private func behaviorDescriptor(for activity: IdleActivity) -> PetBehaviorDescriptor? {
        if let mode = activity.mode {
            return behaviorCatalog.descriptor(for: mode)
        }
        let override = assetPack.manifest.animations.behaviors["pet_response"]
        return PetBehaviorDescriptor(
            mode: .resting,
            assetName: "pet_response",
            fps: override?.fps ?? 2.2,
            playbackLoops: max(1, override?.playbackLoops ?? 1),
            isSleep: false,
            autonomousWeight: 0
        )
    }

    private func randomAutonomousActivity() -> IdleActivity? {
        let candidates = IdleActivity.autonomousChoices.compactMap { activity -> (IdleActivity, Double)? in
            guard let descriptor = behaviorDescriptor(for: activity),
                  descriptor.autonomousWeight > 0,
                  renderer.hasAnimation(named: descriptor.assetName, includeFallback: allowsDefaultAnimationFallback)
            else {
                return nil
            }
            let hour = settings.naturalScheduleEnabled ? Calendar.current.component(.hour, from: Date()) : 12
            let life = settings.lifeSimulationEnabled ? settings.petLife : PetLifeState()
            let weight = behaviorCatalog.autonomousWeight(
                for: descriptor,
                life: life,
                personality: assetPack.manifest.personality,
                hour: hour
            )
            return weight > 0 ? (activity, weight) : nil
        }
        let total = candidates.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var draw = Double.random(in: 0..<total)
        for (activity, weight) in candidates {
            draw -= weight
            if draw < 0 { return activity }
        }
        return candidates.last?.0
    }

    private func stopIdleBehaviors() {
        if settings.lifeSimulationEnabled, currentIdleActivity?.isSleep == true {
            settings.petLife.advance(sleeping: true)
            settingsStore.save(settings)
        }
        idleActivityTimer?.invalidate()
        idleActivityTimer = nil
        idleActivityEndTimer?.invalidate()
        idleActivityEndTimer = nil
        cursorTrackingTimer?.invalidate()
        cursorTrackingTimer = nil
        idleActivityAnimator.stop()
        isIdleActivityPlaying = false
        idleActivityCompletion = nil
        currentLookFrameIndex = nil
        currentIdleActivity = nil
    }

    private func scheduleNextIdleActivity(after delay: TimeInterval? = nil) {
        idleActivityTimer?.invalidate()
        guard case .resting = stateMachine.state else { return }
        let interval = delay ?? TimeInterval.random(in: 6 ... 16)
        idleActivityTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .resting = self.stateMachine.state else { return }
                guard let activity = self.randomAutonomousActivity() else {
                    self.scheduleNextIdleActivity(after: 12)
                    return
                }
                self.playIdleActivity(activity)
            }
        }
    }

    private func startCursorTracking() {
        cursorTrackingTimer?.invalidate()
        cursorTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCursorLook()
            }
        }
    }

    private func updateCursorLook() {
        showLook(toward: NSEvent.mouseLocation, maximumDistance: 520)
    }

    private func showLook(toward target: CGPoint, maximumDistance: CGFloat) {
        guard case .resting = stateMachine.state, !isIdleActivityPlaying else { return }

        let catFrame = catWindow.catView.frame.offsetBy(dx: catWindow.panel.frame.minX, dy: catWindow.panel.frame.minY)
        let dx = target.x - catFrame.midX
        let dy = target.y - catFrame.midY
        let distance = hypot(dx, dy)
        guard distance <= maximumDistance else {
            if currentLookFrameIndex != nil {
                currentLookFrameIndex = nil
                showRestingPose()
            }
            return
        }

        let frameIndex: Int
        if distance < 45 {
            frameIndex = 1
        } else if dy > 45, abs(dy) > abs(dx) * 0.7 {
            frameIndex = 3
        } else if dx < 0 {
            frameIndex = 0
        } else {
            frameIndex = 2
        }
        guard frameIndex != currentLookFrameIndex else { return }

        let look = renderer.animation(named: "look", fps: 8, loops: false)
        guard look.frames.indices.contains(frameIndex) else { return }
        currentLookFrameIndex = frameIndex
        RuntimeDiagnostics.record("cursorLook frame=\(frameIndex) distance=\(Int(distance))")
        catWindow.setImage(
            look.frames[frameIndex],
            mirrored: false,
            sourceSize: stableAnimationSourceSize(named: "look")
        )
    }

    private func playIdleActivity(
        _ activity: IdleActivity,
        continuous: Bool = false,
        recordLifeEvent: Bool = true,
        onFinish: (() -> Void)? = nil
    ) {
        guard case .resting = stateMachine.state else { return }
        idleActivityTimer?.invalidate()
        idleActivityTimer = nil
        idleActivityEndTimer?.invalidate()
        idleActivityEndTimer = nil
        idleActivityAnimator.stop()
        isIdleActivityPlaying = true
        currentIdleActivity = activity
        idleActivityCompletion = onFinish
        currentLookFrameIndex = nil
        guard let descriptor = behaviorDescriptor(for: activity) else {
            finishIdleActivity()
            return
        }
        RuntimeDiagnostics.record("idleActivity start=\(descriptor.assetName)")

        var effectiveFPS = descriptor.fps
        if settings.reducedMotion { effectiveFPS = min(effectiveFPS, 1.5) }
        if settings.batterySaverEnabled, DesktopEnvironmentMonitor.isOnBatterySaver {
            effectiveFPS = min(effectiveFPS, 3)
        }
        if recordLifeEvent { applyLifeEffect(for: activity) }
        let baseAnimation = renderer.animation(
            named: descriptor.assetName,
            fps: effectiveFPS,
            loops: continuous || descriptor.isSleep
        )
        guard !baseAnimation.frames.isEmpty else {
            finishIdleActivity()
            return
        }
        let sourceSize = stableAnimationSourceSize(named: descriptor.assetName)

        if continuous {
            idleActivityAnimator.start(animation: baseAnimation) { [weak self, baseAnimation] frameIndex in
                Task { @MainActor in
                    guard let self, case .resting = self.stateMachine.state else { return }
                    self.catWindow.setImage(baseAnimation.frames[frameIndex], mirrored: false, sourceSize: sourceSize)
                }
            }
            return
        }

        if descriptor.isSleep {
            idleActivityAnimator.start(animation: baseAnimation) { [weak self, baseAnimation] frameIndex in
                Task { @MainActor in
                    guard let self, case .resting = self.stateMachine.state else { return }
                    self.catWindow.setImage(baseAnimation.frames[frameIndex], mirrored: false, sourceSize: sourceSize)
                }
            }
            idleActivityEndTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 16 ... 28), repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.finishIdleActivity()
                }
            }
            return
        }

        let repeatedFrames = Array(repeating: baseAnimation.frames, count: descriptor.playbackLoops).flatMap { $0 }
        let animation = SpriteAnimation(frames: repeatedFrames, fps: effectiveFPS, loops: false)
        idleActivityAnimator.start(
            animation: animation,
            onFrame: { [weak self, animation] frameIndex in
                Task { @MainActor in
                    guard let self, case .resting = self.stateMachine.state else { return }
                    self.catWindow.setImage(animation.frames[frameIndex], mirrored: false, sourceSize: sourceSize)
                }
            },
            onFinish: { [weak self] in
                Task { @MainActor in
                    self?.finishIdleActivity()
                }
            }
        )
    }

    private func finishIdleActivity() {
        guard isIdleActivityPlaying else { return }
        let completion = idleActivityCompletion
        idleActivityCompletion = nil
        idleActivityAnimator.stop()
        idleActivityEndTimer?.invalidate()
        idleActivityEndTimer = nil
        isIdleActivityPlaying = false
        currentIdleActivity = nil
        currentLookFrameIndex = nil
        RuntimeDiagnostics.record("idleActivity finish")
        guard case .resting = stateMachine.state else { return }
        if let completion {
            completion()
            return
        }
        showRestingPose()
        if settings.petBehaviorMode == .random {
            scheduleNextIdleActivity(after: .random(in: 7 ... 18))
        }
    }

    private func showRestingPose() {
        let pose = renderer.randomPose(for: .resting, fallback: .dialogue)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        let point = clampedCatPoint(stateMachine.position)
        stateMachine.updateLongDurationPosition(point)
        catWindow.show(at: point)
    }

    private func stableAnimationSourceSize(named name: String) -> CGSize {
        let sourcePack = renderer.animationSourcePack(named: name) ?? assetPack!
        let manifestSize = CGSize(width: sourcePack.manifest.canvasWidth, height: sourcePack.manifest.canvasHeight)
        if manifestSize.width > 0, manifestSize.height > 0 {
            return manifestSize
        }
        return renderer.animation(named: name, fps: 6, loops: false).frames.reduce(CGSize.zero) { size, image in
            CGSize(width: max(size.width, image.size.width), height: max(size.height, image.size.height))
        }
    }

    private var effectiveWalkSpeed: CGFloat {
        CGFloat(settings.walkBaseSpeed) * 0.67
    }

    private var outingWalkSpeed: CGFloat {
        effectiveWalkSpeed * 1.5
    }

    private func stableWalkSourceSize() -> CGSize {
        let sourcePack = renderer.walkAnimationSourcePack() ?? assetPack!
        let manifestSize = CGSize(width: sourcePack.manifest.canvasWidth, height: sourcePack.manifest.canvasHeight)
        if manifestSize.width > 0, manifestSize.height > 0 {
            return manifestSize
        }
        return renderer.animationFrames(\.walk).frames.reduce(CGSize.zero) { size, image in
            CGSize(width: max(size.width, image.size.width), height: max(size.height, image.size.height))
        }
    }

    private func outingReturnTarget() -> CGPoint {
        startPositionAnchor()
    }

    private func startPositionAnchor() -> CGPoint {
        anchorPoint(forCenterX: activitySpace.entrancePoint.x)
    }

    private func anchorPoint(forCenterX centerX: CGFloat) -> CGPoint {
        return activitySpace.dockEdgeClampedPoint(CGPoint(
            x: centerX - catWindow.catFrameSize.width / 2,
            y: activitySpace.baselineY
        ), contentWidth: catWindow.catFrameSize.width)
    }

    private func updateCurrentPositionPreservingState(_ point: CGPoint) {
        switch stateMachine.state {
        case .outing(.away):
            return
        case .outing(.leaving), .outing(.returning):
            stateMachine.updateOutingWalkPosition(point)
        default:
            stateMachine.updateVisiblePosition(point)
        }
        catWindow.setAnchor(point)
    }

    private func showRecallConfirmation() {
        guard case .outing(.away) = stateMachine.state else { return }
        let pose = renderer.randomPose(for: .dialogue)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        catWindow.show(at: outingReturnTarget())
        catWindow.showBubble(
            message: strings.recallConfirmation(catName: settings.catName),
            primaryTitle: strings.confirm,
            secondaryTitle: strings.cancel,
            onPrimary: { [weak self] in
                guard let self else { return }
                self.catWindow.hideBubble()
                self.returnFromOuting(forceEvent: true)
            },
            onSecondary: { [weak self] in
                guard let self else { return }
                self.catWindow.hideBubble()
                self.catWindow.hide()
            }
        )
    }

    private func petCat() {
        if settings.lifeSimulationEnabled {
            settings.petLife.apply(.pet)
            settingsStore.save(settings)
        }
        switch stateMachine.state {
        case .resting, .walking:
            stateScheduler.cancel()
            stateEndDate = nil
            stateMachine.enterManualLongDurationState(.resting)
            if renderer.hasAnimation(named: "pet_response", includeFallback: assetPack.id == defaultAssetPack.id) {
                playIdleActivity(.petResponse, onFinish: { [weak self] in
                    self?.applyConfiguredBehaviorMode()
                })
            } else {
                applyConfiguredBehaviorMode()
            }
        default:
            return
        }
    }

    private var configuredLongDurationState: LongDurationState? {
        switch settings.petBehaviorMode {
        case .random:
            return nil
        case .walking:
            return .walking
        default:
            return .resting
        }
    }

    private func selectBehaviorMode(_ mode: PetBehaviorMode) {
        guard availableBehaviorModes.contains(mode) else { return }
        guard settings.petBehaviorMode != mode else { return }
        settings.petBehaviorMode = mode
        settingsStore.save(settings)
        saveUserDataBackup()
        guard stateMachine.state.isLongDuration else { return }
        applyConfiguredBehaviorMode()
    }

    private func applyConfiguredBehaviorMode() {
        startupTimer?.invalidate()
        startupTimer = nil
        stateScheduler.cancel()
        stateEndDate = nil
        switch settings.petBehaviorMode {
        case .random:
            stateMachine.enterRandomLongDurationState()
        case .walking:
            stateMachine.enterManualLongDurationState(.walking)
        default:
            stateMachine.enterManualLongDurationState(.resting)
        }
    }

    private func clampedCatPoint(_ point: CGPoint) -> CGPoint {
        activitySpace.clampedPoint(point, contentSize: catWindow.catFrameSize, scope: settings.catActivityScope)
    }

    private func outingWalkOutDragPoint(_ point: CGPoint) -> CGPoint {
        if settings.catActivityScope == .desktop {
            let visibleRange = activitySpace.desktopWalkRangeForContent(width: catWindow.catFrameSize.width)
            let targetX = activitySpace.screenFrame.maxX + catWindow.catFrameSize.width
            let yRange = activitySpace.desktopYRangeForContent(height: catWindow.catFrameSize.height)
            return CGPoint(
                x: GeometryUtils.clamped(point.x, to: visibleRange.lowerBound ... targetX),
                y: GeometryUtils.clamped(point.y, to: yRange)
            )
        }
        let visibleRange = activitySpace.dockEdgeWalkRangeForContent(width: catWindow.catFrameSize.width)
        let targetX = activitySpace.screenFrame.maxX + catWindow.catFrameSize.width
        return CGPoint(
            x: GeometryUtils.clamped(point.x, to: visibleRange.lowerBound ... targetX),
            y: activitySpace.baselineY
        )
    }

    private func updateStateMachineParameters() {
        stateMachine.updateParameters(
            walkingDurationRange: durationRange(
                minimum: settings.walkDurationMinimum,
                maximum: settings.walkDurationMaximum,
                fallback: AppSettings.defaults.walkDurationMinimum ... AppSettings.defaults.walkDurationMaximum
            ),
            restingDurationRange: durationRange(
                minimum: settings.restDurationMinimum,
                maximum: settings.restDurationMaximum,
                fallback: AppSettings.defaults.restDurationMinimum ... AppSettings.defaults.restDurationMaximum
            )
        )
    }

    private func reloadSelectedAssetPack() {
        assetPack = assetLoader.loadSelectedPack(selectedID: settings.selectedAssetPackID)
        renderer = PoseRenderer(pack: assetPack, fallbackPack: defaultAssetPack)
        if !availableBehaviorModes.contains(settings.petBehaviorMode) {
            settings.petBehaviorMode = .random
            settingsStore.save(settings)
        }
        RuntimeDiagnostics.record("reloaded assetPack id=\(assetPack.id) root=\(assetPack.rootURL.path)")
        iconController.updateIconSource(appIconStore.prepareActiveIconSource(selectedPack: assetPack))
        settingsWindowController.update(dialogueImage: renderer.randomPose(for: .dialogue).image)
    }

    private func durationRange(
        minimum: TimeInterval,
        maximum: TimeInterval,
        fallback: ClosedRange<TimeInterval>
    ) -> ClosedRange<TimeInterval> {
        let lower = max(1, minimum)
        let upper = max(1, maximum)
        guard lower <= upper else { return fallback }
        return lower ... upper
    }

    private func configureCompanionEnvironment() {
        desktopToyController.onUse = { [weak self] kind, point in
            self?.reactToToy(kind, at: point)
        }
    }

    private func startCompanionTimers() {
        lifeTimer?.invalidate()
        lifeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.settings.lifeSimulationEnabled else { return }
                self.settings.petLife.advance(sleeping: self.currentIdleActivity?.isSleep == true)
                self.settingsStore.save(self.settings)
            }
        }
        environmentTimer?.invalidate()
        environmentTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateEnvironmentVisibility() }
        }
    }

    private func applyLifeEffect(for activity: IdleActivity) {
        guard settings.lifeSimulationEnabled else { return }
        switch activity {
        case .playToy, .signatureMove:
            settings.petLife.apply(.play)
        case .eating:
            settings.petLife.apply(.eat)
        case .drinking:
            settings.petLife.apply(.drink)
        case .sleepCurled, .sleepSide, .sleepLoaf:
            settings.petLife.apply(.sleep)
        case .grooming, .bellyRoll, .petResponse:
            break
        }
        settingsStore.save(settings)
    }

    private func placeToy(_ kind: PetToyKind) {
        let origin = CGPoint(
            x: catWindow.panel.frame.maxX + 14,
            y: max(activitySpace.visibleFrame.minY + 8, catWindow.panel.frame.minY)
        )
        desktopToyController.place(kind, near: origin)
    }

    private func reactToToy(_ kind: PetToyKind, at point: CGPoint) {
        let minimumInterval: TimeInterval = kind == .laser ? 0.08 : 0.25
        guard Date().timeIntervalSince(lastToyReactionDate) >= minimumInterval else { return }
        lastToyReactionDate = Date()
        guard stateMachine.state.isLongDuration else { return }

        let reaction = PetToyReactionCatalog.reaction(for: kind)
        if case .trackTarget = reaction {
            if !isTrackingLaser {
                if settings.lifeSimulationEnabled {
                    settings.petLife.apply(.play, toy: kind)
                    settingsStore.save(settings)
                }
                stateScheduler.cancel()
                stateEndDate = nil
                stopWalk()
                stateMachine.enterManualLongDurationState(.resting)
                stopIdleBehaviors()
                isTrackingLaser = true
            }
            showLook(toward: point, maximumDistance: .greatestFiniteMagnitude)
            laserReactionResumeTimer?.invalidate()
            laserReactionResumeTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.laserReactionResumeTimer = nil
                    self.isTrackingLaser = false
                    self.applyConfiguredBehaviorMode()
                }
            }
            return
        }

        laserReactionResumeTimer?.invalidate()
        laserReactionResumeTimer = nil
        isTrackingLaser = false
        guard case .behavior(let mode) = reaction, let activity = IdleActivity(mode: mode) else { return }
        if settings.lifeSimulationEnabled {
            switch kind {
            case .food: settings.petLife.apply(.eat)
            case .water: settings.petLife.apply(.drink)
            default: settings.petLife.apply(.play, toy: kind)
            }
        }
        settingsStore.save(settings)
        stateScheduler.cancel()
        stateEndDate = nil
        stateMachine.enterManualLongDurationState(.resting)
        catWindow.setMirrored(point.x < catWindow.panel.frame.midX)
        playIdleActivity(activity, recordLifeEvent: false, onFinish: { [weak self] in self?.applyConfiguredBehaviorMode() })
    }

    private func togglePreference(_ preference: PetPreferenceToggle) {
        switch preference {
        case .quietMode:
            settings.quietMode.toggle()
        case .reducedMotion:
            settings.reducedMotion.toggle()
            applyConfiguredBehaviorMode()
        case .batterySaver:
            settings.batterySaverEnabled.toggle()
            applyConfiguredBehaviorMode()
        case .hideDuringFullscreen:
            settings.hideDuringFullscreen.toggle()
        case .launchAtLogin:
            settings.launchAtLogin.toggle()
            updateLaunchAtLogin(enabled: settings.launchAtLogin)
        }
        settingsStore.save(settings)
        updateEnvironmentVisibility()
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DockCatLog.app.error("Failed to update launch-at-login: \(error.localizedDescription)")
        }
    }

    private func updateEnvironmentVisibility() {
        let shouldSuppress = settings.quietMode ||
            (settings.hideDuringFullscreen && DesktopEnvironmentMonitor.isForegroundApplicationFullscreen())
        guard shouldSuppress != isEnvironmentSuppressed else { return }
        isEnvironmentSuppressed = shouldSuppress
        if shouldSuppress {
            wasPetVisibleBeforeSuppression = catWindow.panel.isVisible
            catWindow.hide()
            desktopToyController.setHidden(true)
        } else {
            desktopToyController.setHidden(false)
            if wasPetVisibleBeforeSuppression, !stateMachine.state.isOuting {
                catWindow.show(at: clampedCatPoint(stateMachine.position))
            }
            wasPetVisibleBeforeSuppression = false
        }
    }

    private func openReleasesPage() {
        checkForUpdates(showCurrentResult: true)
    }

    private func checkForUpdatesIfDue() {
        guard settings.automaticUpdateChecks else { return }
        if let last = settings.lastUpdateCheckDate, Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        checkForUpdates(showCurrentResult: false)
    }

    private func checkForUpdates(showCurrentResult: Bool) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        updateChecker.check(currentVersion: version) { [weak self] result in
            guard let self else { return }
            self.settings.lastUpdateCheckDate = Date()
            self.settingsStore.save(self.settings)
            switch result {
            case let .updateAvailable(tag, page):
                let alert = NSAlert()
                alert.messageText = self.settings.language == .chinese ? "发现新版本 \(tag)" : "Update \(tag) is available"
                alert.informativeText = self.settings.language == .chinese
                    ? "将在 GitHub Releases 中打开经过发布流水线生成的安装包。"
                    : "Open the installer produced by the verified GitHub release workflow."
                alert.addButton(withTitle: self.settings.language == .chinese ? "打开下载页" : "Open downloads")
                alert.addButton(withTitle: self.strings.cancel)
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
            case .current where showCurrentResult:
                self.showAlert(
                    title: self.settings.language == .chinese ? "已经是最新版本" : "You're up to date",
                    message: self.settings.language == .chinese ? "当前没有更新。" : "No update is currently available."
                )
            case let .failed(message) where showCurrentResult:
                self.showAlert(
                    title: self.settings.language == .chinese ? "暂时无法检查更新" : "Unable to check for updates",
                    message: message
                )
            default:
                break
            }
        }
    }

    @objc private func startOutingFromMenu() {
        stateMachine.beginOutingPrompt()
    }

    @objc private func petFromMenu() {
        petCat()
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }
}

private enum IdleActivity {
    case playToy
    case grooming
    case bellyRoll
    case sleepCurled
    case sleepSide
    case sleepLoaf
    case eating
    case drinking
    case petResponse
    case signatureMove

    init?(mode: PetBehaviorMode) {
        switch mode {
        case .playToy: self = .playToy
        case .grooming: self = .grooming
        case .bellyRoll: self = .bellyRoll
        case .sleepCurled: self = .sleepCurled
        case .sleepSide: self = .sleepSide
        case .sleepLoaf: self = .sleepLoaf
        case .eating: self = .eating
        case .drinking: self = .drinking
        case .signatureMove: self = .signatureMove
        case .random, .resting, .walking: return nil
        }
    }

    static let autonomousChoices: [IdleActivity] = [
        .playToy,
        .grooming,
        .bellyRoll,
        .sleepCurled,
        .sleepSide,
        .sleepLoaf,
        .eating,
        .drinking,
        .signatureMove
    ]

    static func preview(named name: String) -> IdleActivity? {
        (autonomousChoices + [.petResponse, .signatureMove]).first {
            $0.defaultAssetName == name || ["pounce", "tail_wag", "binky", "war_dance", "signature_move"].contains(name)
        }
    }

    var mode: PetBehaviorMode? {
        switch self {
        case .playToy: return .playToy
        case .grooming: return .grooming
        case .bellyRoll: return .bellyRoll
        case .sleepCurled: return .sleepCurled
        case .sleepSide: return .sleepSide
        case .sleepLoaf: return .sleepLoaf
        case .eating: return .eating
        case .drinking: return .drinking
        case .signatureMove: return .signatureMove
        case .petResponse: return nil
        }
    }

    var defaultAssetName: String {
        switch self {
        case .playToy: return "play_toy"
        case .grooming: return "grooming"
        case .bellyRoll: return "belly_roll"
        case .sleepCurled: return "sleep_curled"
        case .sleepSide: return "sleep_side"
        case .sleepLoaf: return "sleep_loaf"
        case .eating: return "eating"
        case .drinking: return "drinking"
        case .petResponse: return "pet_response"
        case .signatureMove: return "signature_move"
        }
    }

    var isSleep: Bool {
        switch self {
        case .sleepCurled, .sleepSide, .sleepLoaf: true
        default: false
        }
    }
}

private final class CallbackTarget: NSObject {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    @objc func invoke() {
        callback()
    }
}
