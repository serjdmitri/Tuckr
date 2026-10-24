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
            if feed.expanded && feed.popups.count > 1 {
                expandedList
                    .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
            } else {
                // Oldest first, so the newest is drawn last, on top. Two peek out from behind it.
                ForEach(Array(feed.popups.prefix(3).enumerated()).reversed(), id: \.element.id) { depth, item in
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
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.74), value: feed.popups.map(\.id))
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: feed.expanded)
    }

    /// The stack opened out: every message in it, newest first, each one clickable.
    private var expandedList: some View {
        VStack(spacing: 0) {
            ForEach(feed.popups) { item in
                if feed.replyingID == item.id {
                    ReplyField(item: item).padding(.horizontal, 18).padding(.vertical, 7)
                } else {
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ItemIcon(item: item, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hideText ? "New message" : (item.title.isEmpty ? item.appName : item.title))
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                            let line = [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !hideText, !line.isEmpty {
                                Text(line).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { feed.open(item) }
                    VoiceButton(item: item, size: 30)
                    ReplyButton(item: item, size: 30)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                }
                if item.id != feed.popups.last?.id {
                    Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, 18)
                }
            }
        }
        .padding(.top, notchHeight + 2)
        .padding(.bottom, 8)
        .frame(width: width)
        .background(shape.fill(.black))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
    }

    /// What the cards behind are as tall as: the newest card's content plus its padding.
    private var cardHeight: CGFloat { notchHeight + 2 + 44 + 14 + 8 }

    @ViewBuilder
    private func card(_ item: NotificationItem) -> some View {
        if feed.replyingID == item.id {
            ReplyField(item: item)
                .padding(.horizontal, 22)
                .padding(.top, notchHeight + 2)
                .padding(.bottom, 14)
                .frame(width: width)
                .background(shape.fill(.black))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
        } else {
            messageCard(item)
        }
    }

    private func messageCard(_ item: NotificationItem) -> some View {
        HStack(spacing: 14) {
            // A click on the message opens its app; the play button, beside it, only plays.
            HStack(spacing: 14) {
                ItemIcon(item: item, size: 44)
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
                // A stack opens out; a single message opens its chat.
                if feed.popups.count > 1 { feed.expand() } else { feed.open(item) }
            }
            VoiceButton(item: item)
            ReplyButton(item: item)
        }
        .padding(.horizontal, 22)
        .padding(.top, notchHeight + 2)
        .padding(.bottom, 14)
        .frame(width: width)
        .background(shape.fill(.black))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
    }
}
