//
// MockDeviceKitView.swift
//
// Debug sheet for pairing and driving simulated Meta glasses, so
// registration and the DeviceSession lifecycle can be tested on the
// simulator without physical hardware.
//

#if DEBUG

import SwiftUI

struct MockDeviceKitView: View {
  @ObservedObject var viewModel: MockDeviceKitViewModel

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(spacing: 12) {
          CardView {
            VStack(spacing: 6) {
              HStack {
                Text("MockDeviceKit")
                  .font(.headline)
                  .fontWeight(.bold)
                Spacer()
                if viewModel.isEnabled {
                  Text("\(viewModel.cardViewModels.count) device(s) paired")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                }
              }

              Text("Simulates glasses so registration and connection lifecycle can be tested without hardware.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

              Divider()

              if viewModel.isEnabled {
                MockDeviceKitButton("Disable MockDeviceKit", style: .destructive) {
                  viewModel.disable()
                }
                MockDeviceKitButton("Pair Ray-Ban Meta", disabled: viewModel.cardViewModels.count >= 3) {
                  viewModel.pairGlasses()
                }
              } else {
                MockDeviceKitButton("Enable MockDeviceKit") {
                  viewModel.enable()
                }
              }
            }
            .padding(12)
          }

          if viewModel.isEnabled {
            ForEach(viewModel.cardViewModels, id: \.id) { cardViewModel in
              MockDeviceCardView(
                viewModel: cardViewModel,
                onUnpairDevice: {
                  viewModel.unpairDevice(cardViewModel.device)
                }
              )
            }
          }

          Spacer()
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Debug")
      .alert("Error", isPresented: $viewModel.showError) {
        Button("OK") {
          viewModel.dismissError()
        }
      } message: {
        Text(viewModel.errorMessage)
      }
    }
  }
}

#endif
