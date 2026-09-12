//
// MockDeviceCardViewModel.swift
//
// Controls one simulated device's power/wear/fold state, plus the captured
// photo a paired mock device hands back from stream.capturePhoto() — the
// piece CameraCaptureController needs to be exercised without real glasses.
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
  @Published var hasCapturedImage: Bool = false

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

  /// Sets the photo the mock device's camera returns from a capture request,
  /// so `stream.capturePhoto()` has something real to hand back.
  func selectImage(from url: URL) {
    device.services.camera.setCapturedImage(fileURL: url)
    hasCapturedImage = true
  }
}

#endif
