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

public enum PairedNFCKeyKind: String, Codable, CaseIterable, Equatable {
  case easyCard
  case yubiKey
  case titanKey
  case nfcKey

  public var displayName: String {
    switch self {
    case .easyCard:
      return "EasyCard"
    case .yubiKey:
      return "YubiKey"
    case .titanKey:
      return "Titan Key"
    case .nfcKey:
      return "NFC Key"
    }
  }
}

public struct PairedNFCKey: Codable, Equatable, Identifiable {
  public let id: String
  public var displayName: String
  public var kind: PairedNFCKeyKind
  public let createdAt: Date

  public init(id: String, displayName: String, kind: PairedNFCKeyKind, createdAt: Date) {
    self.id = id
    self.displayName = displayName
    self.kind = kind
    self.createdAt = createdAt
  }

  public var shortID: String {
    String(id.prefix(12))
  }
}

public struct ScannedNFCKey: Equatable, Identifiable {
  public let id: String
  public let defaultName: String
  public let kind: PairedNFCKeyKind
  public let detail: String

  public init(id: String, defaultName: String, kind: PairedNFCKeyKind, detail: String) {
    self.id = id
    self.defaultName = defaultName
    self.kind = kind
    self.detail = detail
  }
}

public struct PendingUnbrickRequest: Equatable, Identifiable {
  public let id: String
  public let displayName: String

  public init(id: String, displayName: String) {
    self.id = id
    self.displayName = displayName
  }
}

public enum BrickDefaults {
  public static let settingsKey = "brick.settings"
  public static let selectionKey = "brick.familyActivitySelection"
  public static let sessionKey = "brick.activeSession"
  public static let pairedCardIDKey = "brick.pairedCardID"
  public static let pairedNFCKeysKey = "brick.pairedNFCKeys"
  public static let emergencyUnbricksRemainingKey = "brick.emergencyUnbricksRemaining"
  public static let scheduledStartKey = "brick.scheduledStart"
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

public enum PairedNFCKeyStore {
  public static func load(defaults: UserDefaults = .standard) -> [PairedNFCKey] {
    if let data = defaults.data(forKey: BrickDefaults.pairedNFCKeysKey),
       let keys = try? JSONDecoder().decode([PairedNFCKey].self, from: data) {
      return keys
    }

    guard let legacyID = defaults.string(forKey: BrickDefaults.pairedCardIDKey) else {
      return []
    }

    let migratedKey = PairedNFCKey(
      id: legacyID,
      displayName: PairedNFCKeyKind.easyCard.displayName,
      kind: .easyCard,
      createdAt: Date()
    )
    save([migratedKey], defaults: defaults)
    defaults.removeObject(forKey: BrickDefaults.pairedCardIDKey)
    return [migratedKey]
  }

  public static func save(_ keys: [PairedNFCKey], defaults: UserDefaults = .standard) {
    let uniqueKeys = deduplicated(keys)
    let data = try? JSONEncoder().encode(uniqueKeys)
    defaults.set(data, forKey: BrickDefaults.pairedNFCKeysKey)
  }

  private static func deduplicated(_ keys: [PairedNFCKey]) -> [PairedNFCKey] {
    var seenIDs = Set<String>()
    return keys.filter { key in
      seenIDs.insert(key.id).inserted
    }
  }
}
