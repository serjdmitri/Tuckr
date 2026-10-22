import AppKit
import Combine
import SwiftUI

/// An agent whose plan usage Coucou can read: Claude Code (through the status-line relay)
/// and Codex (through `codex app-server`). The others report nothing.
enum UsageAgent: String, CaseIterable, Identifiable {
  case claude, codex

  var id: String { rawValue }
  var title: String { self == .claude ? "Claude" : "Codex" }
  var colorHex: String { self == .claude ? "#E07950" : "#10A37F" }

  /// The agent behind a pill, nil when it has no usage source.
  static func forPill(_ pillID: String?) -> UsageAgent? {
    switch pillID {
    case "integration_claude": return .claude
    case "agent_codex": return .codex
    default: return nil
    }
  }

  @MainActor var usage: PlanUsage? {
    switch self {
    case .claude: return AppState.shared.claudePlanUsage
    case .codex: return AppState.shared.codexPlanUsage?.planUsage
    }
  }
}

/// A usage level crossed: what the host shows as a popup.
public struct UsageAlert: Sendable {
  public let agent: String
  public let colorHex: String
  public let window: String
  public let percent: Int
  public let level: Int
  public let resetsAt: Date
}

/// Which levels alert, per agent (a comma-separated list of percentages), and whether it does.
@MainActor
final class UsageAlertSettings: ObservableObject {
  static let shared = UsageAlertSettings()
  static let defaultLevels = [50, 75, 90]

  func enabled(_ agent: UsageAgent) -> Bool {
    UserDefaults.standard.object(forKey: "usageAlert.\(agent.rawValue).enabled") as? Bool ?? true
  }

  func setEnabled(_ agent: UsageAgent, _ on: Bool) {
    objectWillChange.send()
    UserDefaults.standard.set(on, forKey: "usageAlert.\(agent.rawValue).enabled")
  }

  func levels(_ agent: UsageAgent) -> [Int] {
    guard let raw = UserDefaults.standard.string(forKey: "usageAlert.\(agent.rawValue).levels") else {
      return Self.defaultLevels
    }
    return Self.parse(raw)
  }

  func setLevels(_ agent: UsageAgent, text: String) {
    objectWillChange.send()
    UserDefaults.standard.set(text, forKey: "usageAlert.\(agent.rawValue).levels")
  }

  func levelsText(_ agent: UsageAgent) -> String {
    UserDefaults.standard.string(forKey: "usageAlert.\(agent.rawValue).levels")
      ?? Self.defaultLevels.map(String.init).joined(separator: ", ")
  }

  static func parse(_ text: String) -> [Int] {
    let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    return Array(Set(numbers.filter { (1...100).contains($0) })).sorted()
  }
}

/// A small record of each agent's busiest percentage per day, for the usage page's trend.
@MainActor
enum UsageHistory {
  private static let key = "usageHistory"
  private static let keepDays = 14

  private static var formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  static func record(_ agent: UsageAgent, percent: Double) {
    var all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
    var days = all[agent.rawValue] ?? [:]
    let today = formatter.string(from: Date())
    if percent > (days[today] ?? -1) { days[today] = percent }
    // Forget old days.
    let cutoff = formatter.string(from: Date().addingTimeInterval(-Double(keepDays) * 86400))
    days = days.filter { $0.key >= cutoff }
    all[agent.rawValue] = days
    UserDefaults.standard.set(all, forKey: key)
  }

  /// The last seven days, oldest first; nil where nothing was recorded.
  static func lastWeek(_ agent: UsageAgent) -> [Double?] {
    let all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
    let days = all[agent.rawValue] ?? [:]
    return (0..<7).reversed().map { offset in
      days[formatter.string(from: Date().addingTimeInterval(-Double(offset) * 86400))]
    }
  }
}

/// Watches the readings and tells the host when one crosses a level for the first time in
/// its window.
@MainActor
final class UsageAlertEngine {
  static let shared = UsageAlertEngine()

  private var cancellables = Set<AnyCancellable>()
  private var codexTimer: Timer?
  private var chime: NSSound?
  private static let firedKey = "usageAlertsFired"

  func start() {
    let state = AppState.shared
    state.$claudePlanUsage
      .compactMap { $0 }
      .sink { [weak self] in self?.check(.claude, $0) }
      .store(in: &cancellables)
    state.$codexPlanUsage
      .compactMap { $0?.planUsage }
      .sink { [weak self] in self?.check(.codex, $0) }
      .store(in: &cancellables)
    // Codex only reports when asked: every ten minutes while its alerts are on (Coucou
    // itself spaces these requests out to one a minute).
    let timer = Timer(timeInterval: 600, repeats: true) { _ in
      MainActor.assumeIsolated {
        if UsageAlertSettings.shared.enabled(.codex) { AppState.shared.refreshCodexPlanUsage() }
      }
    }
    timer.tolerance = 60
    RunLoop.main.add(timer, forMode: .common)
    codexTimer = timer
  }

  private func check(_ agent: UsageAgent, _ usage: PlanUsage) {
    if let pct = ClaudePlanGauge.dominantPct(usage) { UsageHistory.record(agent, percent: pct) }
    guard UsageAlertSettings.shared.enabled(agent) else { return }
    let levels = UsageAlertSettings.shared.levels(agent)
    for (name, window) in [("5-hour", usage.fiveHour), ("weekly", usage.sevenDay)] {
      guard let window, window.resetsAt > Date() else { continue }
      let pct = ClaudePlanGauge.effectivePct(window)
      guard let level = levels.last(where: { Double($0) <= pct }) else { continue }
      // Once per level per window: the record is keyed by the window, and by when it resets.
      let key = "\(agent.rawValue).\(name)"
      let reset = (window.resetsAt.timeIntervalSince1970 / 60).rounded()
      var fired = UserDefaults.standard.dictionary(forKey: Self.firedKey) as? [String: [Double]] ?? [:]
      let previous = fired[key]
      if let previous, previous[0] == reset, Int(previous[1]) >= level { continue }
      fired[key] = [reset, Double(level)]
      UserDefaults.standard.set(fired, forKey: Self.firedKey)
      notify(
        UsageAlert(
          agent: agent.title, colorHex: agent.colorHex, window: name, percent: Int(pct.rounded()),
          level: level, resetsAt: window.resetsAt))
    }
  }

  private func notify(_ alert: UsageAlert) {
    let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Ping.aiff", byReference: true)
    chime = sound
    sound?.play()
    CoucouHost.onUsageAlert?(alert)
  }
}
