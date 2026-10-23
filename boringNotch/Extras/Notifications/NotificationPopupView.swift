//
//  NotificationPopupView.swift
//  boringNotch
//
//  A new message: the closed notch drops down with the app's icon, who it is from and what
//  it says. A click opens the app.
//

import Defaults
import SwiftUI

struct NotificationPopupView: View {
    @ObservedObject private var feed = NotificationFeed.shared
    @Default(.notificationHideText) private var hideText
    let chinWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if let item = feed.popup {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: NotificationFeed.icon(for: item.appID))
                        .resizable()
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hideText ? item.appName : (item.title.isEmpty ? item.appName : item.title))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        let line = hideText ? "New message" : [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !line.isEmpty {
                            Text(line)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, notchHeight + 4)
                .padding(.bottom, 14)
                .frame(width: max(chinWidth, 400), alignment: .leading)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26).fill(.black))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationFeed.open(item.appID)
                    feed.dismissPopup()
                }
                .transition(.scale(scale: 0.55, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.74), value: feed.popup?.id)
    }
}
