import Foundation

struct GitHubRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let name: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

enum GitHubUpdateResult: Equatable, Sendable {
    case current(version: String)
    case available(release: GitHubRelease)
}

enum GitHubUpdateState: Equatable, Sendable {
    case idle
    case checking
    case current(version: String)
    case available(version: String, name: String, url: URL)
    case failed
}

enum GitHubUpdateError: LocalizedError {
    case invalidResponse
    case unexpectedStatus(Int)
    case malformedRelease

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .unexpectedStatus(status):
            return "GitHub returned HTTP status \(status)."
        case .malformedRelease:
            return "The latest GitHub release could not be read."
        }
    }
}

struct GitHubUpdateChecker: Sendable {
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/Obed0101/Cellium/releases/latest"
    )!

    func check(currentVersion: String) async throws -> GitHubUpdateResult {
        let release = try await fetchLatestRelease()
        guard !release.draft, !release.prerelease else {
            return .current(version: currentVersion)
        }

        if CelliumVersion(release.tagName) > CelliumVersion(currentVersion) {
            return .available(release: release)
        }
        return .current(version: currentVersion)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Cellium", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubUpdateError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubUpdateError.unexpectedStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw GitHubUpdateError.malformedRelease
        }
    }
}

struct CelliumVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.drop(while: { $0 == "v" || $0 == "V" })
        let core = withoutPrefix.split(separator: "-", maxSplits: 1).first ?? "0"
        let parsed = core.split(separator: ".").map { component in
            Int(component.prefix(while: { $0.isNumber })) ?? 0
        }
        self.components = parsed.isEmpty ? [0] : parsed
    }

    static func < (lhs: CelliumVersion, rhs: CelliumVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}
