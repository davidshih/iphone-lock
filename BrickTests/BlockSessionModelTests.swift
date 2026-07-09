import FamilyControls
import XCTest
@testable import Brick

@MainActor
final class BlockSessionModelTests: XCTestCase {
  func testUnknownKeyCreatesPendingScanWithoutStartingBlock() async {
    let model = makeModel()
    let scannedKey = ScannedNFCKey(id: "new-key", defaultName: "YubiKey", kind: .yubiKey, detail: "Tag type: ISO 7816")

    await model.handleKeyScan(scannedKey)

    XCTAssertEqual(model.pendingScannedKey, scannedKey)
    XCTAssertFalse(model.isBlocking)
  }

  func testAddingPendingKeyPersistsIt() async {
    let defaults = testDefaults()
    let model = makeModel(defaults: defaults)
    let scannedKey = ScannedNFCKey(id: "new-key", defaultName: "YubiKey", kind: .yubiKey, detail: "Tag type: ISO 7816")

    await model.handleKeyScan(scannedKey)
    model.addPendingKey(displayName: "Work YubiKey", kind: .yubiKey)

    XCTAssertNil(model.pendingScannedKey)
    XCTAssertEqual(model.pairedKeys.map(\.displayName), ["Work YubiKey"])
    XCTAssertEqual(PairedNFCKeyStore.load(defaults: defaults).map(\.id), ["new-key"])
  }

  func testPairedKeyStartsBlock() async {
    let shieldService = MockShieldService()
    let model = makeModel(shieldService: shieldService)
    let scannedKey = ScannedNFCKey(id: "known-key", defaultName: "YubiKey", kind: .yubiKey, detail: "Tag type: ISO 7816")
    model.addSeedKey(id: "known-key")

    await model.handleKeyScan(scannedKey)

    XCTAssertTrue(model.isBlocking)
    XCTAssertEqual(shieldService.applyCount, 1)
    XCTAssertTrue(model.statusMessage.contains("Blocking Reddit"))
  }

  func testPairedKeyStopsActiveBlock() async {
    let shieldService = MockShieldService()
    let model = makeModel(shieldService: shieldService)
    let scannedKey = ScannedNFCKey(id: "known-key", defaultName: "YubiKey", kind: .yubiKey, detail: "Tag type: ISO 7816")
    model.addSeedKey(id: "known-key")

    await model.handleKeyScan(scannedKey)
    await model.handleKeyScan(scannedKey)

    XCTAssertFalse(model.isBlocking)
    XCTAssertEqual(shieldService.clearCount, 1)
    XCTAssertEqual(model.statusMessage, "Unblocked by Seed YubiKey.")
  }

  func testForgottenKeyBecomesPendingAgain() async {
    let model = makeModel()
    let scannedKey = ScannedNFCKey(id: "known-key", defaultName: "YubiKey", kind: .yubiKey, detail: "Tag type: ISO 7816")
    model.addSeedKey(id: "known-key")

    model.forgetPairedKey(id: "known-key")
    await model.handleKeyScan(scannedKey)

    XCTAssertEqual(model.pendingScannedKey, scannedKey)
    XCTAssertFalse(model.isBlocking)
  }

  private func makeModel(
    shieldService: MockShieldService = MockShieldService(),
    defaults: UserDefaults? = nil
  ) -> BlockSessionModel {
    BlockSessionModel(
      shieldService: shieldService,
      authorizer: MockAuthorizer(),
      defaults: defaults ?? testDefaults()
    )
  }

  private func testDefaults() -> UserDefaults {
    UserDefaults(suiteName: "BlockSessionModelTests.\(UUID().uuidString)")!
  }
}

private extension BlockSessionModel {
  func addSeedKey(id: String) {
    pendingScannedKey = ScannedNFCKey(id: id, defaultName: "YubiKey", kind: .yubiKey, detail: "Seed key")
    addPendingKey(displayName: "Seed YubiKey", kind: .yubiKey)
  }
}

private final class MockShieldService: ScreenTimeShieldServicing {
  private(set) var applyCount = 0
  private(set) var clearCount = 0

  func apply(selection: FamilyActivitySelection) throws {
    applyCount += 1
  }

  func clear() {
    clearCount += 1
  }
}

private struct MockAuthorizer: ScreenTimeAuthorizing {
  func requestAuthorization() async throws {}
}
