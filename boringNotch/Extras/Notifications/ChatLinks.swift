//
//  ChatLinks.swift
//  Opening a message in its own chat. A notification does not say which chat it came from, but
//  WhatsApp and Messages keep every message in a database (read-only here, with Full Disk
//  Access): the message that arrived at that moment, with that text, shows which chat it is
//  in, and each app can open a chat from a link. Anything else just opens the app.
//

import Foundation
import SQLite3

enum ChatLocator {
    /// A link that opens the chat (and, for Messages, the message) this notification came from.
    static func url(for item: NotificationItem) async -> URL? {
        await Task.detached(priority: .userInitiated) { () -> URL? in
            switch item.appID {
            case "net.whatsapp.whatsapp": return whatsApp(item)
            case "com.apple.mobilesms": return messages(item)
            default: return nil
            }
        }.value
    }

    // MARK: WhatsApp

    private static func whatsApp(_ item: NotificationItem) -> URL? {
        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite")
        let at = item.date.timeIntervalSinceReferenceDate
        let rows = query(db, """
            SELECT s.ZCONTACTJID, m.ZTEXT, s.ZPARTNERNAME FROM ZWAMESSAGE m
            JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
            WHERE m.ZISFROMME = 0 AND m.ZMESSAGEDATE BETWEEN ? AND ?
            ORDER BY ABS(m.ZMESSAGEDATE - ?) LIMIT 8
            """, binds: [at - 120, at + 120, at])
        guard let jid = best(rows, jidColumn: 0, textColumn: 1, nameColumn: 2, item: item) else { return nil }
        // A person's chat opens from their number; a group has no link of its own.
        guard jid.hasSuffix("@s.whatsapp.net"), let number = jid.split(separator: "@").first else { return nil }
        return URL(string: "whatsapp://send?phone=\(number)")
    }

    // MARK: Messages

    private static func messages(_ item: NotificationItem) -> URL? {
        let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db")
        // Messages counts its dates in nanoseconds from the reference date.
        let at = item.date.timeIntervalSinceReferenceDate * 1_000_000_000
        let window = 120.0 * 1_000_000_000
        let rows = query(db, """
            SELECT m.guid, m.text, c.display_name FROM message m
            JOIN chat_message_join cj ON cj.message_id = m.ROWID
            JOIN chat c ON c.ROWID = cj.chat_id
            WHERE m.is_from_me = 0 AND m.date BETWEEN ? AND ?
            ORDER BY ABS(m.date - ?) LIMIT 8
            """, binds: [at - window, at + window, at])
        guard let guid = best(rows, jidColumn: 0, textColumn: 1, nameColumn: 2, item: item),
              let encoded = guid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "sms://open?message-guid=\(encoded)")
    }

    // MARK: Matching

    /// Of the messages near the moment, the one whose chat name, then whose text, fits the
    /// notification; failing that, the closest in time.
    private static func best(_ rows: [[String]], jidColumn: Int, textColumn: Int, nameColumn: Int, item: NotificationItem) -> String? {
        let body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = item.title.lowercased()
        let byText = rows.first { !body.isEmpty && $0[textColumn].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(String(body.prefix(40))) }
        let byName = rows.first { !title.isEmpty && $0[nameColumn].lowercased() == title }
        return (byText ?? byName ?? rows.first)?[jidColumn]
    }

    // MARK: SQLite

    private static func query(_ database: URL, _ sql: String, binds: [Double]) -> [[String]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 300)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        for (i, value) in binds.enumerated() { sqlite3_bind_double(statement, Int32(i + 1), value) }
        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            })
        }
        return rows
    }
}
