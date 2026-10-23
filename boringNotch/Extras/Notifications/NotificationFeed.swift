//
//  NotificationFeed.swift
//  Message previews in the notch. macOS keeps every notification it delivers (Messages,
//  WhatsApp, Telegram, Slack, Mail…) in one database; with Full Disk Access this reads that
//  database, never writes it, and shows what arrives. A copy of the files is read, so the
//  system's own notification service is never held up. Nothing is saved: the text lives in
//  memory only.
//

import AppKit
import Defaults
import SQLite3

struct NotificationItem: Identifiable, Equatable {
    let id: Int
    let appID: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    let thread: String
    /// For a voice message: the saved sound, once it has been found.
    var audioURL: URL? = nil
}

/// The apps whose notifications show by default: the ones people talk in.
enum NotificationApps {
    static let defaults: Set<String> = [
        "com.apple.mobilesms", "net.whatsapp.whatsapp", "ru.keepcoder.telegram", "org.telegram.desktop",
        "com.tinyspeck.slackmacgap", "com.apple.mail", "com.hnc.discord", "org.whispersystems.signal-desktop",
        "com.facebook.archon", "com.microsoft.teams2", "com.readdle.smartemail-mac",
    ]
}

@MainActor
final class NotificationFeed: ObservableObject {
    static let shared = NotificationFeed()

    /// Newest first, only from the apps that are switched on.
    @Published private(set) var items: [NotificationItem] = []
    /// Arrived since the inbox was last looked at.
    @Published private(set) var unread = 0
    /// What the closed notch is dropping down with right now, newest first. Several that arrive
    /// close together stack, each leaving on its own timer.
    @Published private(set) var popups: [NotificationItem] = []
    var popup: NotificationItem? { popups.first }
    /// Every app seen in the database (identifier → name), for the settings list.
    @Published private(set) var seenApps: [String: String] = [:]
    /// macOS refused the database: no Full Disk Access.
    @Published private(set) var needsAccess = false

    private var lastID = 0
    /// Messages the banner watcher already showed: the database delivers them again a little later.
    private var captured: [String: Date] = [:]
    private var syntheticID = 0
    private var started = false
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var refreshTask: Task<Void, Never>?
    private var hideTasks: [Int: Task<Void, Never>] = [:]
    private var poll: Timer?

    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2", isDirectory: true)

    func start() {
        guard !started else { return }
        started = true
        refresh()
        watch()
        // The write-ahead file can be swapped out from under a watcher: look again now and then.
        poll = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            MainActor.assumeIsolated {
                NotificationFeed.shared.refresh()
                if NotificationFeed.shared.watchers.isEmpty { NotificationFeed.shared.watch() }
            }
        }
    }

    // MARK: Watching

    private func watch() {
        watchers.forEach { $0.cancel() }
        watchers = []
        for name in ["db-wal", "db"] {
            let fd = Darwin.open(Self.directory.appendingPathComponent(name).path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    NotificationFeed.shared.refresh()
                    // Renamed or deleted: the watcher is on a dead file; set up again.
                    if source.data.contains(.delete) || source.data.contains(.rename) {
                        NotificationFeed.shared.watch()
                    }
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    // MARK: Reading

    /// Looks for what is new, a moment after the last change (a burst of writes is one read).
    func refresh() {
        guard Defaults[.notificationsEnabled] else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            let after = self.lastID
            let result = await Task.detached(priority: .utility) { NotificationDatabase.read(after: after) }.value
            self.apply(result, firstRead: after == 0)
        }
    }

    private func apply(_ result: NotificationDatabase.Result, firstRead: Bool) {
        switch result {
        case .noAccess:
            needsAccess = true
        case .failed:
            break
        case .rows(let rows, let maxID):
            needsAccess = false
            lastID = max(lastID, maxID)
            for row in rows where seenApps[row.appID] == nil { seenApps[row.appID] = Self.name(for: row.appID) }
            let enabled = Defaults[.notificationApps]
            let fresh = rows.filter { enabled.contains($0.appID) && !wasCaptured($0.appID, $0.title, $0.body) }.map { row in
                NotificationItem(
                    id: row.id, appID: row.appID, appName: seenApps[row.appID] ?? row.appID, title: row.title,
                    subtitle: row.subtitle, body: row.body, date: row.date, thread: row.thread)
            }
            guard !fresh.isEmpty else { return }
            items = Array((fresh.reversed() + items).prefix(40))
            // What was already there at launch is history, not news.
            guard !firstRead else { return }
            unread += fresh.count
            for item in fresh where Date().timeIntervalSince(item.date) < 90 { show(item); findAudio(for: item) }
        }
    }

    // MARK: From the banner

    private func signature(_ appID: String, _ title: String, _ body: String) -> String { "\(appID)|\(title)|\(body)" }

    private func wasCaptured(_ appID: String, _ title: String, _ body: String) -> Bool {
        captured = captured.filter { Date().timeIntervalSince($0.value) < 120 }
        return captured[signature(appID, title, body)] != nil
    }

    /// A banner macOS is showing, read as it appeared. True when it is one of the apps switched
    /// on here, which is then shown by the notch (and the banner closed).
    func captured(appName: String, title: String, subtitle: String, body: String) -> Bool {
        guard Defaults[.notificationsEnabled] else { return false }
        let enabled = Defaults[.notificationApps]
        var candidates = Set(seenApps.keys).union(NotificationApps.defaults)
        candidates.formUnion(enabled)
        guard let appID = candidates.first(where: {
            enabled.contains($0) && Self.name(for: $0).caseInsensitiveCompare(appName) == .orderedSame
        }) else { return false }
        captured[signature(appID, title, body)] = Date()
        syntheticID -= 1
        let item = NotificationItem(
            id: syntheticID, appID: appID, appName: Self.name(for: appID), title: title, subtitle: subtitle,
            body: body, date: Date(), thread: "")
        items = Array(([item] + items).prefix(40))
        unread += 1
        show(item)
        findAudio(for: item)
        return true
    }

    /// A voice message: look for its sound a few times, as the chat app may save it a moment late.
    private func findAudio(for item: NotificationItem) {
        guard VoiceLocator.looksLikeVoice(title: item.title, body: item.body) else { return }
        Task { @MainActor [weak self] in
            for delay in [0.2, 0.8, 2.0, 4.0] {
                try? await Task.sleep(for: .seconds(delay))
                if let url = await VoiceLocator.locate(appID: item.appID) {
                    self?.attach(audio: url, to: item.id)
                    return
                }
            }
        }
    }

    private func attach(audio: URL, to id: Int) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].audioURL = audio }
        if let i = popups.firstIndex(where: { $0.id == id }) { popups[i].audioURL = audio }
    }

    // MARK: Popup and inbox

    private func show(_ item: NotificationItem) {
        popups.insert(item, at: 0)
        // Three cards at most; the oldest makes way.
        if popups.count > 3, let gone = popups.popLast() { hideTasks[gone.id]?.cancel(); hideTasks[gone.id] = nil }
        hideTasks[item.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            // Not while it is being listened to.
            while VoicePlayer.shared.isPlaying(item.id) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled else { return }
            self?.dismiss(item.id)
        }
    }

    func dismiss(_ id: Int) {
        if VoicePlayer.shared.isPlaying(id) { VoicePlayer.shared.stop() }
        hideTasks[id]?.cancel()
        hideTasks[id] = nil
        popups.removeAll { $0.id == id }
    }

    func markRead() { unread = 0 }

    func clear() {
        items = []
        unread = 0
    }

    // MARK: Apps

    static func name(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.split(separator: ".").last.map(String.init)?.capitalized ?? bundleID
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil) ?? NSImage()
    }

    static func open(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Reads the system's notification database (a copy of it) for rows newer than one already seen.
enum NotificationDatabase {
    struct Row {
        let id: Int
        let appID: String
        let title: String
        let subtitle: String
        let body: String
        let date: Date
        let thread: String
    }

    enum Result {
        case rows([Row], maxID: Int)
        case noAccess
        case failed
    }

    static func read(after lastID: Int) -> Result {
        let fm = FileManager.default
        let source = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2", isDirectory: true)
        let scratch = fm.temporaryDirectory.appendingPathComponent("notch-un-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            // The write-ahead files hold the newest rows, so they come along.
            for name in ["db", "db-wal", "db-shm"] {
                let from = source.appendingPathComponent(name)
                if name == "db" || fm.fileExists(atPath: from.path) {
                    try fm.copyItem(at: from, to: scratch.appendingPathComponent(name))
                }
            }
        } catch {
            let nsError = error as NSError
            return [513, 257, 1].contains(nsError.code) || nsError.domain == NSPOSIXErrorDomain ? .noAccess : .failed
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(scratch.appendingPathComponent("db").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return .failed
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return .failed }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(lastID))

        var rows: [Row] = []
        var maxID = lastID
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(statement, 0))
            maxID = max(maxID, id)
            guard let identifier = sqlite3_column_text(statement, 1).map({ String(cString: $0).lowercased() }),
                  let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let request = plist["req"] as? [String: Any] else { continue }
            let title = request["titl"] as? String ?? ""
            let body = request["body"] as? String ?? ""
            guard !title.isEmpty || !body.isEmpty else { continue }
            var seconds = sqlite3_column_double(statement, 3)
            if seconds == 0 { seconds = (plist["date"] as? NSNumber)?.doubleValue ?? 0 }
            rows.append(Row(
                id: id, appID: identifier, title: title, subtitle: request["subt"] as? String ?? "", body: body,
                date: seconds == 0 ? Date() : Date(timeIntervalSinceReferenceDate: seconds),
                thread: request["thre"] as? String ?? ""))
        }
        return .rows(rows, maxID: maxID)
    }
}

