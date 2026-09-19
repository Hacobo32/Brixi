//
// PhoneCameraCaptureView.swift
//
// Full-screen live phone-camera viewfinder + shutter button -- the
// phone-first scan path. Deliberately no alignment guide; see
// CameraPreviewView.
//

import SwiftUI

struct PhoneCameraCaptureView: View {
  let frameSource: PhoneCameraFrameSource
  let onCapture: (Data) -> Void
  let onCancel: () -> Void

  @State private var isCapturing = false
  @State private var errorMessage: String?

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black.ignoresSafeArea()

      CameraPreviewView(session: frameSource.session)
        .ignoresSafeArea()

      VStack(spacing: 16) {
        if let errorMessage {
          Text(errorMessage)
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }

        HStack {
          Button("Cancel", action: onCancel)
            .foregroundStyle(.white)

          Spacer()

          Button(action: capture) {
            Circle()
              .fill(.white)
              .frame(width: 72, height: 72)
              .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 2))
          }
          .disabled(isCapturing)

          Spacer()

          // Balances the Cancel button so the shutter stays centered.
          Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 24)
      }
      .padding(.bottom, 32)
    }
    .task {
      do {
        try await frameSource.start()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
    .onDisappear {
      frameSource.stop()
    }
  }

  private func capture() {
    isCapturing = true
    errorMessage = nil
    Task {
      do {
        let data = try await frameSource.captureOneFrame()
        onCapture(data)
      } catch {
        errorMessage = error.localizedDescription
      }
      isCapturing = false
    }
  }
}
