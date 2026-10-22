import AppKit
import SwiftUI

/// The host-facing door into Coucou. Everything else in this module is
/// Coucou's own code, copied unchanged from the upstream commit recorded in
/// UPSTREAM.md; this file and AgentsTabView.swift are the only additions.
@MainActor
public enum CoucouHost {
  public nonisolated static let isLinked = true

  private static var started = false
  private static var hookExpandObserver: NSObjectProtocol?

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

    HookServer.shared.start()
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
