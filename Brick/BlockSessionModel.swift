import FamilyControls
import Foundation

protocol ScreenTimeAuthorizing {
  func requestAuthorization() async throws
}

struct ScreenTimeAuthorizer: ScreenTimeAuthorizing {
  func requestAuthorization() async throws {
    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
  }
}

@MainActor
final class BlockSessionModel: ObservableObject {
  @Published private(set) var authorizationStatusText = "Not requested"
  @Published private(set) var activeSession: BlockSession?
  @Published private(set) var statusMessage = "Brick manually, or scan a paired NFC key to start blocking."
  @Published private(set) var pairedKeys: [PairedNFCKey]
  @Published var pendingScannedKey: ScannedNFCKey?
  @Published var settings: BrickSettings {
    didSet {
      settings.clampDuration()
      SettingsStore.save(settings)
    }
  }
  @Published private(set) var selection: FamilyActivitySelection

  private let shieldService: ScreenTimeShieldServicing
  private let authorizer: ScreenTimeAuthorizing
  private let defaults: UserDefaults
  private var timer: Timer?

  var isBlocking: Bool {
    activeSession != nil
  }

  var hasSelection: Bool {
    !selection.isEmpty
  }

  var remainingText: String {
    guard let endsAt = activeSession?.endsAt else {
      return "Not blocking"
    }

    let remaining = max(0, Int(endsAt.timeIntervalSinceNow))
    let hours = remaining / 3600
    let minutes = (remaining % 3600) / 60

    if hours > 0 {
      return "\(hours)h \(minutes)m left"
    }

    return "\(minutes)m left"
  }

  init(
    shieldService: ScreenTimeShieldServicing = ScreenTimeShieldService(),
    authorizer: ScreenTimeAuthorizing = ScreenTimeAuthorizer(),
    defaults: UserDefaults = .standard
  ) {
    self.shieldService = shieldService
    self.authorizer = authorizer
    self.defaults = defaults
    self.settings = SettingsStore.load(defaults: defaults)
    self.selection = ActivitySelectionStore.load(defaults: defaults)
    self.pairedKeys = PairedNFCKeyStore.load(defaults: defaults)
  }

  func updateSelection(_ selection: FamilyActivitySelection) {
    self.selection = selection
    ActivitySelectionStore.save(selection)
  }

  func forgetPairedKey(id: String) {
    pairedKeys.removeAll { $0.id == id }
    PairedNFCKeyStore.save(pairedKeys, defaults: defaults)
    statusMessage = "NFC key removed."
  }

  func handleKeyScan(_ scannedKey: ScannedNFCKey) async {
    guard let pairedKey = pairedKeys.first(where: { $0.id == scannedKey.id }) else {
      pendingScannedKey = scannedKey
      statusMessage = "New NFC key detected. Confirm it before using it to brick."
      return
    }

    if isBlocking {
      stopBlocking(reason: "Unblocked by \(pairedKey.displayName).")
    } else {
      statusMessage = "\(pairedKey.displayName) scanned. Starting block..."
      await startBlocking()
    }
  }

  func addPendingKey(displayName: String, kind: PairedNFCKeyKind) {
    guard let pendingScannedKey else {
      return
    }

    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let pairedKey = PairedNFCKey(
      id: pendingScannedKey.id,
      displayName: trimmedName.isEmpty ? kind.displayName : trimmedName,
      kind: kind,
      createdAt: Date()
    )

    pairedKeys.append(pairedKey)
    PairedNFCKeyStore.save(pairedKeys, defaults: defaults)
    self.pendingScannedKey = nil
    statusMessage = "\(pairedKey.displayName) added. Scan it again to start or stop blocking."
  }

  func cancelPendingKey() {
    pendingScannedKey = nil
    statusMessage = "NFC key was not added."
  }

  func requestAuthorization() async {
    do {
      try await authorizer.requestAuthorization()
      authorizationStatusText = "Approved"
    } catch {
      authorizationStatusText = "Denied or unavailable"
      statusMessage = error.localizedDescription
    }
  }

  func startBlocking() async {
    do {
      try await authorizer.requestAuthorization()
      authorizationStatusText = "Approved"

      try shieldService.apply(selection: selection)

      let session = BlockSession(
        targetName: settings.targetName,
        endsAt: Date().addingTimeInterval(settings.durationSeconds)
      )
      activeSession = session
      saveSession(session)
      startTimer()
      statusMessage = "Blocking \(settings.targetName) until \(session.endsAt.formatted(date: .omitted, time: .shortened))."
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  func stopBlocking(reason: String = "Blocking ended.") {
    shieldService.clear()
    activeSession = nil
    defaults.removeObject(forKey: BrickDefaults.sessionKey)
    timer?.invalidate()
    timer = nil
    statusMessage = reason
  }

  func restoreSessionIfNeeded() async {
    guard
      let data = defaults.data(forKey: BrickDefaults.sessionKey),
      let session = try? JSONDecoder().decode(BlockSession.self, from: data)
    else {
      return
    }

    if session.endsAt <= Date() {
      stopBlocking(reason: "Previous block expired.")
      return
    }

    activeSession = session
    do {
      try shieldService.apply(selection: selection)
      startTimer()
      statusMessage = "Restored active \(session.targetName) block."
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func saveSession(_ session: BlockSession) {
    let data = try? JSONEncoder().encode(session)
    defaults.set(data, forKey: BrickDefaults.sessionKey)
  }

  private func startTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.expireIfNeeded()
      }
    }
  }

  private func expireIfNeeded() {
    guard let session = activeSession else {
      return
    }

    if session.endsAt <= Date() {
      stopBlocking(reason: "\(session.targetName) block expired.")
    } else {
      objectWillChange.send()
    }
  }
}
