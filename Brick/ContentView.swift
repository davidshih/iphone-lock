import FamilyControls
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: BlockSessionModel
  @StateObject private var scanner = NFCCardScanner()
  @State private var isPickerPresented = false

  var body: some View {
    TabView {
      HomeView(scanner: scanner, isPickerPresented: $isPickerPresented)
        .environmentObject(model)
        .tabItem {
          Label("Brick", systemImage: "lock.fill")
        }

      SettingsView(scanner: scanner, isPickerPresented: $isPickerPresented)
        .environmentObject(model)
        .tabItem {
          Label("Settings", systemImage: "slider.horizontal.3")
        }
    }
    .familyActivityPicker(
      isPresented: $isPickerPresented,
      selection: Binding(
        get: { model.selection },
        set: { model.updateSelection($0) }
      )
    )
    .sheet(item: $model.pendingScannedKey) { scannedKey in
      AddNFCKeySheet(
        scannedKey: scannedKey,
        onAdd: { name, kind in
          model.addPendingKey(displayName: name, kind: kind)
        },
        onCancel: {
          model.cancelPendingKey()
        }
      )
    }
    .onAppear {
      scanner.onKeyScanned = { scannedKey, purpose in
        Task {
          await model.handleKeyScan(scannedKey, purpose: purpose)
        }
      }
    }
  }
}

private struct HomeView: View {
  @EnvironmentObject private var model: BlockSessionModel
  @ObservedObject var scanner: NFCCardScanner
  @Binding var isPickerPresented: Bool
  @State private var scheduleTime = Date().addingTimeInterval(15 * 60)

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Spacer(minLength: 12)

        lockMark
        statusHeading
        setupAction
        durationPicker
        scheduledLockSection

        Spacer(minLength: 12)

        Text(model.statusMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)

        if let lastErrorMessage = scanner.lastErrorMessage {
          Text(lastErrorMessage)
            .font(.footnote)
            .foregroundStyle(Color.red)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }

        smallManualStop
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, 24)
      .padding(.bottom, 16)
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Brick")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Label(model.pairedKeys.isEmpty ? "No key" : "\(model.pairedKeys.count)", systemImage: "key.radiowaves.forward")
            .labelStyle(.titleAndIcon)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button {
            scanner.beginScanning()
          } label: {
            Label("Scan NFC", systemImage: scanner.isScanning ? "wave.3.right.circle.fill" : "wave.3.right.circle")
          }
          .disabled(scanner.isScanning || !scanner.isAvailable)
          .accessibilityIdentifier("scanNFCIconButton")
        }
      }
    }
  }

  private var lockMark: some View {
    Button {
      if model.isBlocking {
        scanner.beginScanning(reason: "Manual unbrick scan requested.", purpose: .toggleBlock)
      } else {
        Task {
          await model.startBlocking()
        }
      }
    } label: {
      ZStack {
        Circle()
          .fill(model.isBlocking ? Color.red : Color.green)
          .shadow(color: .black.opacity(0.15), radius: 24, y: 12)

        Image(systemName: model.isBlocking ? "lock.fill" : "lock.open.fill")
          .font(.system(size: 64, weight: .semibold))
          .foregroundStyle(Color.white)
          .opacity(scanner.isScanning ? 0.35 : 1)

        if scanner.isScanning {
          ProgressView()
            .tint(.white)
            .scaleEffect(1.8)
        }
      }
      .frame(width: 180, height: 180)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("lockMarkButton")
  }

  private var statusHeading: some View {
    VStack(spacing: 6) {
      Text(model.isBlocking ? "Bricked" : "Ready")
        .font(.title.weight(.bold))

      Text(model.isBlocking
        ? "\(model.remainingText) · Tap to scan your key"
        : "Tap to brick · \(model.settings.targetName) · \(durationText)")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  @ViewBuilder
  private var setupAction: some View {
    if !model.hasSelection {
      Button {
        isPickerPresented = true
      } label: {
        Label("Choose Apps and Websites", systemImage: "checklist")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.bordered)
      .tint(.black)
      .accessibilityIdentifier("chooseAppsHomeButton")
    }
  }

  private static let durationOptions = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480]

  // Settings 的 stepper 可調出不在清單裡的值（如 75m），併進來避免 Picker 對不到 tag 顯示空白
  private var durationOptions: [Int] {
    Self.durationOptions.contains(model.settings.durationMinutes)
      ? Self.durationOptions
      : (Self.durationOptions + [model.settings.durationMinutes]).sorted()
  }

  @ViewBuilder
  private var durationPicker: some View {
    if !model.isBlocking {
      HStack {
        Text("Block for")
          .font(.subheadline.weight(.semibold))

        Spacer()

        Picker("Block for", selection: Binding(
          get: { model.settings.durationMinutes },
          set: { model.settings.durationMinutes = $0 }
        )) {
          ForEach(durationOptions, id: \.self) { minutes in
            Text(Self.durationLabel(minutes: minutes)).tag(minutes)
          }
        }
        .pickerStyle(.menu)
        .tint(.primary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  @ViewBuilder
  private var scheduledLockSection: some View {
    if !model.isBlocking {
      HStack {
        if let scheduledStartAt = model.scheduledStartAt {
          TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("Bricking in \(Self.countdownText(until: scheduledStartAt, now: context.date))")
              .font(.subheadline.weight(.semibold))
          }

          Spacer()

          Button("Cancel", role: .destructive) {
            model.cancelScheduledLock()
          }
          .font(.subheadline.weight(.semibold))
          .buttonStyle(.plain)
          .foregroundStyle(Color.red)
        } else {
          Text("Auto-brick at")
            .font(.subheadline.weight(.semibold))

          Spacer()

          DatePicker(
            "Auto-brick at",
            selection: $scheduleTime,
            displayedComponents: .hourAndMinute
          )
          .labelsHidden()

          Button("Set") {
            let interval = scheduleTime.timeIntervalSinceNow
            // 選到已過去的時間 = 明天的那個時間（鬧鐘語意）
            model.scheduleLock(after: interval > 0 ? interval : interval + 86_400)
          }
          .font(.subheadline.weight(.semibold))
          .buttonStyle(.bordered)
          .tint(.black)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private static func durationLabel(minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60

    if hours > 0 && remainder > 0 {
      return "\(hours)h \(remainder)m"
    }

    if hours > 0 {
      return "\(hours)h"
    }

    return "\(remainder)m"
  }

  private static func countdownText(until date: Date, now: Date) -> String {
    let remaining = max(0, Int(date.timeIntervalSince(now)))
    let hours = remaining / 3600
    let minutes = (remaining % 3600) / 60
    let seconds = remaining % 60

    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }

    if minutes > 0 {
      return "\(minutes)m \(seconds)s"
    }

    return "\(seconds)s"
  }

  @ViewBuilder
  private var smallManualStop: some View {
    // Release builds must not offer a stop path that skips the NFC key.
    #if DEBUG
    if model.isBlocking {
      Button("Manual Stop (Debug)") {
        model.stopBlocking(reason: "Unblocked manually.")
      }
      .font(.footnote.weight(.semibold))
      .foregroundStyle(.red)
      .buttonStyle(.plain)
      .accessibilityIdentifier("manualStopHomeButton")
    }
    #endif
  }

  private var durationText: String {
    let hours = model.settings.durationMinutes / 60
    let minutes = model.settings.durationMinutes % 60

    if hours > 0 && minutes > 0 {
      return "\(hours)h \(minutes)m"
    }

    if hours > 0 {
      return "\(hours)h"
    }

    return "\(minutes)m"
  }
}

private struct SettingsView: View {
  @EnvironmentObject private var model: BlockSessionModel
  @ObservedObject var scanner: NFCCardScanner
  @Binding var isPickerPresented: Bool

  var body: some View {
    NavigationStack {
      Form {
        blockSettingsSection
        pairedKeysSection
        manualControlsSection
        emergencySection
        diagnosticsSection
        debugSection
      }
      .navigationTitle("Settings")
    }
  }

  private var blockSettingsSection: some View {
    Section("Block") {
      TextField("Target name", text: Binding(
        get: { model.settings.targetName },
        set: { model.settings.targetName = $0 }
      ))

      Stepper(value: Binding(
        get: { model.settings.durationMinutes },
        set: { model.settings.durationMinutes = $0 }
      ), in: 15...480, step: 15) {
        LabeledContent("Duration", value: durationText)
      }

      Button("Choose Apps and Websites") {
        isPickerPresented = true
      }

      LabeledContent("Selected", value: model.selection.summaryText)
    }
  }

  private var pairedKeysSection: some View {
    Section("Paired NFC Keys") {
      if model.pairedKeys.isEmpty {
        Text("No NFC keys paired.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.pairedKeys) { key in
          HStack(spacing: 12) {
            Image(systemName: iconName(for: key.kind))
              .foregroundStyle(.secondary)
              .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
              Text(key.displayName)
              Text("\(key.kind.displayName) · \(key.shortID)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Forget", role: .destructive) {
              model.forgetPairedKey(id: key.id)
            }
            .font(.subheadline)
          }
        }
      }

      Button {
        scanner.beginScanning(reason: "Pairing a new NFC key.", purpose: .pairing)
      } label: {
        Label("Add NFC Key", systemImage: "plus.circle")
      }
      .disabled(scanner.isScanning || !scanner.isAvailable)
    }
  }

  private var manualControlsSection: some View {
    Section("Manual Controls") {
      Button("Request Screen Time Access") {
        Task {
          await model.requestAuthorization()
        }
      }

      if model.isBlocking {
        // Release builds must not offer a stop path that skips the NFC key.
        #if DEBUG
        Button("End Block Now (Debug)") {
          model.stopBlocking(reason: "Unblocked manually.")
        }
        .foregroundStyle(Color.red)
        #endif
      } else {
        Button("Start Block") {
          Task {
            await model.startBlocking()
          }
        }
      }
    }
  }

  private var diagnosticsSection: some View {
    Section("Diagnostics") {
      LabeledContent("Mode", value: model.isBlocking ? "Blocking" : "Open")
      LabeledContent("Remaining", value: model.remainingText)
      LabeledContent("Screen Time", value: model.authorizationStatusText)
      Text("NFC and Screen Time require Apple-approved capabilities on a paid developer team.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var emergencySection: some View {
    Section("Emergency") {
      LabeledContent("Emergency Unbricks", value: "\(model.emergencyUnbricksRemaining) left")

      Button("Use Emergency Unbrick", role: .destructive) {
        model.useEmergencyUnbrick()
      }
      .disabled(!model.isBlocking || model.emergencyUnbricksRemaining == 0)

      Text("Use this only when you cannot reach your physical Brick.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var debugSection: some View {
    Section("Debug") {
      DisclosureGroup("NFC Diagnostics") {
        LabeledContent("Reader", value: scanner.isAvailable ? "Available" : "Unavailable")
        LabeledContent("Scanning", value: scanner.isScanning ? "Active" : "Idle")

        ForEach(Array(scanner.diagnosticLines.enumerated()), id: \.offset) { _, line in
          Text(line)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
    }
  }

  private func iconName(for kind: PairedNFCKeyKind) -> String {
    switch kind {
    case .easyCard:
      return "creditcard"
    case .yubiKey, .titanKey:
      return "key"
    case .nfcKey:
      return "key.radiowaves.forward"
    }
  }

  private var durationText: String {
    let hours = model.settings.durationMinutes / 60
    let minutes = model.settings.durationMinutes % 60

    if hours > 0 && minutes > 0 {
      return "\(hours)h \(minutes)m"
    }

    if hours > 0 {
      return "\(hours)h"
    }

    return "\(minutes)m"
  }
}

private struct AddNFCKeySheet: View {
  let scannedKey: ScannedNFCKey
  let onAdd: (String, PairedNFCKeyKind) -> Void
  let onCancel: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var displayName: String
  @State private var kind: PairedNFCKeyKind

  init(
    scannedKey: ScannedNFCKey,
    onAdd: @escaping (String, PairedNFCKeyKind) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.scannedKey = scannedKey
    self.onAdd = onAdd
    self.onCancel = onCancel
    _displayName = State(initialValue: scannedKey.defaultName)
    _kind = State(initialValue: scannedKey.kind)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField("Key name", text: $displayName)
          Picker("Type", selection: $kind) {
            ForEach(PairedNFCKeyKind.allCases, id: \.self) { kind in
              Text(kind.displayName).tag(kind)
            }
          }
        }

        Section("Detected NFC") {
          Text(scannedKey.detail)
            .font(.footnote.monospaced())
            .textSelection(.enabled)
          LabeledContent("Short ID", value: String(scannedKey.id.prefix(12)))
        }
      }
      .navigationTitle("Add this NFC key?")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            onCancel()
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Add Key") {
            onAdd(displayName, kind)
            dismiss()
          }
        }
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
      .environmentObject(BlockSessionModel())
  }
}
