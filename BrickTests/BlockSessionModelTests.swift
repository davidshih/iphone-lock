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

    XCTAssertTrue(model.isBlocking)
    XCTAssertEqual(model.pendingUnbrickRequest?.displayName, "Seed YubiKey")
    model.confirmPendingUnbrick()

    XCTAssertFalse(model.isBlocking)
    XCTAssertEqual(shieldService.clearCount, 1)
    XCTAssertEqual(model.statusMessage, "Unblocked by Seed YubiKey.")
  }

  func testCancelingPendingUnbrickKeepsBlockActive() async {
    let shieldService = MockShieldService()
    let model = makeModel(shieldService: shieldService)
    let scannedKey = ScannedNFCKey(id: "known-key", defaultName: "YubiKey", kind: .yubiKey, detail: "Tag type: ISO 7816")
    model.addSeedKey(id: "known-key")

    await model.handleKeyScan(scannedKey)
    await model.handleKeyScan(scannedKey)
    model.cancelPendingUnbrick()

    XCTAssertTrue(model.isBlocking)
    XCTAssertNil(model.pendingUnbrickRequest)
    XCTAssertEqual(model.statusMessage, "Stayed bricked.")
  }

  func testEmergencyUnbrickStopsBlockAndDecrementsCount() async {
    let shieldService = MockShieldService()
    let defaults = testDefaults()
    let model = makeModel(shieldService: shieldService, defaults: defaults)
    let scannedKey = ScannedNFCKey(id: "known-key", defaultName: "YubiKey", kind: .yubiKey, detail: "Tag type: ISO 7816")
    model.addSeedKey(id: "known-key")

    await model.handleKeyScan(scannedKey)
    model.useEmergencyUnbrick()

    XCTAssertFalse(model.isBlocking)
    XCTAssertEqual(model.emergencyUnbricksRemaining, 4)
    XCTAssertEqual(defaults.integer(forKey: BrickDefaults.emergencyUnbricksRemainingKey), 4)
  }

  func testUnknownKeyDuringBlockIsRejectedWithoutPairing() async {
    let model = makeModel()
    model.addSeedKey(id: "known-key")

    await model.handleKeyScan(ScannedNFCKey(id: "known-key", defaultName: "YubiKey", kind: .yubiKey, detail: "Tag type: ISO 7816"))
    XCTAssertTrue(model.isBlocking)

    await model.handleKeyScan(ScannedNFCKey(id: "intruder", defaultName: "EasyCard", kind: .easyCard, detail: "Tag type: MiFare"))

    XCTAssertNil(model.pendingScannedKey)
    XCTAssertNil(model.pendingUnbrickRequest)
    XCTAssertTrue(model.isBlocking)
    XCTAssertEqual(model.statusMessage, "Unknown NFC key. Only an already-paired key can unbrick.")
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

  func testScheduleLockThenDueStartsBlock() async {
    let shieldService = MockShieldService()
    let model = makeModel(shieldService: shieldService)

    model.scheduleLock(after: -1)
    XCTAssertNotNil(model.scheduledStartAt)

    await model.restoreSessionIfNeeded()

    XCTAssertTrue(model.isBlocking)
    XCTAssertNil(model.scheduledStartAt)
  }

  func testCancelScheduledLock() {
    let model = makeModel()

    model.scheduleLock(after: 15 * 60)
    XCTAssertNotNil(model.scheduledStartAt)

    model.cancelScheduledLock()

    XCTAssertNil(model.scheduledStartAt)
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
