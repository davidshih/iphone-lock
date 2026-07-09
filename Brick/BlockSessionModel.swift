import FamilyControls
import Foundation

@MainActor
final class BlockSessionModel: ObservableObject {
  @Published private(set) var authorizationStatusText = "Not requested"
  @Published private(set) var activeSession: BlockSession?
  @Published private(set) var statusMessage = "Pair an EasyCard, then scan it to start blocking."
  @Published private(set) var pairedCardID: String?
  @Published var settings: BrickSettings {
    didSet {
      settings.clampDuration()
      SettingsStore.save(settings)
    }
  }
  @Published private(set) var selection: FamilyActivitySelection

  private let shieldService: ScreenTimeShieldServicing
  private var timer: Timer?

  var isBlocking: Bool {
    activeSession != nil
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
    defaults: UserDefaults = .standard
  ) {
    self.shieldService = shieldService
    self.settings = SettingsStore.load(defaults: defaults)
    self.selection = ActivitySelectionStore.load(defaults: defaults)
    self.pairedCardID = defaults.string(forKey: BrickDefaults.pairedCardIDKey)
  }

  func updateSelection(_ selection: FamilyActivitySelection) {
    self.selection = selection
    ActivitySelectionStore.save(selection)
  }

  func clearPairedCard() {
    pairedCardID = nil
    UserDefaults.standard.removeObject(forKey: BrickDefaults.pairedCardIDKey)
    statusMessage = "Pairing cleared. Scan your EasyCard to pair it again."
  }

  func handleCardScan(_ cardID: String) async {
    if pairedCardID == nil {
      pairedCardID = cardID
      UserDefaults.standard.set(cardID, forKey: BrickDefaults.pairedCardIDKey)
      statusMessage = "EasyCard paired. Scan it again to start blocking."
      return
    }

    guard pairedCardID == cardID else {
      statusMessage = "This is not the paired EasyCard."
      return
    }

    if isBlocking {
      stopBlocking(reason: "Unblocked by EasyCard.")
    } else {
      await startBlocking()
    }
  }

  func requestAuthorization() async {
    do {
      try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
      authorizationStatusText = "Approved"
    } catch {
      authorizationStatusText = "Denied or unavailable"
      statusMessage = error.localizedDescription
    }
  }

  func startBlocking() async {
    do {
      try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
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
    UserDefaults.standard.removeObject(forKey: BrickDefaults.sessionKey)
    timer?.invalidate()
    timer = nil
    statusMessage = reason
  }

  func restoreSessionIfNeeded() async {
    guard
      let data = UserDefaults.standard.data(forKey: BrickDefaults.sessionKey),
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
    UserDefaults.standard.set(data, forKey: BrickDefaults.sessionKey)
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
