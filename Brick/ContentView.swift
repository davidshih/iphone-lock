import FamilyControls
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: BlockSessionModel
  @StateObject private var scanner = NFCCardScanner()
  @State private var isPickerPresented = false

  var body: some View {
    NavigationStack {
      Form {
        statusSection
        targetSection
        nfcSection
        controlsSection
      }
      .navigationTitle("Brick Alpha")
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

  private var statusSection: some View {
    Section("Status") {
      LabeledContent("Mode", value: model.isBlocking ? "Blocking" : "Open")
      LabeledContent("Remaining", value: model.remainingText)
      LabeledContent("Screen Time", value: model.authorizationStatusText)
      Text(model.statusMessage)
        .foregroundStyle(.secondary)
    }
  }

  private var targetSection: some View {
    Section("Block Settings") {
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

  private var nfcSection: some View {
    Section("NFC Card") {
      LabeledContent("Card", value: model.pairedCardID == nil ? "Not paired" : "Paired")

      Button(scanner.isScanning ? "Scanning..." : "Scan NFC Card") {
        scanner.beginScanning()
      }
      .disabled(scanner.isScanning || !scanner.isAvailable)

      if !scanner.isAvailable {
        Text("NFC scanning requires a real iPhone.")
          .foregroundStyle(.secondary)
      }

      if let lastErrorMessage = scanner.lastErrorMessage {
        Text(lastErrorMessage)
          .foregroundStyle(.red)
      }

      Button("Forget Paired Card", role: .destructive) {
        model.clearPairedCard()
      }
      .disabled(model.pairedCardID == nil)
    }
  }

  private var controlsSection: some View {
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
