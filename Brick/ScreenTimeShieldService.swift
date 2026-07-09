import FamilyControls
import Foundation
import ManagedSettings

enum BrickBlockingError: LocalizedError {
  case emptySelection

  var errorDescription: String? {
    switch self {
    case .emptySelection:
      return "Choose at least one app, app category, or website before starting a block."
    }
  }
}

protocol ScreenTimeShieldServicing {
  func apply(selection: FamilyActivitySelection) throws
  func clear()
}

struct ScreenTimeShieldService: ScreenTimeShieldServicing {
  private let store = ManagedSettingsStore()

  func apply(selection: FamilyActivitySelection) throws {
    guard !selection.isEmpty else {
      throw BrickBlockingError.emptySelection
    }

    store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
    store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
  }

  func clear() {
    store.clearAllSettings()
  }
}

extension FamilyActivitySelection {
  var isEmpty: Bool {
    applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
  }

  var summaryText: String {
    let appCount = applicationTokens.count
    let categoryCount = categoryTokens.count
    let webCount = webDomainTokens.count

    if appCount == 0 && categoryCount == 0 && webCount == 0 {
      return "No apps or websites selected"
    }

    return "\(appCount) apps, \(categoryCount) categories, \(webCount) websites"
  }
}

enum ActivitySelectionStore {
  static func load(defaults: UserDefaults = .standard) -> FamilyActivitySelection {
    guard
      let data = defaults.data(forKey: BrickDefaults.selectionKey),
      let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    else {
      return FamilyActivitySelection()
    }

    return selection
  }

  static func save(_ selection: FamilyActivitySelection, defaults: UserDefaults = .standard) {
    let data = try? JSONEncoder().encode(selection)
    defaults.set(data, forKey: BrickDefaults.selectionKey)
  }
}
