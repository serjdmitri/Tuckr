//
//  InstantMessages.swift
//  WhatsApp and Messages save a message the moment it arrives, a few seconds before macOS's
//  notification list records the notification (and long before it would be shown with the
//  banner turned off). This watches their databases (read-only, with Full Disk Access),
//  notices a new incoming message at once and hands it to the notch. Telegram, Slack and the
//  rest do not keep readable chats, so they still come from the banner and the list.
//

import AppKit
import Defaults
import SQLite3

struct InstantMessage {
    let appID: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    /// A link that opens the chat, when the app has one.
    let openURL: URL?
}

@MainActor
final class InstantMessages {
    static let shared = InstantMessages()

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var whatsAppLast = -1
    private var messagesLast = -1
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var pending: Task<Void, Never>?
    private var poll: Timer?

    private var whatsAppDB: URL {
        home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite")
    }
    private var messagesDB: URL { home.appendingPathComponent("Library/Messages/chat.db") }

    func start() {
        guard watchers.isEmpty else { return }
        for url in [whatsAppDB, URL(fileURLWithPath: whatsAppDB.path + "-wal"), messagesDB, URL(fileURLWithPath: messagesDB.path + "-wal")] {
            let fd = Darwin.open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { InstantMessages.shared.changed() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
        // Catches a swapped-out write-ahead file, and sets the starting point.
        poll = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            MainActor.assumeIsolated { InstantMessages.shared.changed() }
        }
        changed()
    }

    private func changed() {
        guard Defaults[.notificationsEnabled], Defaults[.notificationInstant] else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            let whatsApp = self.whatsAppLast, messages = self.messagesLast
            let found = await Task.detached(priority: .userInitiated) { InstantReader.read(whatsAppAfter: whatsApp, messagesAfter: messages) }.value
            self.whatsAppLast = found.whatsAppLast
            self.messagesLast = found.messagesLast
            // The first look only sets the starting point: what is already there is not news.
            guard whatsApp >= 0 || messages >= 0 else { return }
            for message in found.messages where Date().timeIntervalSince(message.date) < 60 {
                NotificationFeed.shared.instant(message)
            }
        }
    }
}

/// Reads the two chat databases off the main thread.
enum InstantReader {
    struct Found {
        var messages: [InstantMessage] = []
        var whatsAppLast: Int
        var messagesLast: Int
    }

    static func read(whatsAppAfter: Int, messagesAfter: Int) -> Found {
        var found = Found(messages: [], whatsAppLast: whatsAppAfter, messagesLast: messagesAfter)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let whatsApp = home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite")
        let messages = home.appendingPathComponent("Library/Messages/chat.db")
        withDatabase(whatsApp) { db in
            if whatsAppAfter < 0 {
                found.whatsAppLast = Int(scalar(db, "SELECT MAX(Z_PK) FROM ZWAMESSAGE") ?? 0)
                return
            }
            let columns = Set(rows(db, "SELECT name FROM pragma_table_info('ZWACHATSESSION')", []).map { $0[0] })
            let mute = columns.contains("ZMUTEEXPIRATION") ? "s.ZMUTEEXPIRATION" : "0"
            let archived = columns.contains("ZARCHIVED") ? "s.ZARCHIVED" : "0"
            let sql = """
                SELECT m.Z_PK, m.ZMESSAGEDATE, m.ZTEXT, m.ZMESSAGETYPE, m.ZPUSHNAME, s.ZPARTNERNAME, s.ZCONTACTJID, \(mute), \(archived)
                FROM ZWAMESSAGE m LEFT JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
                WHERE m.Z_PK > ? AND m.ZISFROMME = 0 ORDER BY m.Z_PK LIMIT 20
                """
            for row in rows(db, sql, [Double(whatsAppAfter)]) {
                found.whatsAppLast = max(found.whatsAppLast, Int(row[0]) ?? 0)
                let type = Int(row[3]) ?? 0
                let jid = row[6]
                guard let body = whatsAppBody(type: type, text: row[2]) else { continue }
                // A muted or archived chat does not notify.
                if (Double(row[7]) ?? 0) != 0 || (Int(row[8]) ?? 0) == 1 { continue }
                let isGroup = jid.hasSuffix("@g.us")
                let chat = row[5].isEmpty ? row[4] : row[5]
                let number = jid.split(separator: "@").first.map(String.init) ?? ""
                found.messages.append(InstantMessage(
                    appID: "net.whatsapp.whatsapp", appName: "WhatsApp", title: chat.isEmpty ? "WhatsApp" : chat,
                    subtitle: isGroup ? row[4] : "", body: body,
                    date: Date(timeIntervalSinceReferenceDate: Double(row[1]) ?? 0),
                    openURL: !isGroup && jid.hasSuffix("@s.whatsapp.net") ? URL(string: "whatsapp://send?phone=\(number)") : nil))
            }
        }
        withDatabase(messages) { db in
            if messagesAfter < 0 {
                found.messagesLast = Int(scalar(db, "SELECT MAX(ROWID) FROM message") ?? 0)
                return
            }
            let sql = """
                SELECT m.ROWID, m.date, m.text, m.guid, m.is_audio_message, m.cache_has_attachments, h.id, c.display_name, m.attributedBody
                FROM message m
                LEFT JOIN handle h ON h.ROWID = m.handle_id
                LEFT JOIN chat_message_join cj ON cj.message_id = m.ROWID
                LEFT JOIN chat c ON c.ROWID = cj.chat_id
                WHERE m.ROWID > ? AND m.is_from_me = 0 AND m.associated_message_type = 0 ORDER BY m.ROWID LIMIT 20
                """
            for row in rows(db, sql, [Double(messagesAfter)], blobColumn: 8) {
                found.messagesLast = max(found.messagesLast, Int(row[0]) ?? 0)
                var body = row[2]
                if body.isEmpty { body = row[8] }
                if row[4] == "1" { body = "🎤 Audio message" }
                else if body.isEmpty { body = row[5] == "1" ? "📎 Attachment" : "" }
                guard !body.isEmpty else { continue }
                let handle = row[6]
                let name = ContactNames.shared.name(forHandle: handle) ?? handle
                let group = row[7]
                let guid = row[3].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                found.messages.append(InstantMessage(
                    appID: "com.apple.mobilesms", appName: "Messages", title: group.isEmpty ? name : group,
                    subtitle: group.isEmpty ? "" : name, body: body,
                    date: Date(timeIntervalSinceReferenceDate: (Double(row[1]) ?? 0) / 1_000_000_000),
                    openURL: URL(string: "sms://open?message-guid=\(guid)")))
            }
        }
        return found
    }

    /// What a WhatsApp message says in a notification; nil for the ones that never notify.
    private static func whatsAppBody(type: Int, text: String) -> String? {
        switch type {
        case 0, 7: return text.isEmpty ? nil : text
        case 1: return text.isEmpty ? "📷 Photo" : "📷 \(text)"
        case 2: return text.isEmpty ? "🎥 Video" : "🎥 \(text)"
        case 3: return "🎤 Voice message"
        case 4: return "👤 Contact"
        case 5: return "📍 Location"
        case 8: return text.isEmpty ? "📄 Document" : "📄 \(text)"
        default: return nil
        }
    }

    // MARK: SQLite

    private static func withDatabase(_ url: URL, _ body: (OpaquePointer) -> Void) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { sqlite3_close(db); return }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        body(db)
    }

    private static func scalar(_ db: OpaquePointer, _ sql: String) -> Double? {
        rows(db, sql, []).first.flatMap { Double($0[0]) }
    }

    /// Every column as text; a blob column is read as the text inside Messages' typed archive.
    static func rows(_ db: OpaquePointer, _ sql: String, _ binds: [Double], blobColumn: Int32 = -1) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        for (i, value) in binds.enumerated() { sqlite3_bind_double(statement, Int32(i + 1), value) }
        var all: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            all.append((0..<sqlite3_column_count(statement)).map { column in
                if column == blobColumn {
                    guard let bytes = sqlite3_column_blob(statement, column) else { return "" }
                    return attributedText(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column))))
                }
                return sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            })
        }
        return all
    }

    /// Messages keeps newer messages' text only inside a typed archive of an attributed string.
    private static func attributedText(_ data: Data) -> String {
        guard let object = try? NSUnarchiver.unarchiveObject(with: data) as? NSAttributedString else { return "" }
        return object.string
    }
}

/// Names for phone numbers and addresses, from the Contacts database (read-only).
final class ContactNames: @unchecked Sendable {
    static let shared = ContactNames()

    private let lock = NSLock()
    private var byNumber: [String: String] = [:]
    private var byEmail: [String: String] = [:]
    private var loadedAt = Date.distantPast

    func name(forHandle handle: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if Date().timeIntervalSince(loadedAt) > 600 { load() }
        if handle.contains("@") { return byEmail[handle.lowercased()] }
        let digits = handle.filter(\.isNumber)
        return byNumber[String(digits.suffix(10))]
    }

    private func load() {
        loadedAt = Date()
        var numbers: [String: String] = [:], emails: [String: String] = [:]
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AddressBook", isDirectory: true)
        var files = [root.appendingPathComponent("AddressBook-v22.abcddb")]
        let sources = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)) ?? []
        files += sources.map { $0.appendingPathComponent("AddressBook-v22.abcddb") }
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            var db: OpaquePointer?
            guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { sqlite3_close(db); continue }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 250)
            func person(_ row: [String]) -> String {
                let full = [row[0], row[1]].filter { !$0.isEmpty }.joined(separator: " ")
                return full.isEmpty ? row[2] : full
            }
            for row in InstantReader.rows(db, "SELECT r.ZFIRSTNAME, r.ZLASTNAME, r.ZORGANIZATION, p.ZFULLNUMBER FROM ZABCDPHONENUMBER p JOIN ZABCDRECORD r ON r.Z_PK = p.ZOWNER", []) {
                let key = String(row[3].filter(\.isNumber).suffix(10))
                if !key.isEmpty, !person(row).isEmpty { numbers[key] = person(row) }
            }
            for row in InstantReader.rows(db, "SELECT r.ZFIRSTNAME, r.ZLASTNAME, r.ZORGANIZATION, e.ZADDRESS FROM ZABCDEMAILADDRESS e JOIN ZABCDRECORD r ON r.Z_PK = e.ZOWNER", []) where !person(row).isEmpty {
                emails[row[3].lowercased()] = person(row)
            }
        }
        byNumber = numbers
        byEmail = emails
    }
}
