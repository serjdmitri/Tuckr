//
//  TimerClosedViews.swift
//  boringNotch
//
//  The timer's symbol for its bubble beside the closed notch: a stopwatch whose hand
//  moves with the time, one full turn a minute, a tick each second.
//

import SwiftUI

let timerRed = Color(red: 1.0, green: 0.27, blue: 0.23)

struct TimerGlyph: View {
    @ObservedObject private var timer = NotchTimer.shared
    var size: CGFloat = 15

    /// Red for the last minute.
    private var tint: Color {
        timer.isActive && timer.secondsLeft <= 60 ? timerRed : timerOrange
    }

    var body: some View {
        let line = size * 0.12
        ZStack {
            Circle()
                .stroke(tint, lineWidth: line)
                .frame(width: size * 0.84, height: size * 0.84)
                .offset(y: size * 0.06)
            // The crown.
            Capsule()
                .fill(tint)
                .frame(width: size * 0.26, height: line)
                .offset(y: -size * 0.45)
            // The hand: it keeps turning with every second that passes.
            Capsule()
                .fill(tint)
                .frame(width: line * 0.9, height: size * 0.34)
                .offset(y: -size * 0.17)
                .rotationEffect(.degrees(Double(timer.elapsedSeconds) * 6), anchor: .center)
                .offset(y: size * 0.06)
                .animation(.spring(response: 0.28, dampingFraction: 0.62), value: timer.elapsedSeconds)
            Circle()
                .fill(tint)
                .frame(width: line * 1.5, height: line * 1.5)
                .offset(y: size * 0.06)
        }
        .frame(width: size, height: size)
        .opacity(timer.phase == .paused ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.6), value: tint)
    }
}
