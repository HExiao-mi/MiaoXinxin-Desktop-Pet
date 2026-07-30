import AppKit

@MainActor
final class DockMenuController: NSObject {
    var stateProvider: (() -> CatState)?
    var statusProvider: (() -> CatStatusSnapshot?)?
    var settingsProvider: (() -> AppSettings)?
    var speciesProvider: (() -> PetSpecies)?
    var behaviorModesProvider: (() -> [PetBehaviorMode])?
    var onPet: (() -> Void)?
    var onBehaviorMode: ((PetBehaviorMode) -> Void)?
    var toysProvider: (() -> [AssetManifest.ToyDefinition])?
    var onToy: ((PetToyKind) -> Void)?
    var onClearToys: (() -> Void)?
    var onTogglePreference: ((PetPreferenceToggle) -> Void)?
    var onCheckUpdates: (() -> Void)?
    var onOuting: (() -> Void)?
    var onRecall: (() -> Void)?
    var onSettings: (() -> Void)?
    var onSleep: (() -> Void)?

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let state = stateProvider?()
        let currentSettings = settingsProvider?() ?? .defaults
        let strings = AppStrings(language: currentSettings.language)
        if let snapshot = statusProvider?() {
            menu.addItem(CatStatusMenuPresenter.statusItem(snapshot: snapshot, language: currentSettings.language))
            let life = NSMenuItem(title: strings.lifeLine(currentSettings.petLife), action: nil, keyEquivalent: "")
            life.isEnabled = false
            menu.addItem(life)
            menu.addItem(NSMenuItem.separator())
        }
        if case .outing(.away) = state {
            menu.addItem(item(strings.recall(currentSettings.catName), #selector(recall)))
        } else {
            menu.addItem(item(strings.menuPet, #selector(pet)))
            menu.addItem(behaviorMenuItem(
                strings: strings,
                selectedMode: currentSettings.petBehaviorMode,
                species: speciesProvider?() ?? .cat,
                availableModes: behaviorModesProvider?() ?? PetBehaviorMode.allCases
            ))
            if currentSettings.desktopToysEnabled {
                menu.addItem(toyMenuItem(strings: strings, toys: toysProvider?() ?? []))
            }
            menu.addItem(item(strings.menuGoOut, #selector(outing)))
        }
        menu.addItem(toggleItem(strings.menuQuietMode, enabled: currentSettings.quietMode, preference: .quietMode))
        menu.addItem(toggleItem(strings.menuReducedMotion, enabled: currentSettings.reducedMotion, preference: .reducedMotion))
        menu.addItem(toggleItem(strings.menuBatterySaver, enabled: currentSettings.batterySaverEnabled, preference: .batterySaver))
        menu.addItem(toggleItem(strings.menuHideFullscreen, enabled: currentSettings.hideDuringFullscreen, preference: .hideDuringFullscreen))
        menu.addItem(toggleItem(strings.menuLaunchAtLogin, enabled: currentSettings.launchAtLogin, preference: .launchAtLogin))
        menu.addItem(item(strings.menuCheckUpdates, #selector(checkUpdates)))
        menu.addItem(item(strings.menuSettings, #selector(settings)))
        menu.addItem(item(strings.menuSleep, #selector(sleep)))
        return menu
    }

    private func toyMenuItem(strings: AppStrings, toys: [AssetManifest.ToyDefinition]) -> NSMenuItem {
        let root = NSMenuItem(title: strings.menuToys, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: strings.menuToys)
        for toy in toys where toy.enabled {
            let toyItem = item(toy.label ?? strings.toyTitle(toy.kind), #selector(placeToy(_:)))
            toyItem.representedObject = toy.kind.rawValue
            submenu.addItem(toyItem)
        }
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(item(strings.menuClearToys, #selector(clearToys)))
        root.submenu = submenu
        return root
    }

    private func toggleItem(_ title: String, enabled: Bool, preference: PetPreferenceToggle) -> NSMenuItem {
        let result = item(title, #selector(togglePreference(_:)))
        result.state = enabled ? .on : .off
        result.representedObject = preference
        return result
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
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
            let modeItem = item(strings.behaviorModeTitle(mode, species: species), #selector(selectBehaviorMode(_:)))
            modeItem.representedObject = mode.rawValue
            modeItem.state = mode == selectedMode ? .on : .off
            submenu.addItem(modeItem)
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

    @objc private func recall() {
        onRecall?()
    }

    @objc private func settings() {
        onSettings?()
    }

    @objc private func sleep() {
        onSleep?()
    }
}
