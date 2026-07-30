import Foundation

struct ReminderQueue {
    private(set) var item: ReminderType?

    mutating func enqueue(_ type: ReminderType) {
        guard let current = item else {
            item = type
            return
        }
        if type.priority > current.priority {
            item = type
        }
    }

    mutating func clear() {
        item = nil
    }
}

private extension ReminderType {
    var priority: Int {
        switch self {
        case .movement: return 3
        case .custom: return 2
        case .water: return 1
        }
    }
}
