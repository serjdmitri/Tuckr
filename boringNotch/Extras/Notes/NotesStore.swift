//
//  NotesStore.swift
//  boringNotch
//
//  The notch's notes, kept in a folder called "Notch" in Apple Notes. Typing is saved there
//  a moment after you stop; the list is read back when the page opens. Only that folder is
//  touched.
//

import AppKit

/// Whether the notch window may take the keyboard: only while a notes editor is up and
/// being typed in. It never steals focus otherwise.
@MainActor
enum NotchKeyboard {
    /// The notes page is showing, so a click may make the notch window key.
    static var allowKey = false
    /// The text fields that have the cursor (the search box, the editor). While any does, the
    /// notch stays open.
    private static var typingSources = Set<String>() {
        didSet { if typingSources.isEmpty && !oldValue.isEmpty { onEndTyping?() } }
    }

    static var isTyping: Bool { !typingSources.isEmpty }

    static func setTyping(_ source: String, _ on: Bool) {
        if on { typingSources.insert(source) } else { typingSources.remove(source) }
    }

    static func stopTyping() { typingSources.removeAll() }
    /// Called when typing ends, so the host can close the notch if nobody is hovering.
    static var onEndTyping: (() -> Void)?

    private static var resignObserver: NSObjectProtocol?

    /// Gives the notch window the keyboard now (the notes page asks for it when a text field
    /// is about to be typed in).
    static func takeKeyboard() {
        guard allowKey else { return }
        NSApp.windows.first { $0 is BoringNotchSkyLightWindow && $0.isVisible }?.makeKey()
    }

    /// Clicking into another app takes the keyboard from the notch window without the text
    /// view being told: end the typing then, and save.
    static func watchForKeyLoss() {
        guard resignObserver == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard note.object is BoringNotchSkyLightWindow else { return }
                NotesStore.shared.flush()
                stopTyping()
            }
        }
    }
}

struct NoteItem: Identifiable, Equatable, Codable {
    /// Apple Notes' id, or "local-…" until the note has been created there.
    var id: String
    /// The name Notes shows (its first line).
    var name: String
    var text: String = ""
    /// The note as Notes' HTML (what the editor shows and what is written back).
    var html: String = ""
    var folder: String = "Notch"
    var modified: Date = Date()
    /// False until the note's text has been read: the list only carries names.
    var isLoaded = true
    var locked = false
    var hasAttachments = false

    var isLocalOnly: Bool { id.hasPrefix("local-") }

    var title: String {
        let line = isLoaded
            ? (text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? "")
            : name
        return line.isEmpty ? (name.isEmpty ? "New note" : name) : line
    }

    var preview: String {
        guard isLoaded else { return folder }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
        let joined = lines.prefix(2).joined(separator: " ")
        return joined.isEmpty ? folder : joined
    }
}

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    enum Status: Equatable { case idle, saving, saved, failed(String) }

    @Published private(set) var notes: [NoteItem] = []
    @Published var selectedID: String?
    @Published private(set) var status = Status.idle
    @Published private(set) var loading = false
    @Published private(set) var pinnedIDs: [String] = []
    /// Notes pinned in Apple Notes itself (read from its database, never changed here).
    @Published private(set) var applePinnedIDs: [String] = []
    @Published private(set) var applePinsNeedAccess = false
    /// Bumped to ask the editor to take the cursor (after + is pressed).
    @Published private(set) var focusToken = 0

    private let bridge = NotesBridge()
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private static let cacheKey = "notchNotesCache3"
    private static let pinKey = "notchPinnedNotes"
    private static let applePinKey = "notchApplePinnedNotes"
    /// How long after the last keystroke the note is written to Notes.
    private static let saveDelay: Duration = .milliseconds(350)

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
            let cached = try? JSONDecoder().decode([NoteItem].self, from: data)
        {
            notes = cached
        }
        pinnedIDs = UserDefaults.standard.stringArray(forKey: Self.pinKey) ?? []
        applePinnedIDs = UserDefaults.standard.stringArray(forKey: Self.applePinKey) ?? []
        selectedID = pinned.first?.id ?? notes.first?.id
    }

    var selected: NoteItem? { notes.first { $0.id == selectedID } }

    // MARK: - What the list shows

    /// Pinned notes: those pinned in Apple Notes (newest first), then those pinned here in
    /// the order they were pinned.
    var pinned: [NoteItem] {
        let apple = notes.filter { applePinnedIDs.contains($0.id) }.sorted { $0.modified > $1.modified }
        let local = pinnedIDs.filter { !applePinnedIDs.contains($0) }.compactMap { id in notes.first { $0.id == id } }
        return apple + local
    }

    /// Everything else, newest first.
    var unpinned: [NoteItem] {
        notes.filter { !pinnedIDs.contains($0.id) && !applePinnedIDs.contains($0.id) }
            .sorted { $0.modified > $1.modified }
    }

    func isPinned(_ id: String) -> Bool { pinnedIDs.contains(id) || applePinnedIDs.contains(id) }

    /// Pinned in Apple Notes: it can only be unpinned there.
    func isApplePinned(_ id: String) -> Bool { applePinnedIDs.contains(id) }

    /// Reads which notes Apple Notes has pinned, once the list is known.
    private func refreshApplePins() {
        Task {
            switch await ApplePins.read() {
            case .pins(let numbers):
                applePinsNeedAccess = false
                let ids = notes.map(\.id).filter { id in
                    numbers.contains { id.hasSuffix("/ICNote/p\($0)") }
                }
                if ids != applePinnedIDs {
                    applePinnedIDs = ids
                    UserDefaults.standard.set(ids, forKey: Self.applePinKey)
                }
            case .noAccess:
                applePinsNeedAccess = true
            case .failed:
                break
            }
        }
    }

    func togglePin(_ id: String) {
        guard !applePinnedIDs.contains(id) else { return }
        if let index = pinnedIDs.firstIndex(of: id) { pinnedIDs.remove(at: index) } else { pinnedIDs.append(id) }
        UserDefaults.standard.set(pinnedIDs, forKey: Self.pinKey)
    }

    // MARK: - Reading

    /// Shows the saved copy at once, then reads every note's name from Notes.
    func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let fresh = try await bridge.list()
                var merged: [NoteItem] = fresh.map { note in
                    guard let known = notes.first(where: { $0.id == note.id }) else { return note }
                    // A note being typed keeps its text; an untouched one keeps what was read if
                    // Notes has not changed it since.
                    if saveTasks[note.id] != nil { return known }
                    if known.isLoaded && !known.html.isEmpty && abs(known.modified.timeIntervalSince(note.modified)) < 2 {
                        var kept = note
                        kept.html = known.html
                        kept.text = known.text
                        kept.isLoaded = true
                        kept.hasAttachments = known.hasAttachments
                        return kept
                    }
                    return note
                }
                merged.insert(contentsOf: notes.filter { $0.isLocalOnly }, at: 0)
                notes = merged
                // Pins of notes that are gone.
                let live = Set(notes.map(\.id))
                let kept = pinnedIDs.filter { live.contains($0) }
                if kept != pinnedIDs {
                    pinnedIDs = kept
                    UserDefaults.standard.set(kept, forKey: Self.pinKey)
                }
                if selected == nil { selectedID = pinned.first?.id ?? unpinned.first?.id }
                persist()
                refreshApplePins()
                if let selected, !selected.isLoaded { loadText(selected.id) }
            } catch {
                status = .failed(Self.describe(error))
            }
        }
    }

    func select(_ id: String) {
        flush()
        selectedID = id
        if let note = notes.first(where: { $0.id == id }), !note.isLoaded, !note.locked { loadText(id) }
    }

    /// Reads one note's text (the list only has names).
    private func loadText(_ id: String) {
        Task {
            do {
                let (html, text, attachments) = try await bridge.load(id: id)
                guard let index = notes.firstIndex(where: { $0.id == id }), saveTasks[id] == nil else { return }
                notes[index].html = html
                notes[index].text = text
                notes[index].hasAttachments = attachments > 0
                notes[index].isLoaded = true
                persist()
            } catch {
                status = .failed(Self.describe(error))
            }
        }
    }

    // MARK: - Editing

    func newNote() {
        let note = NoteItem(id: "local-\(UUID().uuidString)", name: "", text: "")
        notes.insert(note, at: 0)
        selectedID = note.id
        focusToken += 1
    }

    /// The editor's content changed: remember it and write it to Notes shortly.
    func setContent(html: String, text: String, for id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].html != html,
            notes[index].isLoaded, !notes[index].locked, !notes[index].hasAttachments
        else { return }
        backUpOriginal(notes[index])
        notes[index].html = html
        notes[index].text = text
        notes[index].modified = Date()
        persist()
        scheduleSave(id)
    }

    func delete(_ id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes.remove(at: index)
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        if let pin = pinnedIDs.firstIndex(of: id) {
            pinnedIDs.remove(at: pin)
            UserDefaults.standard.set(pinnedIDs, forKey: Self.pinKey)
        }
        selectedID = pinned.first?.id ?? unpinned.first?.id
        persist()
        guard !note.isLocalOnly else { return }
        Task {
            do { try await bridge.delete(id: note.id) } catch { status = .failed(Self.describe(error)) }
        }
    }

    /// Writes anything still waiting, now (the notch is closing or the note is changing).
    func flush() {
        for id in Array(saveTasks.keys) {
            saveTasks[id]?.cancel()
            Task { await save(id) }
        }
    }

    private func scheduleSave(_ id: String) {
        saveTasks[id]?.cancel()
        status = .saving
        saveTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            await self?.save(id)
        }
    }

    private func save(_ id: String) async {
        saveTasks[id] = nil
        guard let note = notes.first(where: { $0.id == id }) else {
            if saveTasks.isEmpty && status == .saving { status = .saved }
            return
        }
        // An empty note that was never created stays only here.
        if note.isLocalOnly && note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if saveTasks.isEmpty { status = .idle }
            return
        }
        do {
            if note.isLocalOnly {
                let newID = try await bridge.create(html: note.html)
                if let index = notes.firstIndex(where: { $0.id == id }) {
                    notes[index].id = newID
                    notes[index].folder = "Notch"
                    if selectedID == id { selectedID = newID }
                    if let pin = pinnedIDs.firstIndex(of: id) { pinnedIDs[pin] = newID }
                    // The text may have moved on while the note was being created.
                    if notes[index].html != note.html { scheduleSave(newID) }
                }
            } else {
                try await bridge.update(id: note.id, html: note.html)
            }
            persist()
            if saveTasks.isEmpty { status = .saved }
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    private var backedUp = Set<String>()

    /// Before an existing note is changed from here for the first time, its HTML is kept in
    /// Application Support: Apple Notes cannot take back checklists or numbered lists that
    /// this editor turns into bullets.
    private func backUpOriginal(_ note: NoteItem) {
        guard !note.isLocalOnly, !note.html.isEmpty, backedUp.insert(note.id).inserted else { return }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("The BoringCoucouify/NotesBackup", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = note.id.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-")
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? note.html.write(to: folder.appendingPathComponent("\(safe)-\(stamp).html"), atomically: true, encoding: .utf8)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private static func describe(_ error: Error) -> String {
        let text = (error as NSError).userInfo["NSAppleScriptErrorMessage"] as? String ?? error.localizedDescription
        if (error as NSError).userInfo["NSAppleScriptErrorNumber"] as? Int == -1743 {
            return "Allow this app to control Notes in System Settings › Privacy & Security › Automation."
        }
        return text
    }
}

/// Talks to Apple Notes through AppleScript, one call at a time, off the main thread.
final class NotesBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "notch.notes.applescript", qos: .userInitiated)
    private let folder = "Notch"
    private static let fieldSeparator: Character = "\u{1F}", recordSeparator: Character = "\u{1E}"

    /// Every note except those in Recently Deleted: id, name, folder, how long ago it was
    /// changed and whether it is locked. No text: that is read when a note is opened.
    func list() async throws -> [NoteItem] {
        // Folder by folder: asking for every note's container at once gives nothing useful.
        let script = """
            tell application "Notes"
                if not (exists folder "\(folder)") then make new folder with properties {name:"\(folder)"}
                set nowD to current date
                set rs to character id 30
                set fs to character id 31
                set out to ""
                repeat with f in (every folder)
                    set fname to name of f
                    if fname is not "Recently Deleted" then
                        set cnt to count of (every note of f)
                        if cnt > 0 then
                            set ids to id of every note of f
                            set nms to name of every note of f
                            set mds to modification date of every note of f
                            set pws to password protected of every note of f
                            repeat with i from 1 to cnt
                                set ago to (((item i of mds) - nowD) as integer)
                                set out to out & (item i of ids) & fs & (item i of nms) & fs & fname & fs & ago & fs & ((item i of pws) as string) & rs
                            end repeat
                        end if
                    end if
                end repeat
                return out
            end tell
            """
        let result = try await run(script)
        let now = Date()
        return result.split(separator: Self.recordSeparator, omittingEmptySubsequences: true).compactMap {
            let parts = $0.split(separator: Self.fieldSeparator, omittingEmptySubsequences: false)
            guard parts.count == 5 else { return nil }
            return NoteItem(
                id: String(parts[0]), name: String(parts[1]), text: "", folder: String(parts[2]),
                modified: now.addingTimeInterval(TimeInterval(Int(parts[3]) ?? 0)),
                isLoaded: false, locked: parts[4] == "true", hasAttachments: false)
        }
    }

    /// One note's HTML, its plain text and how many attachments it has.
    func load(id: String) async throws -> (String, String, Int) {
        let result = try await run("""
            tell application "Notes"
                set n to note id "\(Self.escape(id))"
                return (body of n) & (character id 31) & (plaintext of n) & (character id 31) & (count of attachments of n)
            end tell
            """)
        let parts = result.split(separator: Self.fieldSeparator, maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return ("", result, 0) }
        return (String(parts[0]), String(parts[1]), Int(parts[2].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
    }

    func create(html: String) async throws -> String {
        try await run("""
            tell application "Notes"
                if not (exists folder "\(folder)") then make new folder with properties {name:"\(folder)"}
                set n to make new note at folder "\(folder)" with properties {body:"\(Self.escape(html))"}
                return id of n
            end tell
            """)
    }

    func update(id: String, html: String) async throws {
        _ = try await run("""
            tell application "Notes" to set body of note id "\(Self.escape(id))" to "\(Self.escape(html))"
            """)
    }

    func delete(id: String) async throws {
        _ = try await run("""
            tell application "Notes" to delete note id "\(Self.escape(id))"
            """)
    }

    private func run(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var info: NSDictionary?
                let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&info)
                if let info {
                    continuation.resume(throwing: NSError(domain: "NotesBridge", code: 1, userInfo: info as? [String: Any]))
                } else {
                    continuation.resume(returning: descriptor?.stringValue ?? "")
                }
            }
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
