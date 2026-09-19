//
// CameraPreviewView.swift
//
// Thin SwiftUI wrapper around a live AVCaptureVideoPreviewLayer. No
// alignment guide or bounding box on purpose -- glasses framing is loose,
// so the phone viewfinder should tolerate that too, not train the user
// into carefully centering a piece before capture (see
// docs/rebrickable-brickognize-feasibility.md).
//

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession

  func makeUIView(context: Context) -> PreviewUIView {
    let view = PreviewUIView()
    view.videoPreviewLayer.session = session
    view.videoPreviewLayer.videoGravity = .resizeAspectFill
    return view
  }

  func updateUIView(_ uiView: PreviewUIView, context: Context) {}

  final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
      layer as! AVCaptureVideoPreviewLayer
    }
  }
}
