import AppKit

// MARK: - ClaudeHost
//
// The app a Claude Code session runs in, from the hook payload's term_program /
// bundle_id. VS Code sessions keep the original "VS Code" pill; sessions from a
// terminal also route to integration_claude and the pill says "Claude Code".

struct ClaudeHost: Equatable {
    let bundleId: String
    let name: String

    /// UserDefaults key: show terminal sessions' questions and permission requests in the
    /// notch (they then wait for the notch). Off by default: the terminal asks itself.
    static let terminalCardsKey = "terminalCardsEnabled"
    static var terminalCardsEnabled: Bool { UserDefaults.standard.bool(forKey: terminalCardsKey) }

    /// Terminals (and agent apps like Conductor) accepted for Claude Code sessions.
    /// Keyed by bundle id; the second
    /// table maps TERM_PROGRAM for hooks that run without __CFBundleIdentifier.
    private static let terminals: [String: String] = [
        "dev.warp.Warp-Stable":       "Warp",
        "dev.warp.Warp-Preview":      "Warp",
        "com.apple.Terminal":         "Terminal",
        "com.googlecode.iterm2":      "iTerm",
        "com.mitchellh.ghostty":      "Ghostty",
        "net.kovidgoyal.kitty":       "kitty",
        "org.alacritty":              "Alacritty",
        "com.github.wez.wezterm":     "WezTerm",
        "co.zeit.hyper":              "Hyper",
        "dev.zed.Zed":                "Zed",
        "com.cmuxterm.app":           "cmux",    // sets TERM_PROGRAM=ghostty: the bundle id decides
        "com.stablyai.orca":          "Orca",
        "com.conductor.app":          "Conductor", // runs Claude Code with no TERM_PROGRAM
    ]
    private static let termPrograms: [String: String] = [
        "warpterminal":   "dev.warp.Warp-Stable",
        "apple_terminal": "com.apple.Terminal",
        "iterm.app":      "com.googlecode.iterm2",
        "ghostty":        "com.mitchellh.ghostty",
        "kitty":          "net.kovidgoyal.kitty",
        "alacritty":      "org.alacritty",
        "wezterm":        "com.github.wez.wezterm",
        "hyper":          "co.zeit.hyper",
        "zed":            "dev.zed.Zed",
    ]

    /// JetBrains IDEs (IntelliJ IDEA, PyCharm, WebStorm…) and Android Studio: their built-in terminal
    /// runs the session and inherits the IDE's bundle id; it sets no TERM_PROGRAM. Tuckr addition
    /// (Coucou #605): the name for the bundle id, or nil when it is not one of them.
    private static func jetBrainsName(_ id: String) -> String? {
        let lower = id.lowercased()
        guard lower.hasPrefix("com.jetbrains.") || lower == "com.google.android.studio" else { return nil }
        let names: [(String, String)] = [
            ("intellij", "IntelliJ IDEA"), ("pycharm", "PyCharm"), ("webstorm", "WebStorm"), ("phpstorm", "PhpStorm"),
            ("goland", "GoLand"), ("rubymine", "RubyMine"), ("clion", "CLion"), ("rider", "Rider"),
            ("datagrip", "DataGrip"), ("rustrover", "RustRover"), ("appcode", "AppCode"), ("fleet", "Fleet"),
            ("android.studio", "Android Studio"),
        ]
        return names.first { lower.contains($0.0) }?.1 ?? "JetBrains IDE"
    }

    /// The display name of a known host (terminal, agent app or JetBrains IDE).
    private static func knownName(_ id: String) -> String? { terminals[id] ?? jetBrainsName(id) }

    /// The terminal a session runs in, or nil when it isn't a known terminal.
    static func terminal(termProgram: String, bundleId: String) -> ClaudeHost? {
        if let name = knownName(bundleId) { return ClaudeHost(bundleId: bundleId, name: name) }
        if let id = termPrograms[termProgram.lowercased()], let name = terminals[id] {
            return ClaudeHost(bundleId: id, name: name)
        }
        return nil
    }

    /// The app name for a task's host; nil host means VS Code (the original routing).
    static func name(for hostBundleId: String?) -> String {
        guard let id = hostBundleId, let name = knownName(id) else { return "VS Code" }
        return name
    }

    /// Pill label for integration_claude: "VS Code" for editor sessions, "Claude Code" otherwise.
    static func pillName(hostApp: String?) -> String {
        hostApp == nil ? "VS Code" : "Claude Code"
    }

    /// Brings the session's terminal forward (launching it if needed). false when not a terminal host.
    @discardableResult
    static func activate(_ hostBundleId: String?) -> Bool {
        guard let id = hostBundleId, knownName(id) != nil else { return false }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        }
        return true
    }
}
