import CryptoKit
import Foundation

/// Stores provider secrets in an authenticated encrypted file.
/// The passphrase is intentionally kept only in memory by the caller.
public final class EncryptedSecretStore: @unchecked Sendable {
    private struct Envelope: Codable {
        let version: Int
        let iterations: Int
        let salt: Data
        let combinedCiphertext: Data
    }

    private struct Payload: Codable {
        var secrets: [String: String]
    }

    private let fileURL: URL
    private let iterations: Int

    public init(
        fileURL: URL? = nil,
        iterations: Int = 120_000
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.iterations = max(100_000, iterations)
    }

    public func secret(
        for provider: IntelligenceProvider,
        passphrase: String
    ) throws -> String? {
        try load(passphrase: passphrase).secrets[provider.rawValue]
    }

    public func setSecret(
        _ secret: String,
        for provider: IntelligenceProvider,
        passphrase: String
    ) throws {
        var payload = try load(passphrase: passphrase)
        payload.secrets[provider.rawValue] = secret
        try save(payload, passphrase: passphrase)
    }

    public func deleteSecret(
        for provider: IntelligenceProvider,
        passphrase: String
    ) throws {
        var payload = try load(passphrase: passphrase)
        payload.secrets.removeValue(forKey: provider.rawValue)
        try save(payload, passphrase: passphrase)
    }

    private func load(passphrase: String) throws -> Payload {
        let normalizedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassphrase.isEmpty else {
            throw IntelligenceError.secretPassphraseRequired
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Payload(secrets: [:])
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1 else {
                throw IntelligenceError.secretStore
            }
            let key = deriveKey(
                from: normalizedPassphrase,
                salt: envelope.salt,
                iterations: envelope.iterations
            )
            let sealedBox = try AES.GCM.SealedBox(combined: envelope.combinedCiphertext)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder().decode(Payload.self, from: plaintext)
        } catch let error as IntelligenceError {
            throw error
        } catch {
            throw IntelligenceError.secretPassphraseInvalid
        }
    }

    private func save(_ payload: Payload, passphrase: String) throws {
        let normalizedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassphrase.isEmpty else {
            throw IntelligenceError.secretPassphraseRequired
        }

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
            let key = deriveKey(from: normalizedPassphrase, salt: salt, iterations: iterations)
            let plaintext = try JSONEncoder().encode(payload)
            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            guard let combinedCiphertext = sealedBox.combined else {
                throw IntelligenceError.secretStore
            }
            let envelope = Envelope(
                version: 1,
                iterations: iterations,
                salt: salt,
                combinedCiphertext: combinedCiphertext
            )
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch let error as IntelligenceError {
            throw error
        } catch {
            throw IntelligenceError.secretStore
        }
    }

    private func deriveKey(
        from passphrase: String,
        salt: Data,
        iterations: Int
    ) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(passphrase.utf8))
        var firstBlock = salt
        firstBlock.append(contentsOf: [0, 0, 0, 1])

        var previous = Array(
            HMAC<SHA256>.authenticationCode(for: firstBlock, using: passwordKey)
        )
        var derived = previous
        if iterations > 1 {
            for _ in 1..<iterations {
                previous = Array(
                    HMAC<SHA256>.authenticationCode(for: Data(previous), using: passwordKey)
                )
                for index in derived.indices {
                    derived[index] ^= previous[index]
                }
            }
        }
        return SymmetricKey(data: Data(derived))
    }

    private static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent("Cellium", isDirectory: true)
            .appendingPathComponent("intelligence-secrets.v3.enc", isDirectory: false)
    }

}
