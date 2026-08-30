//
// DebugMenuView.swift
//
// Floating button that opens the MockDeviceKit debug menu, so registration
// and the connection lifecycle can be exercised without physical glasses.
//

#if DEBUG

import SwiftUI

struct DebugMenuView: View {
  @Binding var showDebugMenu: Bool

  var body: some View {
    HStack {
      Spacer()
      VStack {
        Spacer()
        Button {
          showDebugMenu = true
        } label: {
          Image(systemName: "ladybug.fill")
            .foregroundStyle(.white)
            .padding()
            .background(.secondary)
            .clipShape(Circle())
            .shadow(radius: 4)
        }
        .accessibilityIdentifier("debug_menu_button")
        Spacer()
      }
      .padding(.trailing)
    }
  }
}

#endif
