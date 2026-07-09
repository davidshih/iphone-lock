import FamilyControls
import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
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
    .sheet(item: $model.pendingUnbrickRequest) { request in
      ConfirmUnbrickSheet(
        request: request,
        onConfirm: {
          model.confirmPendingUnbrick()
        },
        onCancel: {
          model.cancelPendingUnbrick()
        }
      )
    }
    .onAppear {
      scanner.onKeyScanned = { scannedKey in
        Task {
          await model.handleKeyScan(scannedKey)
        }
      }
      startAutoScanIfNeeded(reason: "App opened. Auto scanning paired NFC keys.")
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else {
        return
      }

      startAutoScanIfNeeded(reason: "App became active. Auto scanning paired NFC keys.")
    }
  }

  private func startAutoScanIfNeeded(reason: String) {
    guard model.shouldAutoScanExistingKey,
          scanner.isAvailable,
          !scanner.isScanning
    else {
      return
    }

    scanner.beginScanning(reason: reason)
  }
}

private struct HomeView: View {
  @EnvironmentObject private var model: BlockSessionModel
  @ObservedObject var scanner: NFCCardScanner
  @Binding var isPickerPresented: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Spacer(minLength: 12)

        statusBadge
        lockMark
        statusCopy
        pairedKeySummary
        statusPanel
        setupAction
        primaryAction
        smallManualStop
        helperCopy

        if let lastErrorMessage = scanner.lastErrorMessage {
          Text(lastErrorMessage)
            .font(.footnote)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }

        Spacer(minLength: 24)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, 24)
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Brick")
      .toolbar {
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

  private var statusBadge: some View {
    Text(model.isBlocking ? "BRICKED" : "READY")
      .font(.caption.weight(.bold))
      .tracking(1.6)
      .foregroundStyle(model.isBlocking ? .white : .secondary)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(model.isBlocking ? Color.black : Color(.secondarySystemGroupedBackground))
      .clipShape(Capsule())
  }

  private var lockMark: some View {
    ZStack {
      Circle()
        .fill(model.isBlocking ? Color.black : Color.white)
        .shadow(color: .black.opacity(0.08), radius: 24, y: 12)

      Image(systemName: model.isBlocking ? "lock.fill" : "lock.open.fill")
        .font(.system(size: 58, weight: .semibold))
        .foregroundStyle(model.isBlocking ? .white : .black)
    }
    .frame(width: 160, height: 160)
  }

  private var statusCopy: some View {
    VStack(spacing: 8) {
      Text(model.isBlocking ? "Your iPhone is bricked." : "Ready to brick.")
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)

      Text(model.isBlocking ? model.remainingText : "Blocks \(model.settings.targetName) for \(durationText).")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  private var pairedKeySummary: some View {
    HStack(spacing: 12) {
      Image(systemName: "key.radiowaves.forward")
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 42, height: 42)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text("\(model.pairedKeys.count) paired NFC \(model.pairedKeys.count == 1 ? "key" : "keys")")
          .font(.headline)
        Text(scanner.isScanning ? "Hold near NFC key" : "Tap the small NFC icon to scan")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var statusPanel: some View {
    Text(model.statusMessage)
      .font(.footnote)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

  private var primaryAction: some View {
    Button {
      if model.isBlocking {
        scanner.beginScanning(reason: "Manual unbrick scan requested.")
      } else {
        Task {
          await model.startBlocking()
        }
      }
    } label: {
      Text(model.isBlocking ? "Scan Brick to Unbrick" : "Brick Now")
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    .buttonStyle(.borderedProminent)
    .tint(model.isBlocking ? .red : .black)
    .accessibilityIdentifier("brickNowButton")
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

  private var helperCopy: some View {
    Text(helperText)
      .font(.footnote)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 12)
  }

  private var helperText: String {
    if !scanner.isAvailable {
      return "NFC scanning is unavailable on this device."
    }

    if !model.hasSelection {
      return "Pick apps or websites before Brick Now or NFC scan can start a block."
    }

    return "Paired NFC keys also start or stop blocking automatically."
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
        scanner.beginScanning()
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

private struct ConfirmUnbrickSheet: View {
  let request: PendingUnbrickRequest
  let onConfirm: () -> Void
  let onCancel: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var countdown = 5

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Image(systemName: "lock.open.trianglebadge.exclamationmark")
          .font(.system(size: 56, weight: .semibold))
          .foregroundStyle(.red)

        VStack(spacing: 8) {
          Text("Unbrick with \(request.displayName)?")
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)

          Text("Take a breath before unlocking. Your Brick is doing its job.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        Text(countdown > 0 ? "\(countdown)" : "Ready")
          .font(.system(size: 44, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(countdown > 0 ? Color.secondary : Color.red)

        Button {
          onConfirm()
          dismiss()
        } label: {
          Text(countdown > 0 ? "Wait \(countdown)s" : "Unbrick")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(countdown > 0)

        Button("Stay Bricked") {
          onCancel()
          dismiss()
        }
        .font(.headline)
        .buttonStyle(.plain)
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("Confirm Unbrick")
      .navigationBarTitleDisplayMode(.inline)
      .task {
        while countdown > 0 {
          try? await Task.sleep(nanoseconds: 1_000_000_000)
          countdown -= 1
        }
      }
    }
    .interactiveDismissDisabled()
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
      .environmentObject(BlockSessionModel())
  }
}
