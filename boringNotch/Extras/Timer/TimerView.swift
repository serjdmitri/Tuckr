//
//  TimerView.swift
//  boringNotch
//
//  The timer's page in the open notch: an orange dial to set the minutes, a Start Timer
//  button and the time in large figures; while it runs, the time left with Pause and
//  Cancel; when it ends, Restart and Dismiss.
//

import Defaults
import SwiftUI

let timerOrange = Color(red: 1.0, green: 0.62, blue: 0.16)

struct TimerView: View {
    @ObservedObject private var timer = NotchTimer.shared

    var body: some View {
        VStack(spacing: 8) {
            switch timer.phase {
            case .idle:
                TimerRuler(minutes: $timer.minutes)
                    .frame(height: 56)
                HStack {
                    TimerButton(title: "Start Timer", filled: true) { timer.start() }
                    Spacer()
                    bigTime(timer.minutes * 60)
                }
            case .running, .paused:
                ProgressBar(fraction: timer.progress)
                    .frame(height: 5)
                    .padding(.top, 14)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if timer.phase == .running {
                        TimerButton(title: "Pause", filled: true) { timer.pause() }
                    } else {
                        TimerButton(title: "Resume", filled: true) { timer.resume() }
                    }
                    TimerButton(title: "Cancel", filled: false) { timer.cancel() }
                    Spacer()
                    bigTime(timer.secondsLeft)
                        .opacity(timer.phase == .paused ? 0.55 : 1)
                }
            case .finished:
                Spacer(minLength: 0)
                Text("Time's up")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(timerOrange)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    TimerButton(title: "Restart", filled: true) { timer.start() }
                    TimerButton(title: "Dismiss", filled: false) { timer.dismiss() }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.25), value: timer.phase)
    }

    private func bigTime(_ seconds: Int) -> some View {
        Text(timerText(seconds))
            .font(.system(size: 40, weight: .regular, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(timerOrange)
            .contentTransition(.numericText())
    }
}

private struct TimerButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(filled ? timerOrange : Color.white.opacity(0.75))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(filled ? timerOrange.opacity(0.22) : Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(timerOrange)
                    .frame(width: max(5, geo.size.width * fraction))
            }
        }
    }
}

/// The dial: ticks every minute, a numbered tick every five, the chosen minute under the
/// marker. Drag sideways to change it.
private struct TimerRuler: View {
    @Binding var minutes: Int
    @State private var dragStart: Int?

    private let spacing: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let mid = size.width / 2
            let visible = Int(size.width / spacing / 2) + 2
            for offset in -visible...visible {
                let minute = minutes + offset
                guard NotchTimer.minuteRange.contains(minute) else { continue }
                let x = mid + CGFloat(offset) * spacing
                let major = minute % 5 == 0
                let distance = abs(CGFloat(offset) * spacing) / (size.width / 2)
                let height: CGFloat = major ? 22 : 14
                let color = offset == 0
                    ? Color(red: 1, green: 0.95, blue: 0.8)
                    : timerOrange.opacity(max(0.15, 1 - distance * 1.1))
                let top: CGFloat = 22
                context.fill(
                    Path(roundedRect: CGRect(x: x - 1, y: top, width: 2, height: height), cornerRadius: 1),
                    with: .color(color))
                if major {
                    let label = Text("\(minute)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                    context.draw(label, at: CGPoint(x: x, y: 11))
                }
            }
            var marker = Path()
            marker.move(to: CGPoint(x: mid, y: size.height - 10))
            marker.addLine(to: CGPoint(x: mid - 7, y: size.height))
            marker.addLine(to: CGPoint(x: mid + 7, y: size.height))
            marker.closeSubpath()
            context.fill(marker, with: .color(timerOrange))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStart ?? minutes
                    dragStart = start
                    let moved = Int((-value.translation.width / spacing).rounded())
                    let next = min(NotchTimer.minuteRange.upperBound, max(NotchTimer.minuteRange.lowerBound, start + moved))
                    if next != minutes {
                        minutes = next
                        if Defaults[.enableHaptics] {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                    }
                }
                .onEnded { _ in dragStart = nil }
        )
    }
}
