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
  @Binding var showRecognitionTest: Bool
  @Binding var showPileSegmentationTest: Bool

  var body: some View {
    // Anchored bottom-trailing, not vertically centered across the whole
    // screen -- a Spacer() on both sides of the VStack used to center these
    // over whatever content sat underneath (e.g. the Needed Parts list's
    // Stepper controls), making them untappable. Views that place scrollable
    // content under this overlay should reserve matching bottom space (see
    // BuildDetailView's safeAreaInset).
    VStack {
      Spacer()
      HStack {
        Spacer()
        VStack(spacing: 8) {
          Button {
            showRecognitionTest = true
          } label: {
            Image(systemName: "viewfinder")
              .foregroundStyle(.white)
              .padding()
              .background(.secondary)
              .clipShape(Circle())
              .shadow(radius: 4)
          }
          .accessibilityIdentifier("recognition_test_button")
          Button {
            showPileSegmentationTest = true
          } label: {
            Image(systemName: "square.dashed")
              .foregroundStyle(.white)
              .padding()
              .background(.secondary)
              .clipShape(Circle())
              .shadow(radius: 4)
          }
          .accessibilityIdentifier("pile_segmentation_test_button")
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
        }
        .padding(.trailing)
        .padding(.bottom)
      }
    }
  }
}

#endif
