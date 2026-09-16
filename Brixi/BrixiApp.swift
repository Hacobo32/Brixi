//
// BrixiApp.swift
//
// Entry point. Configures the Meta Wearables Device Access Toolkit (DAT) SDK
// at launch, then routes on BuildProjectStore.activeSet: with one set to
// active, the app opens straight into that build's checklist; with none, it
// opens the set picker. "Switch Build" (from the checklist) and picking a
// set (from the picker) both just move that one pointer -- every build's
// own progress stays put in BuildProjectStore regardless of which is
// active. Glasses registration lives behind a toolbar button, not as the
// first screen -- that's dev-facing plumbing, not the product.
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
  @State private var showSetPicker = false

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
      Group {
        if let activeSet = buildStore.activeSet {
          BuildDetailView(
            viewModel: BuildDetailViewModel(
              setNum: activeSet.setNum,
              setName: activeSet.name,
              setImageURL: activeSet.imageURL,
              store: buildStore,
              client: rebrickableClient,
              catalog: catalog
            ),
            onSwitchBuild: { showSetPicker = true }
          )
          // Forces a fresh view (and a fresh @StateObject viewModel) when
          // the active set changes -- without this, switching from one
          // build to another would keep showing the first build's
          // viewModel, since @StateObject only initializes once per view
          // identity.
          .id(activeSet.setNum)
        } else {
          SetPickerView(
            viewModel: setPickerViewModel,
            store: buildStore,
            onConnectGlasses: { showRegistration = true },
            onSelectSet: { selection in buildStore.setActive(selection) }
          )
        }
      }
      .sheet(isPresented: $showSetPicker) {
        SetPickerView(
          viewModel: setPickerViewModel,
          store: buildStore,
          onConnectGlasses: { showRegistration = true },
          onSelectSet: { selection in
            buildStore.setActive(selection)
            showSetPicker = false
          }
        )
      }
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
