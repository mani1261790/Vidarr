import Foundation

struct UpdateCandidate {
    let version: String
    let url: URL
}

final class UpdateChecker {
    private struct LatestReleaseResponse: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/mani1261790/Vidarr/releases/latest")!

    func check(completion: @escaping (UpdateCandidate?) -> Void) {
        let currentVersion = Self.normalizedVersionString(from: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        guard let currentVersion else {
            completion(nil)
            return
        }

        var request = URLRequest(url: latestReleaseAPI)
        request.timeoutInterval = 6
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VidarrUpdateChecker/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data else {
                completion(nil)
                return
            }

            let decoder = JSONDecoder()
            guard let release = try? decoder.decode(LatestReleaseResponse.self, from: data) else {
                completion(nil)
                return
            }

            guard let latestVersion = Self.normalizedVersionString(from: release.tagName) else {
                completion(nil)
                return
            }

            if Self.compareSemanticVersion(latestVersion, currentVersion) == .orderedDescending {
                completion(UpdateCandidate(version: latestVersion, url: release.htmlURL))
            } else {
                completion(nil)
            }
        }.resume()
    }

    private static func normalizedVersionString(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func compareSemanticVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(lhsParts.count, rhsParts.count)

        for idx in 0..<count {
            let l = idx < lhsParts.count ? lhsParts[idx] : 0
            let r = idx < rhsParts.count ? rhsParts[idx] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
}
