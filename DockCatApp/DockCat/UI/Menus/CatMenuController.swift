import AppKit

@MainActor
final class CatMenuController: NSObject {
    var onPet: (() -> Void)?
    var onBehaviorMode: ((PetBehaviorMode) -> Void)?
    var onToy: ((PetToyKind) -> Void)?
    var onClearToys: (() -> Void)?
    var onTogglePreference: ((PetPreferenceToggle) -> Void)?
    var onCheckUpdates: (() -> Void)?
    var onOuting: (() -> Void)?
    var onSettings: (() -> Void)?
    var onSleep: (() -> Void)?

    func show(
        snapshot: CatStatusSnapshot,
        language: AppLanguage,
        currentSettings: AppSettings,
        species: PetSpecies,
        availableBehaviorModes: [PetBehaviorMode],
        toys: [AssetManifest.ToyDefinition],
        at event: NSEvent,
        in view: NSView
    ) {
        let strings = AppStrings(language: language)
        let menu = NSMenu()
        menu.addItem(CatStatusMenuPresenter.statusItem(snapshot: snapshot, language: language))
        let lifeItem = NSMenuItem(title: strings.lifeLine(currentSettings.petLife), action: nil, keyEquivalent: "")
        lifeItem.isEnabled = false
        menu.addItem(lifeItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: strings.menuPet, action: #selector(pet), keyEquivalent: ""))
        menu.addItem(behaviorMenuItem(
            strings: strings,
            selectedMode: currentSettings.petBehaviorMode,
            species: species,
            availableModes: availableBehaviorModes
        ))
        if currentSettings.desktopToysEnabled {
            menu.addItem(toyMenuItem(strings: strings, toys: toys))
        }
        menu.addItem(NSMenuItem(title: strings.menuGoOut, action: #selector(outing), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggleItem(strings.menuQuietMode, enabled: currentSettings.quietMode, preference: .quietMode))
        menu.addItem(toggleItem(strings.menuReducedMotion, enabled: currentSettings.reducedMotion, preference: .reducedMotion))
        menu.addItem(toggleItem(strings.menuBatterySaver, enabled: currentSettings.batterySaverEnabled, preference: .batterySaver))
        menu.addItem(toggleItem(strings.menuHideFullscreen, enabled: currentSettings.hideDuringFullscreen, preference: .hideDuringFullscreen))
        menu.addItem(toggleItem(strings.menuLaunchAtLogin, enabled: currentSettings.launchAtLogin, preference: .launchAtLogin))
        menu.addItem(NSMenuItem(title: strings.menuCheckUpdates, action: #selector(checkUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: strings.menuSettings, action: #selector(settings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: strings.menuSleep, action: #selector(sleep), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func toyMenuItem(strings: AppStrings, toys: [AssetManifest.ToyDefinition]) -> NSMenuItem {
        let root = NSMenuItem(title: strings.menuToys, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: strings.menuToys)
        for toy in toys where toy.enabled {
            let item = NSMenuItem(title: toy.label ?? strings.toyTitle(toy.kind), action: #selector(placeToy(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = toy.kind.rawValue
            submenu.addItem(item)
        }
        submenu.addItem(NSMenuItem.separator())
        let clear = NSMenuItem(title: strings.menuClearToys, action: #selector(clearToys), keyEquivalent: "")
        clear.target = self
        submenu.addItem(clear)
        root.submenu = submenu
        return root
    }

    private func toggleItem(_ title: String, enabled: Bool, preference: PetPreferenceToggle) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(togglePreference(_:)), keyEquivalent: "")
        item.target = self
        item.state = enabled ? .on : .off
        item.representedObject = preference
        return item
    }

    private func behaviorMenuItem(
        strings: AppStrings,
        selectedMode: PetBehaviorMode,
        species: PetSpecies,
        availableModes: [PetBehaviorMode]
    ) -> NSMenuItem {
        let root = NSMenuItem(title: strings.menuBehaviorMode, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: strings.menuBehaviorMode)
        for mode in availableModes {
            let item = NSMenuItem(
                title: strings.behaviorModeTitle(mode, species: species),
                action: #selector(selectBehaviorMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == selectedMode ? .on : .off
            submenu.addItem(item)
        }
        root.submenu = submenu
        return root
    }

    @objc private func pet() {
        onPet?()
    }

    @objc private func selectBehaviorMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = PetBehaviorMode(rawValue: rawValue)
        else { return }
        onBehaviorMode?(mode)
    }

    @objc private func outing() {
        onOuting?()
    }

    @objc private func placeToy(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = PetToyKind(rawValue: raw) else { return }
        onToy?(kind)
    }

    @objc private func clearToys() { onClearToys?() }

    @objc private func togglePreference(_ sender: NSMenuItem) {
        guard let preference = sender.representedObject as? PetPreferenceToggle else { return }
        onTogglePreference?(preference)
    }

    @objc private func checkUpdates() { onCheckUpdates?() }

    @objc private func settings() {
        onSettings?()
    }

    @objc private func sleep() {
        onSleep?()
    }
}
