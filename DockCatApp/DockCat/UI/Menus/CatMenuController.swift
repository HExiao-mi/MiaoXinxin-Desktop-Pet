import AppKit

@MainActor
final class CatMenuController: NSObject {
    var onPet: (() -> Void)?
    var onBehaviorMode: ((PetBehaviorMode) -> Void)?
    var onOuting: (() -> Void)?
    var onSettings: (() -> Void)?
    var onSleep: (() -> Void)?

    func show(
        snapshot: CatStatusSnapshot,
        language: AppLanguage,
        behaviorMode: PetBehaviorMode,
        species: PetSpecies,
        availableBehaviorModes: [PetBehaviorMode],
        at event: NSEvent,
        in view: NSView
    ) {
        let strings = AppStrings(language: language)
        let menu = NSMenu()
        menu.addItem(CatStatusMenuPresenter.statusItem(snapshot: snapshot, language: language))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: strings.menuPet, action: #selector(pet), keyEquivalent: ""))
        menu.addItem(behaviorMenuItem(
            strings: strings,
            selectedMode: behaviorMode,
            species: species,
            availableModes: availableBehaviorModes
        ))
        menu.addItem(NSMenuItem(title: strings.menuGoOut, action: #selector(outing), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: strings.menuSettings, action: #selector(settings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: strings.menuSleep, action: #selector(sleep), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
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

    @objc private func settings() {
        onSettings?()
    }

    @objc private func sleep() {
        onSleep?()
    }
}
