import Foundation

enum AppLanguage: String, Codable, Equatable, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    static func preferred(from preferredLanguages: [String]) -> AppLanguage {
        guard let first = preferredLanguages.first?.lowercased() else {
            return .english
        }
        return first.hasPrefix("zh") ? .chinese : .english
    }
}
