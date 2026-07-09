import Foundation

public struct BrickSettings: Codable, Equatable {
  public var targetName: String
  public var durationMinutes: Int

  public init(targetName: String, durationMinutes: Int) {
    self.targetName = targetName
    self.durationMinutes = durationMinutes
  }

  public static let redditDefault = BrickSettings(targetName: "Reddit", durationMinutes: 120)

  public var durationSeconds: TimeInterval {
    TimeInterval(durationMinutes * 60)
  }

  public mutating func clampDuration() {
    durationMinutes = min(max(durationMinutes, 15), 480)
  }
}

public struct BlockSession: Codable, Equatable {
  public let targetName: String
  public let endsAt: Date

  public init(targetName: String, endsAt: Date) {
    self.targetName = targetName
    self.endsAt = endsAt
  }
}

public enum BrickDefaults {
  public static let settingsKey = "brick.settings"
  public static let selectionKey = "brick.familyActivitySelection"
  public static let sessionKey = "brick.activeSession"
  public static let pairedCardIDKey = "brick.pairedCardID"
}

public enum SettingsStore {
  public static func load(defaults: UserDefaults = .standard) -> BrickSettings {
    guard
      let data = defaults.data(forKey: BrickDefaults.settingsKey),
      let settings = try? JSONDecoder().decode(BrickSettings.self, from: data)
    else {
      return .redditDefault
    }

    var clampedSettings = settings
    clampedSettings.clampDuration()
    return clampedSettings
  }

  public static func save(_ settings: BrickSettings, defaults: UserDefaults = .standard) {
    var clampedSettings = settings
    clampedSettings.clampDuration()
    let data = try? JSONEncoder().encode(clampedSettings)
    defaults.set(data, forKey: BrickDefaults.settingsKey)
  }
}
