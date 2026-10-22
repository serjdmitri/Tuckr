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
  @State private var hovering = false
  @State private var loveTimer: DispatchWorkItem?
  @State private var lastLove: TimeInterval = 0

  /// The views an agent can put on screen. Chat, mail, upload and the rest
  /// belong to features this app does not surface.
  private static let shown: [IslandView] = [
    .overview, .empty, .approval, .question, .error, .finished, .confused,
  ]

  private static let islandSize = CGSize(width: 640, height: 160)
  private static let contentOrigin = CGPoint(x: 10, y: 42)

  /// The room the big Mochi has at the left of the cards (the text starts right of it),
  /// where several take its place.
  private static let squareSize = CGSize(width: 98, height: 98)

  /// Agents mid-turn, in the tab's pill order.
  private var workingTasks: [AgentTask] { state.tasks.filter { $0.isWorking } }

  /// Two or more agents working at once: the big Mochi gives way to one per agent.
  private var showsSquare: Bool { effectiveView == .overview && workingTasks.count >= 2 }

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
        if showsSquare {
          MochiSquare(
            tasks: workingTasks, focusId: state.focusId, counts: state.workingSessions
          ) { state.setFocus($0) }
          .frame(width: Self.squareSize.width, height: Self.squareSize.height)
          .offset(x: 4, y: 0)
        } else {
          BotPlacement(state: state, islandW: Self.islandSize.width, islandH: Self.islandSize.height)
            .frame(width: Self.islandSize.width, height: Self.islandSize.height, alignment: .topLeading)
            .offset(x: -Self.contentOrigin.x, y: -Self.contentOrigin.y)
        }
      }
      .overlay(alignment: .topLeading) { if !showsSquare { mochiHitArea } }
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

  /// Mochi's reactions to the pointer, as in Coucou's own island: a blink and a nudge on
  /// hover, love after a moment on him, and a slap on a click (three make him dizzy).
  private var mochiHitArea: some View {
    let (cx, cy, diameter, _) = botPosition(
      mode: .expanded, view: effectiveView,
      islandW: Self.islandSize.width, islandH: Self.islandSize.height,
      uploadProgress: 0, hasNotch: true)
    let size = max(diameter, 48) + 12
    return Color.clear
      .frame(width: size, height: size)
      .background(BotAnchor())
      .overlay(alignment: .topTrailing) {
        SessionBadge(count: state.workingSessions[state.focusId ?? ""] ?? 0)
          .offset(x: 4, y: -2)
      }
      .contentShape(Circle())
      .position(x: cx - Self.contentOrigin.x, y: cy - Self.contentOrigin.y)
      .onHover { inside in inside ? hoverIn() : hoverOut() }
      .onTapGesture {
        NotificationCenter.default.post(name: .triggerSlap, object: nil)
      }
  }

  private func hoverIn() {
    hovering = true
    guard state.stateOverride == nil, ProcessInfo.processInfo.systemUptime - lastLove > 6 else { return }
    NotificationCenter.default.post(name: .botBlink, object: nil)
    NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1.08))
    SoundEngine.shared.play("hover")
    loveTimer?.cancel()
    let work = DispatchWorkItem {
      guard hovering, state.stateOverride == nil,
        ProcessInfo.processInfo.systemUptime - lastLove > 6
      else { return }
      lastLove = ProcessInfo.processInfo.systemUptime
      NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
      SoundEngine.shared.play("love")
    }
    loveTimer = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: work)
  }

  private func hoverOut() {
    hovering = false
    loveTimer?.cancel()
    NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1))
  }
}

/// An invisible view centred on Mochi, so his eyes can find the pointer relative to him.
private struct BotAnchor: NSViewRepresentable {
  final class AnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil { AppState.shared.hostBotAnchor = self }
    }
  }

  func makeNSView(context: Context) -> AnchorView { AnchorView() }
  func updateNSView(_ view: AnchorView, context: Context) {
    if view.window != nil { AppState.shared.hostBotAnchor = view }
  }
}

/// "x2": that many sessions of one agent are working at once (they share its Mochi).
struct SessionBadge: View {
  let count: Int

  var body: some View {
    if count >= 2 {
      Text("\u{00D7}\(count)")
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .allowsHitTesting(false)
    }
  }
}

/// One Mochi per working agent: side by side for two, a 2 x 2 square for three or four,
/// and from five on the fourth place is a +N circle for the agents that do not fit.
struct MochiSquare: View {
  let tasks: [AgentTask]
  let focusId: String?
  let counts: [String: Int]
  let onSelect: (String) -> Void

  /// Up to four; past that, three, and the one whose details the card shows is always
  /// among them.
  private var shown: [AgentTask] {
    guard tasks.count > 4 else { return tasks }
    var picked = Array(tasks.prefix(3))
    if let focused = tasks.first(where: { $0.id == focusId }), !picked.contains(where: { $0.id == focused.id }) {
      picked[2] = focused
    }
    return picked
  }
  private var overflow: Int { tasks.count > 4 ? tasks.count - 3 : 0 }

  var body: some View {
    let cell: CGFloat = 46
    let columns = 2
    let items: [AnyHashable] = shown.map { AnyHashable($0.id) } + (overflow > 0 ? [AnyHashable("+N")] : [])
    LazyVGrid(
      columns: Array(repeating: GridItem(.fixed(cell), spacing: 6), count: columns),
      spacing: 6
    ) {
      ForEach(items, id: \.self) { item in
        if let id = item as? String, id == "+N" {
          ZStack {
            Circle().fill(Color.white.opacity(0.14))
            Text("+\(overflow)")
              .font(.system(size: 15, weight: .bold, design: .rounded))
              .foregroundColor(.white)
          }
          .frame(width: cell - 12, height: cell - 12)
          .frame(width: cell, height: cell)
          .help("\(overflow) more working")
        } else if let id = item as? String, let task = shown.first(where: { $0.id == id }) {
          MiniBotCanvasView(task: task)
            .frame(width: cell, height: cell)
            .overlay(
              Circle()
                .strokeBorder(Color(hex: task.color).opacity(0.9), lineWidth: 2)
                .padding(2)
                .opacity(focusId == task.id ? 1 : 0)
            )
            .overlay(alignment: .topTrailing) { SessionBadge(count: counts[task.id] ?? 0) }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(task.id) }
            .help(task.name)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }
}
