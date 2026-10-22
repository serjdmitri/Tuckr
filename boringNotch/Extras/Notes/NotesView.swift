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

    var body: some View {
        HStack(spacing: 10) {
            list
                .frame(width: 190)
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
            NotchKeyboard.isTyping = false
        }
    }

    private var list: some View {
        VStack(spacing: 6) {
            HStack {
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
                Button { store.newNote() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("New note")
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.notes) { note in
                        row(note)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ note: NoteItem) -> some View {
        let selected = note.id == store.selectedID
        return VStack(alignment: .leading, spacing: 1) {
            Text(note.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(selected ? 0.14 : 0.0)))
        .contentShape(Rectangle())
        .onTapGesture {
            store.flush()
            store.selectedID = note.id
        }
    }

    private var editor: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
            if let note = store.selected {
                NotesTextEditor(
                    text: Binding(get: { note.text }, set: { store.setText($0, for: note.id) }),
                    noteID: note.id)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 26)
            } else {
                Text("No notes yet. Press + to write one.")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 10) {
                statusLabel
                if let id = store.selectedID {
                    Button { store.delete(id) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this note")
                }
            }
            .padding(.trailing, 10)
            .padding(.bottom, 7)
        }
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

/// A plain text editor the notch can type into: a click makes the notch window the key
/// window (it is allowed to be while this page shows), and the cursor keeps the notch open.
struct NotesTextEditor: NSViewRepresentable {
    @Binding var text: String
    let noteID: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let view = NSTextView()
        view.isRichText = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 13)
        view.textColor = .white
        view.insertionPointColor = .white
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
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
        // Another note was picked (or the list refreshed): show its text.
        if context.coordinator.shownID != noteID {
            context.coordinator.shownID = noteID
            view.string = text
        } else if view.string != text && !context.coordinator.isEditing {
            view.string = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextEditor
        weak var view: NSTextView?
        var shownID: String?
        var isEditing = false

        init(_ parent: NotesTextEditor) {
            self.parent = parent
            shownID = parent.noteID
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
            NotchKeyboard.isTyping = true
        }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            parent.text = view.string
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
            NotchKeyboard.isTyping = false
            NotesStore.shared.flush()
        }
    }
}
