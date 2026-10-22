//
//  TeleprompterStore.swift
//  boringNotch
//
//  The teleprompter's scripts (each a list of parts), its settings, and where they are kept:
//  one JSON file in Application Support. Scripts stay on this Mac.
//

import AppKit
import SwiftUI

struct ScriptPart: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var text: String
}

struct Script: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var parts: [ScriptPart]
}

@MainActor
final class TeleprompterStore: ObservableObject {
    static let shared = TeleprompterStore()

    @Published var scripts: [Script] = []
    @Published var scriptID: UUID?
    @Published var partID: UUID?

    // Settings, kept in UserDefaults.
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "tpSpeed") } }
    @Published var textSize: Double { didSet { UserDefaults.standard.set(textSize, forKey: "tpTextSize") } }
    @Published var mirrored: Bool { didSet { UserDefaults.standard.set(mirrored, forKey: "tpMirror") } }
    @Published var countdown: Bool { didSet { UserDefaults.standard.set(countdown, forKey: "tpCountdown") } }
    /// Keep the notch out of screen shares and recordings while reading.
    @Published var hideFromSharing: Bool { didSet { UserDefaults.standard.set(hideFromSharing, forKey: "tpHideShare") } }

    static let speedRange = 10.0...160.0
    static let sizeRange = 16.0...52.0

    private var saveTask: Task<Void, Never>?

    private init() {
        let d = UserDefaults.standard
        speed = d.object(forKey: "tpSpeed") as? Double ?? 45
        textSize = d.object(forKey: "tpTextSize") as? Double ?? 28
        mirrored = d.bool(forKey: "tpMirror")
        countdown = d.object(forKey: "tpCountdown") as? Bool ?? true
        hideFromSharing = d.object(forKey: "tpHideShare") as? Bool ?? true
        load()
        if scripts.isEmpty { newScript(select: true) }
        scriptID = scriptID ?? scripts.first?.id
        partID = script?.parts.first?.id
    }

    var script: Script? { scripts.first { $0.id == scriptID } }
    var part: ScriptPart? { script?.parts.first { $0.id == partID } }

    // MARK: Scripts and parts

    func newScript(select: Bool = true) {
        let s = Script(title: "Script \(scripts.count + 1)", parts: [ScriptPart(title: "Part 1", text: "")])
        scripts.append(s)
        if select { scriptID = s.id; partID = s.parts.first?.id }
        save()
    }

    func deleteScript(_ id: UUID) {
        scripts.removeAll { $0.id == id }
        if scripts.isEmpty { newScript(select: true) }
        if scriptID == id { scriptID = scripts.first?.id; partID = script?.parts.first?.id }
        save()
    }

    func renameScript(_ title: String) {
        guard let i = scripts.firstIndex(where: { $0.id == scriptID }) else { return }
        scripts[i].title = title
        save()
    }

    func selectScript(_ id: UUID) {
        scriptID = id
        partID = script?.parts.first?.id
    }

    @discardableResult
    func addPart(title: String? = nil, text: String = "") -> UUID? {
        guard let i = scripts.firstIndex(where: { $0.id == scriptID }) else { return nil }
        let part = ScriptPart(title: title ?? "Part \(scripts[i].parts.count + 1)", text: text)
        scripts[i].parts.append(part)
        partID = part.id
        save()
        return part.id
    }

    func deletePart(_ id: UUID) {
        guard let i = scripts.firstIndex(where: { $0.id == scriptID }) else { return }
        scripts[i].parts.removeAll { $0.id == id }
        if scripts[i].parts.isEmpty { scripts[i].parts.append(ScriptPart(title: "Part 1", text: "")) }
        if partID == id { partID = scripts[i].parts.first?.id }
        save()
    }

    func movePart(_ id: UUID, by offset: Int) {
        guard let s = scripts.firstIndex(where: { $0.id == scriptID }),
            let from = scripts[s].parts.firstIndex(where: { $0.id == id })
        else { return }
        let to = from + offset
        guard scripts[s].parts.indices.contains(to) else { return }
        scripts[s].parts.swapAt(from, to)
        save()
    }

    func setPart(title: String? = nil, text: String? = nil, for id: UUID) {
        guard let s = scripts.firstIndex(where: { $0.id == scriptID }),
            let p = scripts[s].parts.firstIndex(where: { $0.id == id })
        else { return }
        if let title { scripts[s].parts[p].title = title }
        if let text { scripts[s].parts[p].text = text }
        scheduleSave()
    }

    /// The part after (or before) the current one, for the reading controls.
    func neighbour(_ step: Int) -> UUID? {
        guard let parts = script?.parts, let i = parts.firstIndex(where: { $0.id == partID }) else { return nil }
        return parts.indices.contains(i + step) ? parts[i + step].id : nil
    }

    // MARK: Importing

    /// Puts imported text into the current part when that is still empty, otherwise into a new one.
    func importText(_ text: String, title: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let part, part.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setPart(title: title, text: trimmed, for: part.id)
            save()
        } else {
            addPart(title: title, text: trimmed)
        }
    }

    func importFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string) { importText(text, title: "Pasted text") }
    }

    func importFile(_ url: URL) {
        let text: String?
        if ["rtf", "rtfd"].contains(url.pathExtension.lowercased()) {
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        } else {
            text = try? String(contentsOf: url, encoding: .utf8)
        }
        if let text { importText(text, title: url.deletingPathExtension().lastPathComponent) }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .rtf, .text, .utf8PlainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a text file to use as a script part"
        panel.level = .modalPanel
        if panel.runModal() == .OK, let url = panel.url { importFile(url) }
    }

    // MARK: Saving

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("The BoringCoucouify", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Teleprompter.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
            let saved = try? JSONDecoder().decode([Script].self, from: data)
        else { return }
        scripts = saved
        if let id = UserDefaults.standard.string(forKey: "tpScript").flatMap(UUID.init), scripts.contains(where: { $0.id == id }) {
            scriptID = id
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        saveTask?.cancel()
        if let data = try? JSONEncoder().encode(scripts) { try? data.write(to: Self.fileURL, options: .atomic) }
        UserDefaults.standard.set(scriptID?.uuidString, forKey: "tpScript")
    }
}

/// Keeps the notch out of screen sharing and recordings while the teleprompter is reading.
@MainActor
enum NotchPrivacy {
    static func setHidden(_ hidden: Bool) {
        for window in NSApp.windows where window is BoringNotchSkyLightWindow {
            window.sharingType = hidden ? .none : .readOnly
        }
    }
}

/// A plain text editor for the notch, with the keyboard handling it needs (see NotchKeyboard).
struct NotchPlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var placeholderKey = "tp-editor"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let view = PlainNotchTextView()
        view.source = placeholderKey
        view.isRichText = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = .white
        view.insertionPointColor = .white
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.allowsUndo = true
        view.textContainerInset = .zero
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        view.string = text
        scroll.documentView = view
        context.coordinator.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = context.coordinator.view else { return }
        if view.string != text && !context.coordinator.editing { view.string = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotchPlainTextEditor
        weak var view: PlainNotchTextView?
        var editing = false

        init(_ parent: NotchPlainTextEditor) { self.parent = parent }

        func textDidBeginEditing(_ notification: Notification) { editing = true }
        func textDidEndEditing(_ notification: Notification) { editing = false }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            parent.text = view.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            textView.window?.makeFirstResponder(nil)
            textView.window?.resignKey()
            return true
        }
    }
}

final class PlainNotchTextView: NSTextView {
    var source = "plain"

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { MainActor.assumeIsolated { NotchKeyboard.setTyping(source, true) } }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { MainActor.assumeIsolated { NotchKeyboard.setTyping(source, false) } }
        return ok
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = event.modifierFlags.contains(.shift)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": copy(nil); return true
        case "x": cut(nil); return true
        case "v": pasteAsPlainText(nil); return true
        case "a": selectAll(nil); return true
        case "z": if shift { undoManager?.redo() } else { undoManager?.undo() }; return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
