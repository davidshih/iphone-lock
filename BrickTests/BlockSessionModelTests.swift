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

  func testEmergencyUnbrickStopsBlockAndDecrementsCount() async {
    let shieldService = MockShieldService()
    let defaults = testDefaults()
    let emergencyStore = MockEmergencyUnbrickStore()
    let model = makeModel(
      shieldService: shieldService,
      defaults: defaults,
      emergencyStore: emergencyStore
    )
    let scannedKey = ScannedNFCKey(id: "known-key", defaultName: "YubiKey", kind: .yubiKey, detail: "Tag type: ISO 7816")
    model.addSeedKey(id: "known-key")

    await model.handleKeyScan(scannedKey)
    model.useEmergencyUnbrick()

    XCTAssertFalse(model.isBlocking)
    XCTAssertEqual(model.emergencyUnbricksRemaining, 4)
    XCTAssertEqual(emergencyStore.value, 4)
    XCTAssertNil(defaults.object(forKey: BrickDefaults.emergencyUnbricksRemainingKey))
  }

  func testLegacyEmergencyCountMigratesToSecureStore() {
    let defaults = testDefaults()
    defaults.set(2, forKey: BrickDefaults.emergencyUnbricksRemainingKey)
    let emergencyStore = MockEmergencyUnbrickStore()

    let model = makeModel(defaults: defaults, emergencyStore: emergencyStore)

    XCTAssertEqual(model.emergencyUnbricksRemaining, 2)
    XCTAssertEqual(emergencyStore.value, 2)
    XCTAssertNil(defaults.object(forKey: BrickDefaults.emergencyUnbricksRemainingKey))
  }

  func testEmergencyCountFallsBackToDefaultsWhenSecureSaveFails() async {
    let defaults = testDefaults()
    let emergencyStore = MockEmergencyUnbrickStore()
    emergencyStore.value = 5
    let model = makeModel(defaults: defaults, emergencyStore: emergencyStore)
    model.addSeedKey(id: "known-key")
    await model.handleKeyScan(ScannedNFCKey(
      id: "known-key",
      defaultName: "YubiKey",
      kind: .yubiKey,
      detail: "Tag type: ISO 7816"
    ))
    emergencyStore.shouldFailSave = true

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
    XCTAssertTrue(model.isBlocking)
    XCTAssertEqual(model.statusMessage, "Unknown NFC key (intruder…). Only an already-paired key can unbrick.")
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

  func testFutureScheduledLockRestartsTimerAfterRestore() async {
    let defaults = testDefaults()
    let startAt = Date().addingTimeInterval(60 * 60)
    defaults.set(startAt, forKey: BrickDefaults.scheduledStartKey)
    let model = makeModel(defaults: defaults)

    XCTAssertFalse(model.hasActiveScheduleTimer)

    await model.restoreSessionIfNeeded()

    XCTAssertEqual(model.scheduledStartAt, startAt)
    XCTAssertTrue(model.hasActiveScheduleTimer)
    model.cancelScheduledLock()
  }

  func testPastClockTimeSchedulesNextCalendarDay() {
    let model = makeModel()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 10,
      hour: 15
    ))!
    let selectedTime = calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 10,
      hour: 14,
      minute: 30
    ))!
    let expected = calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 11,
      hour: 14,
      minute: 30
    ))!

    model.scheduleLock(at: selectedTime, now: now, calendar: calendar)

    XCTAssertEqual(model.scheduledStartAt?.timeIntervalSince1970, expected.timeIntervalSince1970)
    model.cancelScheduledLock()
  }

  func testUnknownKeyWithToggleScanAndPairedKeysDoesNotOfferPairing() async {
    let model = makeModel()
    model.addSeedKey(id: "known-key")

    await model.handleKeyScan(
      ScannedNFCKey(id: "random-uid", defaultName: "EasyCard", kind: .easyCard, detail: "Tag type: MiFare"),
      purpose: .toggleBlock
    )

    XCTAssertNil(model.pendingScannedKey)
    XCTAssertFalse(model.isBlocking)
    XCTAssertTrue(model.statusMessage.contains("Unknown key"))
  }

  func testUnknownKeyWithPairingScanOffersPairing() async {
    let model = makeModel()
    model.addSeedKey(id: "known-key")

    await model.handleKeyScan(
      ScannedNFCKey(id: "second-key", defaultName: "Titan Key", kind: .titanKey, detail: "Tag type: ISO 7816"),
      purpose: .pairing
    )

    XCTAssertNotNil(model.pendingScannedKey)
    XCTAssertFalse(model.isBlocking)
  }

  func testRandomUIDDetection() {
    XCTAssertTrue(NFCFingerprint.isRandomUID([0x08, 0x01, 0x02, 0x03]))
    XCTAssertFalse(NFCFingerprint.isRandomUID([0x04, 0x01, 0x02, 0x03]))
    XCTAssertFalse(NFCFingerprint.isRandomUID([0x08, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06]))
  }

  private func makeModel(
    shieldService: MockShieldService = MockShieldService(),
    defaults: UserDefaults? = nil,
    emergencyStore: MockEmergencyUnbrickStore = MockEmergencyUnbrickStore()
  ) -> BlockSessionModel {
    BlockSessionModel(
      shieldService: shieldService,
      authorizer: MockAuthorizer(),
      defaults: defaults ?? testDefaults(),
      emergencyStore: emergencyStore
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

private final class MockEmergencyUnbrickStore: EmergencyUnbrickStoring {
  var value: Int?
  var shouldFailSave = false

  func load() throws -> Int? {
    value
  }

  func save(_ value: Int) throws {
    if shouldFailSave {
      throw MockEmergencyStoreError.saveFailed
    }
    self.value = value
  }
}

private enum MockEmergencyStoreError: Error {
  case saveFailed
}
