//
// BrixiApp.swift
//
// Entry point. Configures the Meta Wearables Device Access Toolkit (DAT) SDK
// at launch and hosts the main "pick a set, find its parts" flow. Glasses
// registration/connection lives behind a toolbar button now, rather than
// being the first screen -- that's dev-facing plumbing, not the product.
//

import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@main
struct BrixiApp: App {
  @StateObject private var wearablesViewModel: WearablesViewModel
  @StateObject private var buildStore = BuildProjectStore()
  @State private var showRegistration = false

  private let catalog: CatalogDatabase?
  private let rebrickableClient: RebrickableClient?
  private let setPickerViewModel: SetPickerViewModel

  #if DEBUG
  @State private var showDebugMenu = false
  @State private var showRecognitionTest = false
  @StateObject private var mockDeviceKitViewModel = MockDeviceKitViewModel(mockDeviceKit: MockDeviceKit.shared)
  @StateObject private var recognitionTestViewModel = RecognitionTestViewModel()
  #endif

  init() {
    do {
      try Wearables.configure()
    } catch {
      #if DEBUG
      NSLog("[Brixi] Failed to configure Wearables SDK: \(error)")
      #endif
    }
    self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: Wearables.shared))

    let catalog = try? CatalogDatabase()
    self.catalog = catalog
    self.rebrickableClient = RebrickableClient.fromInfoPlist()
    self.setPickerViewModel = SetPickerViewModel(catalog: catalog)
  }

  var body: some Scene {
    WindowGroup {
      SetPickerView(
        viewModel: setPickerViewModel,
        store: buildStore,
        client: rebrickableClient,
        catalog: catalog,
        onConnectGlasses: { showRegistration = true }
      )
        .onOpenURL { url in
          Task {
            _ = try? await Wearables.shared.handleUrl(url)
          }
        }
        .sheet(isPresented: $showRegistration) {
          RegistrationView(viewModel: wearablesViewModel)
        }
        .alert("Something went wrong", isPresented: $wearablesViewModel.showError) {
          Button("OK") {
            wearablesViewModel.dismissError()
          }
        } message: {
          Text(wearablesViewModel.errorMessage)
        }
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) {
          MockDeviceKitView(viewModel: mockDeviceKitViewModel)
        }
        .sheet(isPresented: $showRecognitionTest) {
          RecognitionTestView(viewModel: recognitionTestViewModel)
        }
        .overlay {
          DebugMenuView(showDebugMenu: $showDebugMenu, showRecognitionTest: $showRecognitionTest)
        }
        #endif
    }
  }
}
