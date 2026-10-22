import SwiftUI

/// One agent's usage, in place of the cards: its two windows with their reset times and
/// the last seven days' trend. Opened from the dots on a pill or beside the big Mochi.
struct AgentUsageView: View {
  @ObservedObject var state: AppState
  let pillID: String
  let pillName: String
  let onBack: () -> Void

  @State private var now = Date()

  private var agent: UsageAgent? { UsageAgent.forPill(pillID) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Circle().fill(Color(hex: agent?.colorHex ?? "#6B7079")).frame(width: 7, height: 7)
        Text("\(agent?.title ?? pillName) usage")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(Color(hex: "#F5F6F8"))
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundColor(Color(hex: "#8E939C"))
        Spacer()
        Button(action: onBack) {
          HStack(spacing: 3) {
            Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
            Text("Back").font(.system(size: 11, weight: .medium))
          }
          .foregroundColor(Color(hex: "#C5C8CD"))
          .padding(.horizontal, 9)
          .padding(.vertical, 3)
          .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
      }
      .padding(.top, 8)

      if let agent, let usage = agent.usage {
        HStack(alignment: .center, spacing: 18) {
          VStack(alignment: .leading, spacing: 9) {
            UsageBarRow(label: "5 hours", window: usage.fiveHour, now: now, weekly: false)
            UsageBarRow(label: "Week", window: usage.sevenDay, now: now, weekly: true)
          }
          Spacer(minLength: 0)
          VStack(alignment: .trailing, spacing: 3) {
            Sparkline(values: UsageHistory.lastWeek(agent), tint: Color(hex: agent.colorHex))
              .frame(width: 96, height: 34)
            Text("Last 7 days")
              .font(.system(size: 9))
              .foregroundColor(Color(hex: "#6B7079"))
          }
        }
        .padding(.top, 10)
      } else {
        Text(emptyMessage)
          .font(.system(size: 12))
          .foregroundColor(Color(hex: "#8E939C"))
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 14)
        Spacer(minLength: 0)
      }
    }
    .padding(.leading, 116)
    .padding(.trailing, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      TimelineView(.periodic(from: .now, by: 30)) { ctx in
        Color.clear.onChange(of: ctx.date) { _, d in now = d }
      }
    )
    .onAppear { if agent == .codex { state.refreshCodexPlanUsage() } }
  }

  private var subtitle: String {
    guard let usage = agent?.usage else { return "" }
    let diff = now.timeIntervalSince(usage.updatedAt)
    if diff < 60 { return "just now" }
    let mins = Int(diff / 60)
    return mins < 60 ? "\(mins) min ago" : "\(mins / 60) h ago"
  }

  private var emptyMessage: String {
    switch agent {
    case .claude:
      return "Waiting for Claude Code's status line. Switch the plan relay on in Agents Settings; the numbers arrive while Claude Code runs."
    case .codex:
      return "No Codex reading yet. It is fetched when Codex is installed and signed in."
    case nil:
      return "\(pillName) does not report how much of its plan is used."
    }
  }
}

private let weeklyResetFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "EEE H:mm"
  return f
}()

private struct UsageBarRow: View {
  let label: String
  let window: PlanWindow?
  let now: Date
  let weekly: Bool

  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.system(size: 11))
        .foregroundColor(Color(hex: "#6B7079"))
        .frame(width: 44, alignment: .leading)
      if let window {
        let pct = ClaudePlanGauge.effectivePct(window)
        let accent = Color(hex: ClaudePlanGauge.color(for: pct))
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.08)).frame(width: 130, height: 6)
          Capsule().fill(accent).frame(width: max(6, 130 * CGFloat(pct / 100)), height: 6)
        }
        Text("\(Int(pct.rounded()))%")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(Color(hex: "#E5E7EB"))
          .monospacedDigit()
          .frame(width: 38, alignment: .trailing)
        Text(resetText(window))
          .font(.system(size: 10))
          .foregroundColor(Color(hex: "#6B7079"))
          .fixedSize()
      } else {
        Text("—").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
      }
    }
  }

  private func resetText(_ w: PlanWindow) -> String {
    let secs = w.resetsAt.timeIntervalSince(now)
    guard secs > 0 else { return "resetting" }
    if weekly { return "resets \(weeklyResetFormatter.string(from: w.resetsAt))" }
    let h = Int(secs / 3600), m = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
    return h > 0 ? "resets in \(h) h \(m) min" : "resets in \(m) min"
  }
}

/// The last seven days' busiest percentage as a smooth line over a faint fill.
private struct Sparkline: View {
  let values: [Double?]
  let tint: Color

  var body: some View {
    GeometryReader { geo in
      let points = pointList(in: geo.size)
      ZStack {
        if points.count > 1 {
          Path { p in
            p.move(to: CGPoint(x: points[0].x, y: geo.size.height))
            points.forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
            p.closeSubpath()
          }
          .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
          Path { p in
            p.move(to: points[0])
            points.dropFirst().forEach { p.addLine(to: $0) }
          }
          .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        } else if let only = points.first {
          Circle().fill(tint).frame(width: 5, height: 5).position(only)
        } else {
          Text("starting today")
            .font(.system(size: 9))
            .foregroundColor(Color(hex: "#6B7079"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
  }

  private func pointList(in size: CGSize) -> [CGPoint] {
    let step = size.width / CGFloat(max(1, values.count - 1))
    return values.enumerated().compactMap { index, value in
      guard let value else { return nil }
      return CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(min(100, value)) / 100))
    }
  }
}
