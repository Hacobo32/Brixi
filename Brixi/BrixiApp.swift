//
// BrixiApp.swift
//
// Entry point. Configures the Meta Wearables Device Access Toolkit (DAT) SDK
// at launch and hosts the registration + connection lifecycle screen.
//

import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@main
struct BrixiApp: App {
  @StateObject private var wearablesViewModel: WearablesViewModel

  init() {
    do {
      try Wearables.configure()
    } catch {
      #if DEBUG
      NSLog("[Brixi] Failed to configure Wearables SDK: \(error)")
      #endif
    }
    self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: Wearables.shared))
  }

  var body: some Scene {
    WindowGroup {
      RegistrationView(viewModel: wearablesViewModel)
        .onOpenURL { url in
          Task {
            _ = try? await Wearables.shared.handleUrl(url)
          }
        }
        .alert("Something went wrong", isPresented: $wearablesViewModel.showError) {
          Button("OK") {
            wearablesViewModel.dismissError()
          }
        } message: {
          Text(wearablesViewModel.errorMessage)
        }
    }
  }
}
