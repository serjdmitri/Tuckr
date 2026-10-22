//
//  NotesView.swift
//  boringNotch
//
//  The Notes page: the list of notes on the left, the writing area on the right, and what
//  state the saving to Apple Notes is in.
//

import AppKit
import SwiftUI

struct NotesView: View {
    @ObservedObject private var store = NotesStore.shared
    @State private var query = ""
    @State private var searching = false
    @State private var hoveredID: String?
    /// The Pinned section's drop-down: kept between launches.
    @AppStorage("notesPinnedOpen") private var pinnedOpen = true
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            list
                .frame(width: 210)
            editor
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            NotchKeyboard.allowKey = true
            NotchKeyboard.watchForKeyLoss()
            store.refresh()
        }
        .onDisappear {
            store.flush()
            NotchKeyboard.allowKey = false
            NotchKeyboard.stopTyping()
        }
    }

    // MARK: - The list

    private var matches: (pinned: [NoteItem], others: [NoteItem]) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func keep(_ n: NoteItem) -> Bool {
            q.isEmpty || n.title.lowercased().contains(q) || n.text.lowercased().contains(q)
                || n.folder.lowercased().contains(q)
        }
        return (store.pinned.filter(keep), store.unpinned.filter(keep))
    }

    private var list: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Notes")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(store.notes.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                Spacer()
                roundButton("magnifyingglass", help: "Search") {
                    searching.toggle()
                    if searching {
                        NotchKeyboard.takeKeyboard()
                        searchFocused = true
                    } else {
                        query = ""
                        searchFocused = false
                    }
                }
                roundButton("plus", help: "New note") { store.newNote() }
            }
            if searching {
                TextField("Search notes", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .focused($searchFocused)
                    // The notch stays open while the search box has the cursor.
                    .onChange(of: searchFocused) { _, focused in NotchKeyboard.setTyping("search", focused) }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            }
            ScrollView {
                LazyVStack(spacing: 3) {
                    let result = matches
                    if !result.pinned.isEmpty {
                        pinnedHeader(count: result.pinned.count)
                        if pinnedOpen || !query.isEmpty { ForEach(result.pinned) { row($0) } }
                        if !result.others.isEmpty { sectionLabel("All notes") }
                    }
                    ForEach(result.others) { row($0) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// "Pinned ▾": click to hide or show every pinned note.
    private func pinnedHeader(count: Int) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) { pinnedOpen.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(pinnedOpen ? 90 : 0))
                Text("PINNED")
                    .font(.system(size: 9, weight: .bold))
                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                Spacer()
            }
            .foregroundStyle(.gray)
            .padding(.horizontal, 9)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinnedOpen ? "Hide pinned notes" : "Show pinned notes")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 4)
    }

    private func row(_ note: NoteItem) -> some View {
        let selected = note.id == store.selectedID
        let pinned = store.isPinned(note.id)
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if note.locked {
                        Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.gray)
                    }
                    Text(note.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(note.preview)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if pinned || hoveredID == note.id {
                Button { store.togglePin(note.id) } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned ? Color(red: 1, green: 0.8, blue: 0.2) : .gray)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pinned ? "Unpin" : "Pin to the top")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(selected ? 0.14 : 0.0)))
        .contentShape(Rectangle())
        .onTapGesture { store.select(note.id) }
        .onHover { inside in hoveredID = inside ? note.id : (hoveredID == note.id ? nil : hoveredID) }
        .contextMenu {
            Button(pinned ? "Unpin" : "Pin to the top") { store.togglePin(note.id) }
            Button("Delete", role: .destructive) { store.delete(note.id) }
        }
    }

    // MARK: - The editor

    private var editor: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
            if let note = store.selected {
                if note.locked {
                    notice("This note is locked in Apple Notes. Unlock and edit it there.")
                } else if !note.isLoaded {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if note.hasAttachments {
                    VStack(spacing: 6) {
                        Text(note.text)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        Text("This note has pictures or files, so it can only be read here. Edit it in Apple Notes.")
                            .font(.system(size: 10))
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                } else {
                    VStack(spacing: 4) {
                        NotesFormatBar()
                        NotesTextEditor(
                            html: note.html, noteID: note.id, focusToken: store.focusToken
                        ) { html, text in store.setContent(html: html, text: text, for: note.id) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
            } else {
                notice("No notes yet. Press + to write one.")
            }
            HStack(spacing: 10) {
                statusLabel
                if let id = store.selectedID {
                    Button { store.togglePin(id) } label: {
                        Image(systemName: store.isPinned(id) ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(store.isPinned(id) ? Color(red: 1, green: 0.8, blue: 0.2) : .gray)
                    }
                    .buttonStyle(.plain)
                    .help(store.isPinned(id) ? "Unpin" : "Pin to the top")
                    Button { store.delete(id) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this note (it goes to Recently Deleted in Notes)")
                }
            }
            .padding(.trailing, 10)
            .padding(.bottom, 7)
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.gray)
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch store.status {
        case .idle:
            EmptyView()
        case .saving:
            Text("Saving to Notes…").font(.system(size: 10)).foregroundStyle(.gray)
        case .saved:
            Label("Saved to Notes", systemImage: "checkmark")
                .font(.system(size: 10)).foregroundStyle(Color(red: 0.3, green: 0.8, blue: 0.5))
        case .failed(let message):
            Text(message).font(.system(size: 10)).foregroundStyle(Color(red: 1, green: 0.42, blue: 0.38))
                .lineLimit(1).help(message)
        }
    }
}

/// The formatting bar: block style, bold, italic, underline, strikethrough, monospace,
/// bullets, checklist and numbering, lit for what is on at the cursor.
struct NotesFormatBar: View {
    @ObservedObject private var editor = NotesEditorController.shared

    var body: some View {
        let state = editor.state
        _ = editor.revision
        return HStack(spacing: 2) {
            Menu {
                Button("Title") { editor.setBlock(.title) }
                Button("Heading") { editor.setBlock(.heading) }
                Button("Body") { editor.setBlock(.body) }
            } label: {
                Text(state.block == .title ? "Title" : (state.block == .heading ? "Heading" : "Body"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 46)
            .padding(.trailing, 4)
            button("bold", on: state.bold, help: "Bold  ⌘B") { editor.toggle(.bold) }
            button("italic", on: state.italic, help: "Italic  ⌘I") { editor.toggle(.italic) }
            button("underline", on: state.underline, help: "Underline  ⌘U") { editor.toggle(.underline) }
            button("strikethrough", on: state.strike, help: "Strikethrough  ⇧⌘X") { editor.toggle(.strike) }
            button("chevron.left.forwardslash.chevron.right", on: state.mono, help: "Monospaced") { editor.toggle(.mono) }
            Divider().frame(height: 14).padding(.horizontal, 4)
            button("list.bullet", on: state.list == .bullet, help: "Bulleted list") { editor.toggleList(.bullet) }
            button("checklist", on: state.list == .checklist, help: "Checklist: click a box to tick it") { editor.toggleList(.checklist) }
            button("list.number", on: state.list == .numbered, help: "Numbered list") { editor.toggleList(.numbered) }
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func button(_ symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? .black : .white.opacity(0.85))
                .frame(width: 24, height: 20)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.white.opacity(0.92) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The rich text editor the notch can type into: a click makes the notch window the key
/// window (it is allowed to be while this page shows), and the cursor keeps the notch open.
struct NotesTextEditor: NSViewRepresentable {
    let html: String
    let noteID: String
    /// Changes when the editor should take the cursor.
    var focusToken = 0
    let onChange: (_ html: String, _ text: String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let view = NotesNSTextView()
        view.isRichText = true
        view.importsGraphics = false
        view.drawsBackground = false
        view.insertionPointColor = .white
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticLinkDetectionEnabled = true
        view.allowsUndo = true
        view.textContainerInset = .zero
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.linkTextAttributes = [
            .foregroundColor: NSColor(red: 0.45, green: 0.7, blue: 1, alpha: 1),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        view.delegate = context.coordinator
        view.onFormattingChange = { NotesEditorController.shared.touch() }
        context.coordinator.view = view
        context.coordinator.load(html: html, into: view)
        scroll.documentView = view
        NotesEditorController.shared.textView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = context.coordinator.view else { return }
        NotesEditorController.shared.textView = view
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                NotchKeyboard.takeKeyboard()
                view.window?.makeFirstResponder(view)
            }
        }
        // Another note was picked: show it.
        if context.coordinator.shownID != noteID {
            context.coordinator.shownID = noteID
            context.coordinator.load(html: html, into: view)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextEditor
        weak var view: NotesNSTextView?
        var shownID: String?
        var isEditing = false
        var focusToken = 0
        private var loading = false

        init(_ parent: NotesTextEditor) {
            self.parent = parent
            shownID = parent.noteID
        }

        func load(html: String, into view: NotesNSTextView) {
            loading = true
            let attributed = html.isEmpty ? NSAttributedString(string: "", attributes: NotesStyle.bodyAttributes) : NotesHTML.attributed(from: html)
            view.textStorage?.setAttributedString(attributed)
            view.typingAttributes = NotesStyle.bodyAttributes
            view.undoManager?.removeAllActions()
            loading = false
            NotesEditorController.shared.touch()
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidChange(_ notification: Notification) {
            guard !loading, let view, let storage = view.textStorage else { return }
            parent.onChange(NotesHTML.html(from: storage), storage.string)
            NotesEditorController.shared.touch()
        }

        /// Esc leaves the editor and gives the keyboard back.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            textView.window?.makeFirstResponder(nil)
            textView.window?.resignKey()
            return true
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            NotesStore.shared.flush()
        }
    }
}
