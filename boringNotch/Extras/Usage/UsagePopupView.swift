//
//  UsagePopupView.swift
//  boringNotch
//
//  The usage alert: the closed notch drops down with the agent, which window passed which
//  level, when it resets, and a ring with the percentage.
//

import CoucouCore
import SwiftUI

@MainActor
final class UsagePopup: ObservableObject {
    static let shared = UsagePopup()

    struct Info: Equatable {
        let id = UUID()
        let alert: UsageAlertBox
    }

    @Published private(set) var info: Info?
    private var hideTask: Task<Void, Never>?

    func present(_ alert: UsageAlert) {
        info = Info(alert: UsageAlertBox(alert))
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.info = nil
        }
    }

    func dismiss() {
        hideTask?.cancel()
        info = nil
    }
}

/// `UsageAlert` made equatable for the popup state.
struct UsageAlertBox: Equatable {
    let agent: String
    let colorHex: String
    let window: String
    let percent: Int
    let level: Int
    let resetsAt: Date

    init(_ alert: UsageAlert) {
        agent = alert.agent
        colorHex = alert.colorHex
        window = alert.window
        percent = alert.percent
        level = alert.level
        resetsAt = alert.resetsAt
    }
}

struct UsagePopupView: View {
    @ObservedObject private var popup = UsagePopup.shared
    let chinWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if let info = popup.info {
                let alert = info.alert
                let width = max(chinWidth, 360)
                let tint = Color(usageHex: levelColor(alert.percent))
                HStack(spacing: 14) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 28))
                        .foregroundStyle(Color(usageHex: alert.colorHex))
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(alert.agent) · \(alert.window) limit")
                            .font(.system(size: 13))
                            .foregroundStyle(.gray)
                        Text("\(alert.percent)% used")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text(resetText(alert.resetsAt))
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                    }
                    Spacer(minLength: 8)
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.14), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(alert.percent) / 100)
                            .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(alert.percent)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 46, height: 46)
                }
                .padding(.horizontal, 22)
                .padding(.top, notchHeight + 2)
                .padding(.bottom, 14)
                .frame(width: width)
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26).fill(.black)
                )
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                .transition(.scale(scale: 0.55, anchor: .top).combined(with: .opacity))
                .onTapGesture { popup.dismiss() }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.74), value: popup.info?.id)
    }

    private func levelColor(_ percent: Int) -> String {
        percent < 50 ? "#22C55E" : (percent < 80 ? "#F59E0B" : "#F4505E")
    }

    private func resetText(_ date: Date) -> String {
        let secs = date.timeIntervalSinceNow
        guard secs > 0 else { return "resetting" }
        let h = Int(secs / 3600), m = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
        if h >= 24 { return "resets in \(h / 24) d \(h % 24) h" }
        return h > 0 ? "resets in \(h) h \(m) min" : "resets in \(m) min"
    }
}

private extension Color {
    /// "#RRGGBB".
    init(usageHex hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0x888888
        self.init(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
