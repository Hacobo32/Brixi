//
// MockDeviceKitViewModel.swift
//
// Owns the set of paired mock devices so the debug menu can pair/unpair
// simulated Ray-Ban Meta glasses and drive their lifecycle without hardware.
//

#if DEBUG

import Combine
import Foundation
import MWDATMockDevice

@MainActor
final class MockDeviceKitViewModel: ObservableObject {
  private let mockDeviceKit: MockDeviceKitInterface
  @Published var cardViewModels: [MockDeviceCardViewModel] = []
  @Published var isEnabled: Bool
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""

  init(mockDeviceKit: MockDeviceKitInterface) {
    self.mockDeviceKit = mockDeviceKit
    self.isEnabled = mockDeviceKit.isEnabled
    self.cardViewModels = mockDeviceKit.pairedDevices
      .compactMap { $0 as? MockGlasses }
      .map { MockDeviceCardViewModel(device: $0) }
  }

  func enable() {
    mockDeviceKit.enable()
    isEnabled = true
  }

  func disable() {
    mockDeviceKit.disable()
    cardViewModels = []
    isEnabled = false
  }

  func pairGlasses() {
    let mockDevice: MockGlasses
    do {
      mockDevice = try mockDeviceKit.pairGlasses(model: .rayBanMeta)
    } catch {
      showError(error.localizedDescription)
      return
    }
    cardViewModels.append(MockDeviceCardViewModel(device: mockDevice))
  }

  func unpairDevice(_ device: MockDevice) {
    if let idx = cardViewModels.firstIndex(where: { $0.id == device.deviceIdentifier }) {
      cardViewModels.remove(at: idx)
      mockDeviceKit.unpairDevice(device)
    }
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func dismissError() {
    showError = false
  }
}

#endif
