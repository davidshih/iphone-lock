import FamilyControls
import Foundation
import UserNotifications

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
  @Published private(set) var emergencyUnbricksRemaining: Int
  @Published private(set) var scheduledStartAt: Date?
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
  private var scheduleTimer: Timer?

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
    self.emergencyUnbricksRemaining = defaults.object(forKey: BrickDefaults.emergencyUnbricksRemainingKey) as? Int ?? 5
    self.scheduledStartAt = defaults.object(forKey: BrickDefaults.scheduledStartKey) as? Date
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

  func handleKeyScan(_ scannedKey: ScannedNFCKey, purpose: ScanPurpose = .toggleBlock) async {
    guard let pairedKey = pairedKeys.first(where: { $0.id == scannedKey.id }) else {
      if isBlocking {
        statusMessage = "Unknown NFC key (\(scannedKey.id.prefix(12))…). Only an already-paired key can unbrick."
        return
      }

      // 掃卡上鎖時卡對不上又已有配對 key，不該跳加卡 sheet（有些卡每次 tap 回報隨機 UID）。
      if purpose == .toggleBlock && !pairedKeys.isEmpty {
        statusMessage = "Unknown key (\(scannedKey.id.prefix(12))…). It doesn't match any paired key — pair it in Settings, or your card may use a random UID."
        return
      }

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

  func useEmergencyUnbrick() {
    guard isBlocking, emergencyUnbricksRemaining > 0 else {
      return
    }

    emergencyUnbricksRemaining -= 1
    defaults.set(emergencyUnbricksRemaining, forKey: BrickDefaults.emergencyUnbricksRemainingKey)
    stopBlocking(reason: "Emergency unbrick used. \(emergencyUnbricksRemaining) left.")
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
      clearScheduledLock()
      statusMessage = "Blocking \(settings.targetName) until \(session.endsAt.formatted(date: .omitted, time: .shortened)). Put your phone down."
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  func scheduleLock(after interval: TimeInterval) {
    let startAt = Date().addingTimeInterval(interval)
    scheduledStartAt = startAt
    defaults.set(startAt, forKey: BrickDefaults.scheduledStartKey)
    scheduleNotification(interval: interval)
    startScheduleTimer()
    statusMessage = "Scheduled to brick at \(startAt.formatted(date: .omitted, time: .shortened))."
  }

  func cancelScheduledLock() {
    clearScheduledLock()
    statusMessage = "Scheduled brick canceled."
  }

  private func clearScheduledLock() {
    scheduledStartAt = nil
    defaults.removeObject(forKey: BrickDefaults.scheduledStartKey)
    scheduleTimer?.invalidate()
    scheduleTimer = nil
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["brick.scheduledLock"])
  }

  private func startScheduleTimer() {
    scheduleTimer?.invalidate()
    scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.fireScheduledLockIfDue()
      }
    }
  }

  private func fireScheduledLockIfDue() async {
    guard let scheduledStartAt else {
      return
    }

    if isBlocking {
      clearScheduledLock()
      return
    }

    guard Date() >= scheduledStartAt else {
      return
    }

    clearScheduledLock()
    await startBlocking()
  }

  // ponytail: app 前景在場即刻上鎖，否則下次開 app 補上鎖；通知負責提醒。真背景排程需 DeviceActivity extension（deferred，見 improvement-plan.html P1）
  private func scheduleNotification(interval: TimeInterval) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

    let content = UNMutableNotificationContent()
    content.title = "Brick"
    content.body = "Time to brick — open Brick to lock."
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
    let request = UNNotificationRequest(identifier: "brick.scheduledLock", content: content, trigger: trigger)
    center.add(request)
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
      await fireScheduledLockIfDue()
      return
    }

    if session.endsAt <= Date() {
      stopBlocking(reason: "Previous block expired.")
      await fireScheduledLockIfDue()
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
    await fireScheduledLockIfDue()
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
