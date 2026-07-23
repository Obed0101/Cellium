import XCTest
@testable import CelliumIntelligence

final class EncryptedSecretStoreTests: XCTestCase {
    func testRoundTripAndDeletionUseEncryptedFile() throws {
        let fileURL = makeFileURL()
        let store = EncryptedSecretStore(fileURL: fileURL, iterations: 100_000)
        let passphrase = "correct horse battery staple"
        let secret = "openrouter-secret-value"

        try store.setSecret(secret, for: .openRouter, passphrase: passphrase)

        XCTAssertEqual(
            try store.secret(for: .openRouter, passphrase: passphrase),
            secret
        )
        let encryptedData = try Data(contentsOf: fileURL)
        XCTAssertNil(encryptedData.range(of: Data(secret.utf8)))
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try store.deleteSecret(for: .openRouter, passphrase: passphrase)

        XCTAssertNil(try store.secret(for: .openRouter, passphrase: passphrase))
    }

    func testWrongPassphraseCannotReadSecret() throws {
        let store = EncryptedSecretStore(fileURL: makeFileURL(), iterations: 100_000)
        try store.setSecret("secret", for: .openRouter, passphrase: "right")

        XCTAssertThrowsError(try store.secret(for: .openRouter, passphrase: "wrong")) { error in
            XCTAssertEqual(error as? IntelligenceError, .secretPassphraseInvalid)
        }
    }

    func testBlankPassphraseIsRejected() {
        let store = EncryptedSecretStore(fileURL: makeFileURL(), iterations: 100_000)

        XCTAssertThrowsError(try store.setSecret("secret", for: .openRouter, passphrase: "  \n")) { error in
            XCTAssertEqual(error as? IntelligenceError, .secretPassphraseRequired)
        }
    }

    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CelliumEncryptedSecretStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
    }
}
