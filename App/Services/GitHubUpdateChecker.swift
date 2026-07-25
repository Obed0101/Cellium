import Foundation
import AppKit
import CryptoKit

struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

struct GitHubRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let name: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
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
    case updating(version: String)
    case failed
}

enum GitHubUpdateError: LocalizedError {
    case invalidResponse
    case unexpectedStatus(Int)
    case malformedRelease
    case missingUpdateAsset
    case invalidUpdateAsset
    case checksumMismatch
    case extractionFailed
    case installationFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .unexpectedStatus(status):
            return "GitHub returned HTTP status \(status)."
        case .malformedRelease:
            return "The latest GitHub release could not be read."
        case .missingUpdateAsset:
            return "The GitHub release does not contain an update package."
        case .invalidUpdateAsset:
            return "The GitHub update package is invalid."
        case .checksumMismatch:
            return "The downloaded update failed checksum verification."
        case .extractionFailed:
            return "The downloaded update could not be opened."
        case .installationFailed:
            return "The downloaded update could not be installed."
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

struct GitHubUpdateInstaller: Sendable {
    func prepare(asset: GitHubReleaseAsset, expectedBundleIdentifier: String) async throws -> URL {
        let fileName = URL(fileURLWithPath: asset.name).lastPathComponent
        guard fileName == asset.name, fileName.lowercased().hasSuffix(".zip") else {
            throw GitHubUpdateError.invalidUpdateAsset
        }
        guard let expectedDigest = normalizedDigest(asset.digest) else {
            throw GitHubUpdateError.missingUpdateAsset
        }

        let updateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cellium-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: updateDirectory,
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: asset.browserDownloadURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Cellium", forHTTPHeaderField: "User-Agent")

        let (downloadURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubUpdateError.unexpectedStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let archiveURL = updateDirectory.appendingPathComponent(fileName)
        try FileManager.default.moveItem(at: downloadURL, to: archiveURL)
        let archiveData = try Data(contentsOf: archiveURL)
        let actualDigest = SHA256.hash(data: archiveData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualDigest == expectedDigest else {
            throw GitHubUpdateError.checksumMismatch
        }

        let extractionDirectory = updateDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(
            at: extractionDirectory,
            withIntermediateDirectories: true
        )
        try runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path]
        )

        let appURL = extractionDirectory.appendingPathComponent("Cellium.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: appURL.path),
              let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == expectedBundleIdentifier else {
            throw GitHubUpdateError.extractionFailed
        }
        try runProcess(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appURL.path]
        )
        return appURL
    }

    func launchReplacement(sourceAppURL: URL, targetAppURL: URL) throws {
        let helperURL = sourceAppURL
            .deletingLastPathComponent()
            .appendingPathComponent("install-cellium-update.sh")
        let script = """
        #!/bin/sh
        set -eu
        SOURCE_APP="$1"
        TARGET_APP="$2"
        PARENT_PID="$3"

        while kill -0 "$PARENT_PID" 2>/dev/null; do
            sleep 0.25
        done

        /usr/bin/ditto --rsrc --noqtn "$SOURCE_APP" "$TARGET_APP"
        /usr/bin/open "$TARGET_APP"
        """
        try script.write(to: helperURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            helperURL.path,
            sourceAppURL.path,
            targetAppURL.path,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        try process.run()
    }

    private func normalizedDigest(_ digest: String?) -> String? {
        guard var digest else { return nil }
        digest = digest.lowercased()
        if digest.hasPrefix("sha256:") {
            digest.removeFirst("sha256:".count)
        }
        guard digest.count == 64,
              digest.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return digest
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitHubUpdateError.extractionFailed
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
