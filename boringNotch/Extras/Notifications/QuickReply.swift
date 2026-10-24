//
//  QuickReply.swift
//  Replying to a message from the notch. Only Messages can be driven from outside (AppleScript);
//  the other chat apps only open. Nothing is ever sent unless the person types a reply and
//  presses Return or Send.
//

import AppKit
import SwiftUI

enum MessageSender {
    private static let queue = DispatchQueue(label: "notch.message-sender")

    /// Sends `text` to a Messages chat by its id (e.g. "iMessage;-;+15551234567").
    static func send(_ text: String, toChat chat: String) {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = "tell application \"Messages\" to send \(quoted(text)) to chat id \(quoted(chat))"
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}

/// The small reply button on a Messages card.
struct ReplyButton: View {
    let item: NotificationItem
    var size: CGFloat = 34
    @ObservedObject private var feed = NotificationFeed.shared

    var body: some View {
        if item.appID == "com.apple.mobilesms" {
            Button { feed.beginReply(item) } label: {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Reply")
        }
    }
}

/// A card turned into a reply box.
struct ReplyField: View {
    let item: NotificationItem
    @ObservedObject private var feed = NotificationFeed.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NotificationFeed.icon(for: item.appID))
                .resizable().interpolation(.high).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reply to \(item.title.isEmpty ? item.appName : item.title)")
                    .font(.system(size: 12)).foregroundStyle(.gray).lineLimit(1)
                TextField("Write a reply…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { feed.sendReply(text, to: item) }
                    .onChange(of: text) { _, _ in feed.touchReply() }
                    .onExitCommand { feed.endReply() }
            }
            Button { feed.sendReply(text, to: item) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color(red: 0.2, green: 0.82, blue: 0.38))
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            Button { feed.endReply() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true } }
    }
}
