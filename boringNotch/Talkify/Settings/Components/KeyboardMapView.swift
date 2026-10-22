import SwiftUI

/// The user's own keyboard, drawn, with the bound keys lit.
///
/// "Which keys are still free" is a question about a physical object, and a
/// list of labels cannot answer it. This is drawn from the attached keyboard's
/// real shape and the selected input source's real legends, so it matches the
/// board someone is looking at rather than a US keyboard they may not own.
struct KeyboardMapView: View {
  /// One binding's worth of lit keys.
  struct Highlight: Equatable {
    let keyCodes: Set<Int64>
    let color: Color
    /// Dimmed until the row it belongs to is hovered, so a glance shows every
    /// binding and a hover picks one out.
    var isEmphasized: Bool
  }

  let layout: KeyboardLayout
  let highlights: [Highlight]
  private let unit: CGFloat = 26.5
  private let spacing: CGFloat = 3
  /// Set while a binding is being assigned: the keys picked so far, and what
  /// happens when one is clicked. Nil leaves the drawing display-only.
  var picked: Set<Int64> = []
  var onPick: ((Int64) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      ForEach(Array(KeyboardMap.rows(for: layout.shape).enumerated()), id: \.offset) { _, row in
        HStack(alignment: .bottom, spacing: spacing) {
          ForEach(Array(groups(of: row).enumerated()), id: \.offset) { _, group in
            if group.count == 2 {
              // Up over down, sharing the height of one key.
              VStack(spacing: spacing) {
                cap(for: group[0])
                cap(for: group[1])
              }
            } else {
              cap(for: group[0])
            }
          }
        }
      }
    }
    .accessibilityHidden(true)
  }

  /// The keys of a row, with up and down paired so they can be stacked.
  private func groups(of row: [KeyboardMap.Key]) -> [[KeyboardMap.Key]] {
    var groups: [[KeyboardMap.Key]] = []
    var index = 0
    while index < row.count {
      if row[index].keyCode == 126, index + 1 < row.count, row[index + 1].keyCode == 125 {
        groups.append([row[index], row[index + 1]])
        index += 2
      } else {
        groups.append([row[index]])
        index += 1
      }
    }
    return groups
  }

  private func cap(for key: KeyboardMap.Key) -> some View {
    if key.isTouchID {
      return AnyView(
        Circle()
          .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
          .background(Circle().fill(Color(white: 0.07)))
          .frame(width: unit * 0.62, height: unit * 0.62)
          .frame(width: unit * key.width, height: unit * key.height * 0.92)
      )
    }
    let lit = highlights.filter { $0.keyCodes.contains(key.keyCode) }
    let strongest = picked.contains(key.keyCode)
      ? Highlight(keyCodes: [], color: pickColor, isEmphasized: true)
      : (lit.first { $0.isEmphasized } ?? lit.first)
    let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

    return AnyView(shape
      .fill(fill(for: strongest))
      .overlay {
        shape.strokeBorder(border(for: strongest), lineWidth: strongest == nil ? 1 : 1.5)
      }
      .overlay {
        Text(caption(for: key))
          .font(.system(size: unit * 0.34, weight: .medium))
          .foregroundStyle(strongest == nil ? .white.opacity(0.4) : .white)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .padding(.horizontal, 2)
      }
      .frame(width: unit * key.width + spacing * (key.width - 1), height: height(of: key))
      .contentShape(Rectangle())
      .onTapGesture { onPick?(key.keyCode) }
      .allowsHitTesting(onPick != nil))
  }

  /// A key is as tall as it is wide per unit; a half-height key is half of that less the
  /// gap, so an up key and a down key stacked add up to one full key.
  private func height(of key: KeyboardMap.Key) -> CGFloat {
    key.height == 0.5 ? (unit - spacing) / 2 : unit * key.height
  }

  /// While picking, the selection outranks whatever the key is already bound
  /// to — the question on screen is what this binding will become.
  private var pickColor: Color { SettingsTheme.accent }

  private func fill(for highlight: Highlight?) -> AnyShapeStyle {
    guard let highlight else {
      return AnyShapeStyle(
        LinearGradient(
          colors: [Color(white: 0.13), Color(white: 0.09)],
          startPoint: .top,
          endPoint: .bottom
        )
      )
    }
    return AnyShapeStyle(highlight.color.opacity(highlight.isEmphasized ? 0.32 : 0.14))
  }

  private func border(for highlight: Highlight?) -> AnyShapeStyle {
    guard let highlight else { return AnyShapeStyle(Color.white.opacity(0.06)) }
    return AnyShapeStyle(highlight.color.opacity(highlight.isEmphasized ? 1 : 0.5))
  }

  /// A fixed glyph where the key has one, otherwise whatever this input source
  /// prints on it — which is how the same keycode reads Q on QWERTY, A on
  /// AZERTY and ქ in Georgian.
  private func caption(for key: KeyboardMap.Key) -> String {
    if let glyph = key.glyph { return glyph }
    return layout.legend(for: key.keyCode) ?? ""
  }
}
