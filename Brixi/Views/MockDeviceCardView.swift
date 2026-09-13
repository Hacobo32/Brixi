//
// MockDeviceCardView.swift
//
// One paired mock device: power/wear/fold toggles that drive the same
// session-lifecycle transitions real glasses would.
//

#if DEBUG

import MWDATMockDevice
import PhotosUI
import SwiftUI

struct MockDeviceCardView: View {
  @ObservedObject var viewModel: MockDeviceCardViewModel
  let onUnpairDevice: () -> Void

  @State private var expanded = true
  @State private var photosPickerItem: PhotosPickerItem?

  var body: some View {
    CardView {
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.deviceName)
              .font(.headline)
              .fontWeight(.semibold)
              .foregroundStyle(.primary)
            Text(viewModel.id)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }

          Spacer()

          MockDeviceKitButton("Unpair", style: .destructive, expandsHorizontally: false) {
            onUnpairDevice()
          }
        }
        .contentShape(Rectangle())
        .onTapGesture {
          withAnimation {
            expanded.toggle()
          }
        }

        if expanded {
          Divider()
            .padding(.vertical, 4)

          VStack(spacing: 0) {
            Toggle(
              "Power",
              isOn: Binding(
                get: { viewModel.isPoweredOn },
                set: { $0 ? viewModel.powerOn() : viewModel.powerOff() }
              )
            )
            .frame(height: 36)

            Toggle(
              "Donned",
              isOn: Binding(
                get: { viewModel.isDonned },
                set: { $0 ? viewModel.don() : viewModel.doff() }
              )
            )
            .frame(height: 36)

            Toggle(
              "Unfolded",
              isOn: Binding(
                get: { viewModel.isUnfolded },
                set: { $0 ? viewModel.unfold() : viewModel.fold() }
              )
            )
            .frame(height: 36)
          }

          if viewModel.hasCapturedImage {
            Text("Has captured image")
              .font(.caption)
              .foregroundStyle(.green)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          PhotosPicker("Select Test Photo", selection: $photosPickerItem, matching: .images)
            .onChange(of: photosPickerItem) { _, newItem in
              Task {
                guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                let url = FileManager.default.temporaryDirectory
                  .appendingPathComponent(UUID().uuidString)
                  .appendingPathExtension("jpg")
                do {
                  try data.write(to: url)
                  viewModel.selectImage(from: url)
                } catch {
                  // Best-effort debug tooling; nothing to recover from here.
                }
              }
            }

          Menu {
            Button("Front camera") { viewModel.setCameraFeed(.front) }
            Button("Back camera") { viewModel.setCameraFeed(.back) }
          } label: {
            Text("Camera feed: \(cameraFeedLabel)")
          }
        }
      }
      .padding()
    }
    .alert("Camera access required", isPresented: $viewModel.showCameraPermissionAlert) {
      Button("Open Settings") {
        viewModel.openSettings()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Camera access was denied. Enable it in Settings to use the camera feed.")
    }
  }

  private var cameraFeedLabel: String {
    guard let source = viewModel.cameraSource else { return "None" }
    return source == .front ? "Front camera" : "Back camera"
  }
}

#endif
