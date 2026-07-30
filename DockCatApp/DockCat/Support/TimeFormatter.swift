import Foundation

enum TimeFormatter {
    static func outingRemaining(_ interval: TimeInterval) -> String {
        let remaining = max(0, Int(interval.rounded(.up)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return "\(hours) h \(minutes) min"
        }
        return "\(max(1, minutes)) min"
    }

    static func menuRemaining(_ interval: TimeInterval, language: AppLanguage = .chinese) -> String {
        let remaining = max(0, interval)
        if remaining == 0 {
            return language == .chinese ? "0分钟" : "0 min"
        }
        let totalMinutes = max(1, Int((remaining / 60).rounded(.up)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return language == .chinese ? "\(hours)小时\(minutes)分钟" : "\(hours) h \(minutes) min"
        }
        return language == .chinese ? "\(totalMinutes)分钟" : "\(totalMinutes) min"
    }
}
