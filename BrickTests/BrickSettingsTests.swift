import XCTest
@testable import Brick

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
}
