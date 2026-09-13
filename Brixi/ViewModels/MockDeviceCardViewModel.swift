//
// MockDeviceCardViewModel.swift
//
// Controls one simulated device's power/wear/fold state, plus the captured
// photo a paired mock device hands back from stream.capturePhoto() — the
// piece CameraCaptureController needs to be exercised without real glasses.
//

#if DEBUG

import AVFoundation
import Combine
import Foundation
import MWDATMockDevice
import UIKit

@MainActor
final class MockDeviceCardViewModel: ObservableObject {
  let device: MockGlasses
  @Published var isPoweredOn: Bool = false
  @Published var isDonned: Bool = false
  @Published var isUnfolded: Bool = false
  @Published var hasCapturedImage: Bool = false
  @Published var cameraSource: CameraFacing?
  @Published var showCameraPermissionAlert: Bool = false

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

  /// Feeds the mock camera's live stream from the phone's own front/back
  /// camera -- without a feed configured, `stream.start()` has nothing to
  /// stream and the stream immediately reports `.stopped`.
  func setCameraFeed(_ facing: CameraFacing) {
    Task {
      let status = AVCaptureDevice.authorizationStatus(for: .video)
      if status == .denied || status == .restricted {
        showCameraPermissionAlert = true
        return
      }
      let granted = await AVCaptureDevice.requestAccess(for: .video)
      guard granted else {
        showCameraPermissionAlert = true
        return
      }
      device.services.camera.setCameraFeed(cameraFacing: facing)
      cameraSource = facing
    }
  }

  func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
      UIApplication.shared.open(url)
    }
  }
}

#endif
