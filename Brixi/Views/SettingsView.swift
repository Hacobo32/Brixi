//
// SettingsView.swift
//
// Glasses health check + fixes, plus stub Voice and About sections.
// Everything here reads/drives WearablesViewModel directly -- there's no
// separate settings view model, since registration/session/camera-access
// state already lives there and a second owner would just be two sources
// of truth for the same thing.
//

import MWDATCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var viewModel: WearablesViewModel

  @State private var cameraAccess: WearablesViewModel.CameraAccess = .unknown
  #if DEBUG
  // Same UserDefaults key CaptureDiagnostics reads -- Phase 0 of pile mode
  // (docs/pile-mode-spec.md): confirms the glasses' actual still-capture
  // resolution before building anything that depends on it.
  @AppStorage("com.brixi.debug.saveCaptures") private var saveCaptures = false
  #endif

  var body: some View {
    NavigationStack {
      List {
        Section {
          healthRow(
            title: "Registered",
            status: registrationStatusText,
            systemImage: registrationState == .registered ? "checkmark.circle.fill" : "xmark.circle",
            tint: registrationState == .registered ? .green : .secondary
          )
          healthRow(
            title: "Camera Permission",
            status: cameraAccessText,
            systemImage: cameraAccess == .granted ? "checkmark.circle.fill" : "xmark.circle",
            tint: cameraAccess == .granted ? .green : .secondary
          )
          healthRow(
            title: "Connected",
            status: viewModel.hasActiveDevice ? "Glasses active" : "No active glasses",
            systemImage: viewModel.hasActiveDevice ? "checkmark.circle.fill" : "xmark.circle",
            tint: viewModel.hasActiveDevice ? .green : .secondary
          )

          VStack(alignment: .leading, spacing: 8) {
            Button {
              Task { await viewModel.testCameraStream() }
            } label: {
              if viewModel.isTestingStream {
                HStack {
                  ProgressView()
                  Text("Testing camera stream…")
                }
              } else {
                Text("Test Stream")
              }
            }
            .disabled(viewModel.isTestingStream)

            if let result = viewModel.streamTestResult {
              Text(result)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 4)
        } header: {
          Text("Glasses")
        } footer: {
          Text(troubleshootingHint)
        }

        Section {
          Button("Reconnect") {
            viewModel.reconnect()
          }
          Button("Reset Registration", role: .destructive) {
            viewModel.resetRegistration()
          }
          NavigationLink("Debug Log") {
            debugLogView
          }
        }

        #if DEBUG
        Section {
          Toggle("Save Captures", isOn: $saveCaptures)
        } header: {
          Text("Developer")
        } footer: {
          Text("Saves every scan photo (glasses or phone) to your Photos library exactly as captured, with its real pixel dimensions logged -- for checking what resolution the camera pipeline actually produces.")
        }
        #endif

        Section("Voice") {
          Text("Voice commands aren't available yet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Section("About") {
          LabeledContent("Brixi", value: appVersion)
          Text("Set and part data provided by Rebrickable.com.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .task {
        cameraAccess = await viewModel.checkCameraAccess()
      }
      .refreshable {
        cameraAccess = await viewModel.checkCameraAccess()
      }
    }
  }

  private var registrationState: RegistrationState { viewModel.registrationState }

  private var registrationStatusText: String {
    switch registrationState {
    case .registered: "Registered"
    case .registering: "Registering…"
    case .available: "Not registered"
    case .unavailable: "Unavailable"
    @unknown default: "Unknown"
    }
  }

  private var cameraAccessText: String {
    switch cameraAccess {
    case .granted: "Granted"
    case .denied: "Denied"
    case .unknown: "Unknown (no glasses connected)"
    }
  }

  /// A plain-English nudge at whatever's actually blocking right now,
  /// ordered the same way the rows above read top to bottom.
  private var troubleshootingHint: String {
    if registrationState != .registered {
      return "Not registered yet. Tap Reconnect to start registration in Meta AI. If it bounces back with no change, make sure Developer Mode is on for this pair in Meta AI → Settings → Your glasses, then try Reset Registration."
    }
    if !viewModel.hasActiveDevice {
      return "Registered, but no glasses are currently active. Put them on, make sure they're linked in Meta AI, then tap Reconnect."
    }
    if cameraAccess == .denied {
      return "Camera access was denied in Meta AI. Open Meta AI → your app's permissions to allow it, then test the stream again."
    }
    return "Looks healthy. Run Test Stream to confirm the camera pipeline end to end."
  }

  private func healthRow(title: String, status: String, systemImage: String, tint: Color) -> some View {
    HStack {
      Label(title, systemImage: systemImage)
        .foregroundStyle(tint)
      Spacer()
      Text(status)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var debugLogView: some View {
    List(Array(viewModel.eventLog.enumerated()), id: \.offset) { _, entry in
      Text(entry)
        .font(.caption.monospaced())
    }
    .navigationTitle("Debug Log")
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if viewModel.eventLog.isEmpty {
        Text("No events yet.")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var appVersion: String {
    let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    return "v\(shortVersion) (\(build))"
  }
}
