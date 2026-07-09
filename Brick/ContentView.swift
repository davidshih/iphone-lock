import FamilyControls
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: BlockSessionModel
  @StateObject private var scanner = NFCCardScanner()
  @State private var isPickerPresented = false

  var body: some View {
    TabView {
      HomeView(scanner: scanner)
        .environmentObject(model)
        .tabItem {
          Label("Brick", systemImage: "lock.fill")
        }

      SettingsView(isPickerPresented: $isPickerPresented)
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
    .onAppear {
      scanner.onCardID = { cardID in
        Task {
          await model.handleCardScan(cardID)
        }
      }
    }
  }
}

private struct HomeView: View {
  @EnvironmentObject private var model: BlockSessionModel
  @ObservedObject var scanner: NFCCardScanner

  var body: some View {
    NavigationStack {
      VStack(spacing: 28) {
        Spacer(minLength: 12)

        statusBadge
        lockMark
        statusCopy
        cardPanel
        primaryAction

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
      Text(model.isBlocking ? "Your iPhone is bricked." : "Tap your EasyCard to brick.")
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)

      Text(model.isBlocking ? model.remainingText : "Blocks \(model.settings.targetName) for \(durationText).")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  private var cardPanel: some View {
    VStack(spacing: 14) {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.black)
          .frame(width: 54, height: 36)
          .overlay {
            Image(systemName: "wave.3.right")
              .font(.title3.weight(.semibold))
              .foregroundStyle(.white)
          }

        VStack(alignment: .leading, spacing: 3) {
          Text("EasyCard")
            .font(.headline)
          Text(model.pairedCardID == nil ? "Not paired yet" : "Paired")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      Text(model.statusMessage)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(18)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var primaryAction: some View {
    Button {
      scanner.beginScanning()
    } label: {
      Text(scanner.isScanning ? "Hold Near EasyCard" : "Scan EasyCard")
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    .buttonStyle(.borderedProminent)
    .tint(.black)
    .disabled(scanner.isScanning || !scanner.isAvailable)
    .accessibilityIdentifier("scanEasyCardButton")
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
  @Binding var isPickerPresented: Bool

  var body: some View {
    NavigationStack {
      Form {
        blockSettingsSection
        cardSection
        manualControlsSection
        diagnosticsSection
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

  private var cardSection: some View {
    Section("EasyCard") {
      LabeledContent("Pairing", value: model.pairedCardID == nil ? "Not paired" : "Paired")

      Button("Forget EasyCard", role: .destructive) {
        model.clearPairedCard()
      }
      .disabled(model.pairedCardID == nil)
    }
  }

  private var manualControlsSection: some View {
    Section("Manual Controls") {
      Button("Request Screen Time Access") {
        Task {
          await model.requestAuthorization()
        }
      }

      Button("Start Block") {
        Task {
          await model.startBlocking()
        }
      }
      .disabled(model.isBlocking)

      Button("End Block Now", role: .destructive) {
        model.stopBlocking(reason: "Unblocked manually.")
      }
      .disabled(!model.isBlocking)
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

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
      .environmentObject(BlockSessionModel())
  }
}
