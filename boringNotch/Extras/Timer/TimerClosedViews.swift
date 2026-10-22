//
//  TimerClosedViews.swift
//  boringNotch
//
//  The running timer on the closed notch: the timer symbol, swinging with each second, in
//  the left ear and the time in the right; or, when music holds the ears, a small round
//  bubble with the symbol hanging under the notch.
//

import SwiftUI

/// The timer symbol, ticking: it swings one way and back every second. Still when paused.
struct TimerGlyph: View {
    @ObservedObject private var timer = NotchTimer.shared
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: timer.phase == .paused ? "pause.fill" : "timer")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(timerOrange)
            .rotationEffect(.degrees(swing), anchor: .center)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: timer.secondsLeft)
    }

    private var swing: Double {
        guard timer.phase == .running else { return 0 }
        return timer.secondsLeft % 2 == 0 ? -14 : 14
    }
}

/// Both ears of the closed notch: the symbol at the left edge, the time at the right.
struct ClosedTimerActivity: View {
    @ObservedObject private var timer = NotchTimer.shared
    let gap: CGFloat
    static let earWidth: CGFloat = 46

    var body: some View {
        HStack {
            TimerGlyph(size: 15)
                .frame(width: Self.earWidth, alignment: .leading)
                .padding(.leading, 4)
            Rectangle().fill(.black).frame(width: gap)
            Text(timerText(timer.secondsLeft))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timerOrange.opacity(timer.phase == .paused ? 0.55 : 1))
                .frame(width: Self.earWidth, alignment: .trailing)
                .padding(.trailing, 4)
        }
    }
}

/// The bubble shown beside the music cover: a black circle under the notch's right side.
struct TimerBubble: View {
    @ObservedObject private var timer = NotchTimer.shared

    var body: some View {
        TimerGlyph(size: 15)
            .frame(width: 30, height: 30)
            .background(Circle().fill(.black))
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            .help(timerText(timer.secondsLeft))
    }
}
