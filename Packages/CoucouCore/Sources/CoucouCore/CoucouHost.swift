import AppKit
import Combine
import SwiftUI

/// The host-facing door into Coucou. Everything else in this module is
/// Coucou's own code, copied unchanged from the upstream commit recorded in
/// UPSTREAM.md; this file and AgentsTabView.swift are the only additions.
@MainActor
public enum CoucouHost {
  public nonisolated static let isLinked = true

  private static var started = false
  private static var hookExpandObserver: NSObjectProtocol?

  /// Where Coucou's agent UI is shown. The host sets this to follow its notch:
  /// `expanded` while the notch is open on the Agents tab, `compact` while it
  /// is closed and an agent is around (Mochi and the mini grid in the ears),
  /// `hidden` otherwise.
  public enum Surface: Equatable {
    case hidden, compact, expanded
  }

  public static func setSurface(_ surface: Surface) {
    let state = AppState.shared
    let mode: IslandMode
    switch surface {
    case .hidden: mode = .hidden
    case .compact: mode = .compact
    case .expanded: mode = .expanded
    }
    guard state.mode != mode else { return }
    let previous = state.mode
    state.mode = mode
    // The pill shown before another pill's alert comes back when the card goes.
    if previous == .expanded { HookServer.shared.restoreAlertFocus() }
  }

  /// Seconds the notch stays open after an alert nobody is looking at,
  /// Coucou's own "Close after" setting.
  public static var autoCloseInterval: TimeInterval { AppState.shared.autoCloseInterval }

  /// Called when an agent event wants the notch open on the Agents tab: a
  /// permission request, a question, or a session that finished or failed.
  public static var onExpandRequested: (() -> Void)?

  /// Starts what the agents need and nothing else: the hook socket that
  /// Claude Code and the other agents talk to, and Coucou's state. Coucou's
  /// own island window, menu icon, hot keys, dictation and integrations stay
  /// off.
  public static func start() {
    guard !started else { return }
    started = true

    // nb-hook closing its socket early must not crash the app.
    signal(SIGPIPE, SIG_IGN)
    // Coucou warms its Keychain wrapper here in the standalone app. It is left
    // cold on purpose: the agents need none of the saved keys, and reading the
    // standalone app's items makes macOS block the main thread on a prompt.

    let state = AppState.shared
    // First run: agents only, no Stripe, Vercel or GitHub pills beside them.
    // After that the pills chosen in Agents Settings are kept.
    if UserDefaults.standard.data(forKey: "activeIntegrations") == nil {
      state.activeIntegrations = []
    }
    state.loadIntegrationTasks()

    hookExpandObserver = NotificationCenter.default.addObserver(
      forName: .hookExpand, object: nil, queue: .main
    ) { note in
      guard let view = note.object as? IslandView else { return }
      MainActor.assumeIsolated {
        state.view = view
        state.lastActivity = .now
        onExpandRequested?()
      }
    }

    // Non-alert work events only reveal the compact state; presence follows.
    NotificationCenter.default.addObserver(
      forName: .hookReveal, object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { AgentPresence.shared.noteActivity() }
    }

    AgentPresence.shared.start()
    HookServer.shared.start()
  }

  /// One ear of the closed notch: Mochi, or the mini grid of the other agents.
  public static func makeClosedEar(_ ear: ClosedEar, height: CGFloat) -> some View {
    ClosedEarView(ear: ear, height: height)
  }

  private static var settingsWindow: NSWindow?

  /// Coucou's own settings: which agents and pills show, and the hook
  /// installers for Claude Code, Codex, Gemini CLI, Cursor and the rest.
  public static func showSettings() {
    if let window = settingsWindow, window.isVisible {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false
    )
    window.title = "Agents Settings"
    let host = NSHostingView(rootView: SettingsView())
    host.sizingOptions = [.minSize]
    window.contentView = host
    window.contentMinSize = NSSize(width: 640, height: 420)
    window.isReleasedWhenClosed = false
    window.center()
    settingsWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Coucou's agent cards and Mochi, for the Agents tab.
  public static func makeAgentsView() -> some View {
    AgentsTabView()
  }
}

/// Which ear of the closed notch.
public enum ClosedEar {
  /// Mochi, the agent in focus.
  case leading
  /// The other agents as a grid of little Mochis; Mochi himself when music
  /// holds the other ear.
  case trailing
  case focusedMochi
}

/// Whether an agent is around, for the closed notch: working, waiting on an
/// answer, or active a moment ago.
@MainActor
public final class AgentPresence: ObservableObject {
  public static let shared = AgentPresence()

  /// An agent is working, waiting for you, or was a minute ago or less.
  @Published public private(set) var isActive = false
  /// A permission request or a question is waiting for an answer.
  @Published public private(set) var isHoldingForAnswer = false

  /// How long the closed notch keeps showing agents after the last sign of life.
  private static let lingerSeconds: TimeInterval = 60

  private var lastActivityAt = Date.distantPast
  private var cancellables = Set<AnyCancellable>()
  private var timer: Timer?

  func start() {
    let state = AppState.shared
    state.$tasks
      .combineLatest(state.$pendingApproval, state.$pendingQuestion)
      .sink { [weak self] _, _, _ in
        DispatchQueue.main.async { self?.recompute() }
      }
      .store(in: &cancellables)
    timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.recompute() }
    }
    recompute()
  }

  func noteActivity() {
    lastActivityAt = .now
    recompute()
  }

  private func recompute() {
    let state = AppState.shared
    let holding = state.pendingApproval != nil || state.pendingQuestion != nil
    let busy = state.tasks.contains { $0.state != .idle && $0.state != .sleeping }
    if holding || busy { lastActivityAt = .now }
    let active = holding || busy || Date.now.timeIntervalSince(lastActivityAt) < Self.lingerSeconds
    if holding != isHoldingForAnswer { isHoldingForAnswer = holding }
    if active != isActive { isActive = active }
  }
}

private struct ClosedEarView: View {
  let ear: ClosedEar
  let height: CGFloat
  @ObservedObject private var state = AppState.shared

  var body: some View {
    switch ear {
    case .leading, .focusedMochi:
      // Coucou's compact Mochi: 20 points across, drawn on a canvas 1/0.6 as big.
      let diameter = min(20, max(0, height - 6))
      BotCanvasView(state: state, particleOverhang: 0, paused: state.mochiOnDesktop)
        .frame(width: diameter / 0.6, height: diameter / 0.6)
        .frame(width: height, height: height)
        .opacity(state.mochiOnDesktop ? 0 : 1)
    case .trailing:
      CompactMiniGrid(state: state)
        .scaleEffect(min(1, max(0, height - 4) / 28))
        .frame(width: height, height: height)
    }
  }
}
