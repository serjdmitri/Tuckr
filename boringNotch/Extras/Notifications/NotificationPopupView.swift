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
                // Laid out like the Bluetooth popup: the app's own icon, who it is from, what it says.
                HStack(spacing: 14) {
                    Image(nsImage: NotificationFeed.icon(for: item.appID))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.appName)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
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
                .padding(.horizontal, 22)
                .padding(.top, notchHeight + 2)
                .padding(.bottom, 14)
                .frame(width: max(chinWidth, 380))
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26)
                        .fill(.black)
                )
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
