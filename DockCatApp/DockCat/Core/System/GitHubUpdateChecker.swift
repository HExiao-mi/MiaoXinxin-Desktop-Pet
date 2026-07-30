import Foundation

@MainActor
final class GitHubUpdateChecker {
    enum CheckResult {
        case updateAvailable(tag: String, page: URL)
        case current
        case failed(String)
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private let endpoint = URL(string: "https://api.github.com/repos/HExiao-mi/MiaoXinxin-Desktop-Pet/releases/latest")!

    func check(currentVersion: String, completion: @escaping (CheckResult) -> Void) {
        Task {
            do {
                var request = URLRequest(url: endpoint)
                request.setValue("MiaoXinxin-Desktop-Pet", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    completion(.failed("GitHub Releases unavailable"))
                    return
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                if Self.isNewer(release.tagName, than: currentVersion) {
                    completion(.updateAvailable(tag: release.tagName, page: release.htmlURL))
                } else {
                    completion(.current)
                }
            } catch {
                completion(.failed(error.localizedDescription))
            }
        }
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = versionParts(candidate)
        let rhs = versionParts(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    nonisolated private static func versionParts(_ value: String) -> [Int] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in Int(component.prefix(while: { $0.isNumber })) ?? 0 }
    }
}
