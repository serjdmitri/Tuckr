//
//  NotificationsView.swift
//  boringNotch
//
//  The Messages page: the recent notifications from the apps switched on in Settings. A click
//  opens the app.
//

import Defaults
import SwiftUI

struct NotificationsView: View {
    @ObservedObject private var feed = NotificationFeed.shared
    @Default(.notificationHideText) private var hideText
    @Default(.notificationHideFromSharing) private var hideFromSharing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Messages").font(.system(size: 17, weight: .bold))
                if !feed.items.isEmpty {
                    Text("\(feed.items.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                Spacer()
                if !feed.items.isEmpty {
                    Button("Clear") { feed.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if feed.needsAccess {
                notice("Full Disk Access is needed to read notifications.", "Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
            } else if feed.items.isEmpty {
                notice("No messages yet. Choose the apps in Settings → Notifications.", nil) {}
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(feed.items) { item in row(item) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            feed.markRead()
            if hideFromSharing { NotchPrivacy.set("notifications", true) }
        }
        .onDisappear { NotchPrivacy.set("notifications", false) }
    }

    private func row(_ item: NotificationItem) -> some View {
        Button {
            NotificationFeed.open(item.appID)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: NotificationFeed.icon(for: item.appID))
                    .resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(hideText ? item.appName : (item.title.isEmpty ? item.appName : item.title))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text(item.date, style: .relative)
                            .font(.system(size: 10)).foregroundStyle(.gray)
                    }
                    let line = hideText ? "New message" : [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " · ")
                    Text(line)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func notice(_ text: String, _ button: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(text).font(.system(size: 13)).foregroundStyle(.gray).multilineTextAlignment(.center)
            if let button {
                Button(button, action: action).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
