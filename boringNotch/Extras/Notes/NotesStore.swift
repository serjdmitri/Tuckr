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
    /// A text field in the notch has the cursor: the notch stays open.
    static var isTyping = false {
        didSet { if !isTyping && oldValue { onEndTyping?() } }
    }
    /// Called when typing ends, so the host can close the notch if nobody is hovering.
    static var onEndTyping: (() -> Void)?

    private static var resignObserver: NSObjectProtocol?

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
                isTyping = false
            }
        }
    }
}

struct NoteItem: Identifiable, Equatable, Codable {
    /// Apple Notes' id, or "local-…" until the note has been created there.
    var id: String
    var text: String

    var isLocalOnly: Bool { id.hasPrefix("local-") }

    var title: String {
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return line.isEmpty ? "New note" : line
    }

    var preview: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
        return lines.prefix(2).joined(separator: " ")
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

    private let bridge = NotesBridge()
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private static let cacheKey = "notchNotesCache"
    /// How long after the last keystroke the note is written to Notes.
    private static let saveDelay: Duration = .milliseconds(350)

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
            let cached = try? JSONDecoder().decode([NoteItem].self, from: data)
        {
            notes = cached
        }
        selectedID = notes.first?.id
    }

    var selected: NoteItem? { notes.first { $0.id == selectedID } }

    // MARK: - Reading

    /// Shows the saved copy at once, then reads the folder.
    func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let fresh = try await bridge.list()
                // Notes being typed or not yet created stay as they are.
                let pending = Set(saveTasks.keys)
                var merged = fresh.map { note in
                    pending.contains(note.id) ? (notes.first { $0.id == note.id } ?? note) : note
                }
                merged.insert(contentsOf: notes.filter { $0.isLocalOnly }, at: 0)
                notes = merged
                if selected == nil { selectedID = notes.first?.id }
                persist()
            } catch {
                status = .failed(Self.describe(error))
            }
        }
    }

    // MARK: - Editing

    func newNote() {
        let note = NoteItem(id: "local-\(UUID().uuidString)", text: "")
        notes.insert(note, at: 0)
        selectedID = note.id
    }

    /// The editor's text changed: remember it and write it to Notes shortly.
    func setText(_ text: String, for id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        persist()
        scheduleSave(id)
    }

    func delete(_ id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes.remove(at: index)
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        selectedID = notes.first?.id
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
                let newID = try await bridge.create(text: note.text)
                if let index = notes.firstIndex(where: { $0.id == id }) {
                    notes[index].id = newID
                    if selectedID == id { selectedID = newID }
                    // The text may have moved on while the note was being created.
                    if notes[index].text != note.text { scheduleSave(newID) }
                }
            } else {
                try await bridge.update(id: note.id, text: note.text)
            }
            persist()
            if saveTasks.isEmpty { status = .saved }
        } catch {
            status = .failed(Self.describe(error))
        }
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
    private static let fieldSeparator = "\u{1F}", recordSeparator = "\u{1E}"

    func list() async throws -> [NoteItem] {
        let script = """
            tell application "Notes"
                if not (exists folder "\(folder)") then make new folder with properties {name:"\(folder)"}
                set rs to character id 30
                set fs to character id 31
                set out to ""
                repeat with n in (notes of folder "\(folder)")
                    set out to out & (id of n) & fs & (plaintext of n) & rs
                end repeat
                return out
            end tell
            """
        let result = try await run(script)
        return result.split(separator: Character(Self.recordSeparator), omittingEmptySubsequences: true).compactMap {
            let parts = $0.split(separator: Character(Self.fieldSeparator), maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return NoteItem(id: String(parts[0]), text: String(parts[1]))
        }
    }

    func create(text: String) async throws -> String {
        try await run("""
            tell application "Notes"
                if not (exists folder "\(folder)") then make new folder with properties {name:"\(folder)"}
                set n to make new note at folder "\(folder)" with properties {body:"\(Self.html(text))"}
                return id of n
            end tell
            """)
    }

    func update(id: String, text: String) async throws {
        _ = try await run("""
            tell application "Notes" to set body of note id "\(Self.escape(id))" to "\(Self.html(text))"
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

    /// Plain text as Notes' HTML, one div per line, ready to sit inside an AppleScript string.
    private static func html(_ text: String) -> String {
        let body = text.components(separatedBy: "\n").map { line -> String in
            let escaped = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<div>\(escaped.isEmpty ? "<br>" : escaped)</div>"
        }.joined()
        return escape(body)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
