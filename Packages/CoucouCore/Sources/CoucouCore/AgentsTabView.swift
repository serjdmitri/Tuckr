import SwiftUI

/// Coucou's agent cards and Mochi, laid out for the notch's Agents tab.
///
/// Coucou draws its island as 640 by 160 points: a 34-point header, then a
/// 98-point band of cards starting 10 points from the left and 42 from the
/// top, with Mochi placed in those island coordinates. The tab has no header
/// of Coucou's (the notch's own tab bar replaces it), so the cards start at
/// the tab's top-left corner and Mochi's layer is shifted by the same amount.
struct AgentsTabView: View {
  @ObservedObject private var state = AppState.shared

  /// The views an agent can put on screen. Chat, mail, upload and the rest
  /// belong to features this app does not surface.
  private static let shown: [IslandView] = [
    .overview, .empty, .approval, .question, .error, .finished, .confused,
  ]

  private static let islandSize = CGSize(width: 640, height: 160)
  private static let contentOrigin = CGPoint(x: 10, y: 42)

  private var effectiveView: IslandView {
    Self.shown.contains(state.view) ? state.view : .overview
  }

  /// Coucou's overview is two cards side by side in a 620-point band: a fixed
  /// 322-point card and the pills card taking the rest.
  private static let contentSize = CGSize(width: 620, height: 98)

  var body: some View {
    cards
      .frame(width: Self.contentSize.width, height: Self.contentSize.height)
      // Mochi's layer is an overlay, so its 640-point frame never widens the notch.
      .overlay(alignment: .topLeading) {
        BotPlacement(state: state, islandW: Self.islandSize.width, islandH: Self.islandSize.height)
          .frame(width: Self.islandSize.width, height: Self.islandSize.height, alignment: .topLeading)
          .offset(x: -Self.contentOrigin.x, y: -Self.contentOrigin.y)
      }
      .foregroundColor(Color(hex: "#F5F6F8"))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private var cards: some View {
    ZStack {
      ForEach(Self.shown, id: \.self) { view in
        let active = effectiveView == view
        let animation: Animation = active
          ? .spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
          : .easeIn(duration: 0.16)
        IslandViewContent(view: view, state: state)
          // Views behind the active one stay mounted for the cross-fade but
          // stop their endless animations.
          .environment(\.islandViewActive, active)
          .frame(maxWidth: .infinity)
          .frame(height: 98)
          .opacity(active ? 1 : 0)
          .scaleEffect(active ? 1 : 0.97)
          .allowsHitTesting(active)
          .animation(animation, value: effectiveView)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
