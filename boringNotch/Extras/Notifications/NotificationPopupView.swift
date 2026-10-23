//
//  NotificationPopupView.swift
//  boringNotch
//
//  A new message: the closed notch drops down with the app's icon, who it is from and what
//  it says, laid out like the Bluetooth popup. Messages that arrive close together stack:
//  the newest on top, the older ones peeking out beneath it. A click opens the app.
//

import Defaults
import SwiftUI

struct NotificationPopupView: View {
    @ObservedObject private var feed = NotificationFeed.shared
    @Default(.notificationHideText) private var hideText
    let chinWidth: CGFloat
    let notchHeight: CGFloat

    private var width: CGFloat { max(chinWidth, 380) }
    private let shape = UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26)

    var body: some View {
        ZStack(alignment: .top) {
            // Oldest first, so the newest is drawn last, on top.
            ForEach(Array(feed.popups.enumerated()).reversed(), id: \.element.id) { depth, item in
                if depth == 0 {
                    card(item)
                        .transition(.scale(scale: 0.55, anchor: .top).combined(with: .opacity))
                } else {
                    // Behind the newest: just the edge of a card, a little lower and narrower.
                    shape
                        .fill(Color(white: 0.13))
                        .frame(width: width - CGFloat(depth) * 26, height: cardHeight)
                        .offset(y: CGFloat(depth) * 12)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.74), value: feed.popups.map(\.id))
    }

    /// What the cards behind are as tall as: the newest card's content plus its padding.
    private var cardHeight: CGFloat { notchHeight + 2 + 44 + 14 + 8 }

    private func card(_ item: NotificationItem) -> some View {
        HStack(spacing: 14) {
            // A click on the message opens its app; the play button, beside it, only plays.
            HStack(spacing: 14) {
                Image(nsImage: NotificationFeed.icon(for: item.appID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(item.appName)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                        if feed.popups.count > 1 {
                            Text("+\(feed.popups.count - 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.18)))
                        }
                    }
                    Text(hideText ? "New message" : (item.title.isEmpty ? item.appName : item.title))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    let line = [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !hideText, !line.isEmpty {
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 1)
                    }
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                feed.open(item)
            }
            VoiceButton(item: item)
        }
        .padding(.horizontal, 22)
        .padding(.top, notchHeight + 2)
        .padding(.bottom, 14)
        .frame(width: width)
        .background(shape.fill(.black))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
    }
}
