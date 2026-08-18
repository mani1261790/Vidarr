import Foundation

struct UpdateCandidate {
    let version: String
    let url: URL
}

enum UpdateCheckResult {
    case updateAvailable(UpdateCandidate)
    case upToDate
    case failed
}

final class UpdateChecker {
    private struct ReleaseResponse: Decodable {
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    private let releasesAPI = URL(string: "https://api.github.com/repos/mani1261790/Vidarr/releases?per_page=30")!

    func check(completion: @escaping (UpdateCheckResult) -> Void) {
        let currentVersion = Self.normalizedVersionString(from: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        guard let currentVersion else {
            completion(.failed)
            return
        }

        var request = URLRequest(url: releasesAPI)
        request.timeoutInterval = 6
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VidarrUpdateChecker/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data else {
                completion(.failed)
                return
            }

            let decoder = JSONDecoder()
            guard let releases = try? decoder.decode([ReleaseResponse].self, from: data) else {
                completion(.failed)
                return
            }

            guard let latest = Self.bestStableRelease(from: releases),
                  let latestVersion = Self.normalizedVersionString(from: latest.tagName) else {
                completion(.failed)
                return
            }

            if Self.compareSemanticVersion(latestVersion, currentVersion) == .orderedDescending {
                completion(.updateAvailable(UpdateCandidate(version: latestVersion, url: latest.htmlURL)))
            } else {
                completion(.upToDate)
            }
        }.resume()
    }

    private static func bestStableRelease(from releases: [ReleaseResponse]) -> ReleaseResponse? {
        let stable = releases.filter { !$0.draft && !$0.prerelease }
        guard !stable.isEmpty else { return nil }

        return stable.max { lhs, rhs in
            let left = normalizedVersionString(from: lhs.tagName) ?? "0"
            let right = normalizedVersionString(from: rhs.tagName) ?? "0"
            return compareSemanticVersion(left, right) == .orderedAscending
        }
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
