import AppKit
import Foundation

struct CatStatusSnapshot {
    var state: CatState
    var stateEndDate: Date?
    var outingEndDate: Date?
}

enum CatStatusMenuPresenter {
    static func statusItem(snapshot: CatStatusSnapshot, language: AppLanguage = .chinese, now: Date = Date()) -> NSMenuItem {
        let strings = AppStrings(language: language)
        let title = strings.statusLine(state: snapshot.state, remaining: remainingText(snapshot: snapshot, language: language, now: now))
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func remainingText(snapshot: CatStatusSnapshot, language: AppLanguage, now: Date) -> String {
        if case .transitioning = snapshot.state {
            return "--"
        }
        let endDate: Date?
        if case .outing = snapshot.state {
            endDate = snapshot.outingEndDate
        } else {
            endDate = snapshot.stateEndDate
        }
        guard let endDate else { return "--" }
        return TimeFormatter.menuRemaining(endDate.timeIntervalSince(now), language: language)
    }
}
