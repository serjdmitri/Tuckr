//
//  QuickReply.swift
//  Replying to a message from the notch. Only Messages can be driven from outside (AppleScript);
//  the other chat apps only open. Nothing is ever sent unless the person types a reply and
//  presses Return or Send.
//

import AppKit
import SQLite3
import SwiftUI

enum MessageSender {
    private static let queue = DispatchQueue(label: "notch.message-sender")

    /// Sends `text` to a Messages chat by its id (e.g. "iMessage;-;+15551234567").
    static func send(_ text: String, toChat chat: String) async -> Bool {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = "tell application \"Messages\" to send \(quoted(text)) to chat id \(quoted(chat))"
        return await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil)
            }
        }
    }
}

/// Sends a reply to the chat a message came from. Messages is driven by AppleScript. WhatsApp
/// has no way to be told to send, but it can open a chat with the text already written: this
/// opens that, presses Return in WhatsApp, and checks in WhatsApp's own database that the
/// message went. If it did not, the draft is left in WhatsApp for the person to send.
enum Replier {
    @MainActor static func send(_ text: String, to item: NotificationItem) async {
        switch item.appID {
        case "com.apple.mobilesms":
            var guid = item.chatGUID
            if guid == nil { guid = await ChatLocator.chatGUID(for: item) }
            guard let guid else { NotificationFeed.shared.toast("Couldn't find that chat", item: item); return }
            let sent = await MessageSender.send(text, toChat: guid)
            NotificationFeed.shared.toast(sent ? "Sent to \(item.title)" : "Couldn't send: allow Tuckr to control Messages", item: item)
        case "net.whatsapp.whatsapp":
            await sendWhatsApp(text, item)
        default:
            break
        }
    }

    @MainActor private static func sendWhatsApp(_ text: String, _ item: NotificationItem) async {
        var link = item.openURL
        if link == nil { link = await ChatLocator.url(for: item) }
        guard let link, link.host == "send",
              let phone = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "phone" })?.value,
              var components = URLComponents(string: "whatsapp://send"),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.appID)
        else {
            NotificationFeed.shared.toast("WhatsApp groups can't be replied to from here", item: item)
            return
        }
        components.queryItems = [URLQueryItem(name: "phone", value: phone), URLQueryItem(name: "text", value: text)]
        guard let url = components.url else { return }
        let before = NSWorkspace.shared.frontmostApplication
        let started = Date().timeIntervalSinceReferenceDate
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        // Let WhatsApp open the chat and write the draft, then send it.
        try? await Task.sleep(for: .seconds(1.2))
        if let pid = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == app })?.processIdentifier {
            for down in [true, false] {
                CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: down)?.postToPid(pid)
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        // Did it go? WhatsApp saves what you send the moment it does.
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(500))
            if await Task.detached(operation: { WhatsAppOutbox.contains(text, since: started - 2) }).value {
                before?.activate()
                NotificationFeed.shared.toast("Sent to \(item.title)", item: item)
                return
            }
        }
        NotificationFeed.shared.toast("Draft is in WhatsApp: press Return to send", item: item)
    }
}

/// Whether WhatsApp has a sent message with this text since a moment (its own database, read-only).
enum WhatsAppOutbox {
    static func contains(_ text: String, since: Double) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite")
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return false }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM ZWAMESSAGE WHERE ZISFROMME = 1 AND ZTEXT = ? AND ZMESSAGEDATE > ? LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(statement, 2, since)
        return sqlite3_step(statement) == SQLITE_ROW
    }
}

/// The small reply button on a message card (Messages and WhatsApp).
struct ReplyButton: View {
    let item: NotificationItem
    var size: CGFloat = 34
    @ObservedObject private var feed = NotificationFeed.shared

    var body: some View {
        if item.appID == "com.apple.mobilesms" || item.appID == "net.whatsapp.whatsapp" {
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
