import SwiftUI

@main
struct BrickApp: App {
  @StateObject private var model = BlockSessionModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .task {
          await model.restoreSessionIfNeeded()
        }
    }
  }
}
