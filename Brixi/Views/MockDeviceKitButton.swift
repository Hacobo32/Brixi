//
// MockDeviceKitButton.swift
//
// Button style shared by the MockDeviceKit debug screens.
//

#if DEBUG

import SwiftUI

struct MockDeviceKitButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  var backgroundColor: Color
  var foregroundColor: Color = .white
  var isFullWidth: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(foregroundColor.opacity(isEnabled ? 1.0 : 0.6))
      .padding(.horizontal)
      .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: 44)
      .background(backgroundColor.opacity(isEnabled ? 1.0 : 0.4))
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .opacity(configuration.isPressed ? 0.8 : 1.0)
  }
}

struct MockDeviceKitButton: View {
  enum Style {
    case primary
    case destructive

    var backgroundColor: Color {
      switch self {
      case .primary: .accentColor
      case .destructive: .red
      }
    }
  }

  let title: String
  let style: Style
  let expandsHorizontally: Bool
  let disabled: Bool
  let action: () -> Void

  init(
    _ title: String,
    style: Style = .primary,
    expandsHorizontally: Bool = true,
    disabled: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.style = style
    self.expandsHorizontally = expandsHorizontally
    self.disabled = disabled
    self.action = action
  }

  var body: some View {
    Button(title) {
      action()
    }
    .buttonStyle(
      MockDeviceKitButtonStyle(backgroundColor: style.backgroundColor, isFullWidth: expandsHorizontally)
    )
    .disabled(disabled)
  }
}

#endif
