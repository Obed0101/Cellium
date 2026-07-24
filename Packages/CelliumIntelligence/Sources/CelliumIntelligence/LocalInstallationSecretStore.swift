import Foundation

/// Stores the local encryption passphrase in a private per-user file.
/// The credential file is never shown in UI.
public final class LocalInstallationSecretStore: @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    public func secret() throws -> String {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                guard let value = String(data: data, encoding: .utf8),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw IntelligenceError.secretStore
                }
                return value
            } catch let error as IntelligenceError {
                throw error
            } catch {
                throw IntelligenceError.secretStore
            }
        }

        var randomBytes = [UInt8](repeating: 0, count: 32)
        for index in randomBytes.indices {
            randomBytes[index] = UInt8.random(in: .min ... .max)
        }
        let value = Data(randomBytes).base64EncodedString()

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )
            try Data(value.utf8).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw IntelligenceError.secretStore
        }

        return value
    }

    private static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent("Cellium", isDirectory: true)
            .appendingPathComponent("intelligence-installation-secret.v3", isDirectory: false)
    }
}
