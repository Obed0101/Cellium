import XCTest
@testable import CelliumIntelligence

final class LocalInstallationSecretStoreTests: XCTestCase {
    func testSecretIsCreatedReusedAndStoredWithPrivatePermissions() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CelliumLocalInstallationSecretStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("installation-secret", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = LocalInstallationSecretStore(fileURL: fileURL)
        let firstSecret = try store.secret()
        let secondSecret = try store.secret()

        XCTAssertFalse(firstSecret.isEmpty)
        XCTAssertEqual(firstSecret, secondSecret)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
