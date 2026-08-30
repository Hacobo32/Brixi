//
// MockDeviceCardView.swift
//
// One paired mock device: power/wear/fold toggles that drive the same
// session-lifecycle transitions real glasses would.
//

#if DEBUG

import MWDATMockDevice
import SwiftUI

struct MockDeviceCardView: View {
  @ObservedObject var viewModel: MockDeviceCardViewModel
  let onUnpairDevice: () -> Void

  @State private var expanded = true

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
        }
      }
      .padding()
    }
  }
}

#endif
