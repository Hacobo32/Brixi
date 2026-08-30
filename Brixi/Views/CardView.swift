//
// CardView.swift
//
// Reusable container that gives child content consistent card styling.
//

import SwiftUI

struct CardView<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(Color(.secondarySystemGroupedBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
  }
}
