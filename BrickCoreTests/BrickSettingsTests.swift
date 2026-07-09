import BrickCore
import XCTest

final class BrickSettingsTests: XCTestCase {
  func testDefaultSettingsBlockRedditForTwoHours() {
    let settings = BrickSettings.redditDefault

    XCTAssertEqual(settings.targetName, "Reddit")
    XCTAssertEqual(settings.durationMinutes, 120)
    XCTAssertEqual(settings.durationSeconds, 7_200)
  }

  func testSettingsStoreClampsDurationWhenLoading() throws {
    let defaults = UserDefaults(suiteName: "BrickSettingsTests.\(UUID().uuidString)")!
    let settings = BrickSettings(targetName: "Reddit", durationMinutes: 10_000)
    let data = try JSONEncoder().encode(settings)
    defaults.set(data, forKey: BrickDefaults.settingsKey)

    let loaded = SettingsStore.load(defaults: defaults)

    XCTAssertEqual(loaded.durationMinutes, 480)
  }

  func testPairedNFCKeyStorePersistsMultipleKeys() {
    let defaults = UserDefaults(suiteName: "PairedNFCKeyStoreTests.\(UUID().uuidString)")!
    let keys = [
      PairedNFCKey(id: "easy-card-id", displayName: "EasyCard", kind: .easyCard, createdAt: Date(timeIntervalSince1970: 10)),
      PairedNFCKey(id: "yubikey-id", displayName: "YubiKey 5C", kind: .yubiKey, createdAt: Date(timeIntervalSince1970: 20)),
      PairedNFCKey(id: "titan-id", displayName: "Titan", kind: .titanKey, createdAt: Date(timeIntervalSince1970: 30))
    ]

    PairedNFCKeyStore.save(keys, defaults: defaults)

    XCTAssertEqual(PairedNFCKeyStore.load(defaults: defaults), keys)
  }

  func testPairedNFCKeyStoreMigratesLegacySingleCard() {
    let defaults = UserDefaults(suiteName: "PairedNFCKeyStoreTests.\(UUID().uuidString)")!
    defaults.set("legacy-card-id", forKey: BrickDefaults.pairedCardIDKey)

    let loaded = PairedNFCKeyStore.load(defaults: defaults)

    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded.first?.id, "legacy-card-id")
    XCTAssertEqual(loaded.first?.kind, .easyCard)
    XCTAssertNil(defaults.string(forKey: BrickDefaults.pairedCardIDKey))
  }
}
