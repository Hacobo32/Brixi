//
// RegistrationView.swift
//
// Smallest possible UI over the DAT SDK: register/unregister with Meta AI,
// then start/stop a device session and show its lifecycle state.
//

import MWDATCore
import SwiftUI

struct RegistrationView: View {
  var viewModel: WearablesViewModel

  var body: some View {
    VStack(spacing: 24) {
      Text("Brixi")
        .font(.largeTitle.bold())

      VStack(spacing: 8) {
        Text("Registration")
          .font(.headline)
        Text(registrationLabel)
          .foregroundStyle(.secondary)

        switch viewModel.registrationState {
        case .registered:
          Button("Disconnect Glasses", role: .destructive) {
            viewModel.disconnectGlasses()
          }
        case .registering:
          ProgressView()
        default:
          Button("Connect Glasses") {
            viewModel.connectGlasses()
          }
        }
      }

      if viewModel.registrationState == .registered {
        Divider()

        VStack(spacing: 8) {
          Text("Connection")
            .font(.headline)
          Text(sessionLabel)
            .foregroundStyle(.secondary)

          if viewModel.sessionState == nil {
            Button("Start Session") {
              viewModel.startSession()
            }
          } else {
            Button("Stop Session", role: .destructive) {
              viewModel.stopSession()
            }
          }
        }
      }
    }
    .padding()
  }

  private var registrationLabel: String {
    switch viewModel.registrationState {
    case .registered: "Registered"
    case .registering: "Registering…"
    case .available: "Not registered"
    case .unavailable: "Unavailable"
    @unknown default: "Unknown"
    }
  }

  private var sessionLabel: String {
    guard let state = viewModel.sessionState else { return "Not started" }
    return "\(state)"
  }
}
