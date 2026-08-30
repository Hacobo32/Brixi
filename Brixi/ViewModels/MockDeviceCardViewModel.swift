//
// MockDeviceCardViewModel.swift
//
// Controls one simulated device's power/wear/fold state. Camera-specific
// controls (feeds, photo capture, captouch) are left out of this slice —
// see /camera-streaming once the app actually streams.
//

#if DEBUG

import Combine
import Foundation
import MWDATMockDevice

@MainActor
final class MockDeviceCardViewModel: ObservableObject {
  let device: MockGlasses
  @Published var isPoweredOn: Bool = false
  @Published var isDonned: Bool = false
  @Published var isUnfolded: Bool = false

  init(device: MockGlasses) {
    self.device = device
  }

  var id: String { device.deviceIdentifier }
  var deviceName: String { "Mock glasses" }

  func powerOn() {
    device.powerOn()
    isPoweredOn = true
  }

  func powerOff() {
    device.powerOff()
    isPoweredOn = false
    isDonned = false
    isUnfolded = false
  }

  func don() {
    device.don()
    isDonned = true
    isUnfolded = true
  }

  func doff() {
    device.doff()
    isDonned = false
  }

  func unfold() {
    device.unfold()
    isUnfolded = true
  }

  func fold() {
    device.fold()
    isUnfolded = false
    isDonned = false
  }
}

#endif
