//
//  TeleprompterView.swift
//  boringNotch
//
//  The teleprompter page: write or import a script in parts, then read it as large text that
//  scrolls under the camera, with speed and size controls and, optionally, out of sight of
//  screen sharing.
//

import SwiftUI
import UniformTypeIdentifiers

struct TeleprompterView: View {
    @ObservedObject private var store = TeleprompterStore.shared
    @State private var reading = false

    var body: some View {
        Group {
            if reading {
                ReadingView(onExit: { reading = false })
            } else {
                EditView(onStart: { reading = true })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            NotchKeyboard.allowKey = true
            NotchKeyboard.watchForKeyLoss()
            // The notch stays open for as long as this page is showing, however the pointer
            // moves, until another tab is picked.
            NotchKeyboard.setTyping("teleprompter", true)
        }
        .onChange(of: reading) { _, now in NotchPrivacy.setHidden(now && store.hideFromSharing) }
        .onChange(of: store.hideFromSharing) { _, hide in if reading { NotchPrivacy.setHidden(hide) } }
        .onDisappear {
            store.save()
            NotchPrivacy.setHidden(false)
            NotchKeyboard.allowKey = false
            NotchKeyboard.setTyping("teleprompter", false)
            NotchKeyboard.stopTyping()
        }
    }
}

// MARK: - Writing the script

private struct EditView: View {
    @ObservedObject private var store = TeleprompterStore.shared
    let onStart: () -> Void
    @State private var showNotes = false
    @State private var showSettings = false
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            sidebar.frame(width: 190)
            editor
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        // A popover hangs below the notch, so the pointer leaves it: hold the notch open.
        .onChange(of: showNotes || showSettings) { _, open in NotchKeyboard.setTyping("popover", open) }
        .onDisappear { NotchKeyboard.setTyping("popover", false) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in store.importFile(url) }
            }
            return true
        }
    }

    private var sidebar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(store.scripts) { script in
                        Button(script.title) { store.selectScript(script.id) }
                    }
                    Divider()
                    Button("New script") { store.newScript() }
                    if let id = store.scriptID {
                        Button("Delete this script", role: .destructive) { store.deleteScript(id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(store.script?.title ?? "Script")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.gray)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                Spacer()
                roundButton("plus", help: "New part") { store.addPart() }
            }
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.script?.parts ?? []) { part in
                        row(part)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ part: ScriptPart) -> some View {
        let selected = part.id == store.partID
        return VStack(alignment: .leading, spacing: 1) {
            Text(part.title.isEmpty ? "Untitled part" : part.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(part.text.isEmpty ? "Empty" : part.text.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 10))
                .foregroundStyle(.gray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(selected ? 0.14 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { store.partID = part.id }
        .contextMenu {
            Button("Move up") { store.movePart(part.id, by: -1) }
            Button("Move down") { store.movePart(part.id, by: 1) }
            Button("Delete part", role: .destructive) { store.deletePart(part.id) }
        }
    }

    private var editor: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07))
                if let part = store.part {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Part title", text: Binding(
                            get: { part.title }, set: { store.setPart(title: $0, for: part.id) }))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                        NotchPlainTextEditor(
                            text: Binding(get: { part.text }, set: { store.setPart(text: $0, for: part.id) }))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .id(part.id)
                }
            }
            HStack(spacing: 6) {
                pill("doc.on.clipboard", "Paste") { store.importFromClipboard() }
                    .help("Put the text on the clipboard into the script")
                pill("doc.text", "File…") { store.chooseFile() }
                    .help("Import a .txt, .md or .rtf file (or drop one here)")
                pill("note.text", "A note…") { showNotes = true }
                    .popover(isPresented: $showNotes, arrowEdge: .bottom) { NotesPickerView(isPresented: $showNotes) }
                Spacer()
                roundButton("slider.horizontal.3", help: "Speed, size and privacy") { showSettings = true }
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) { SettingsPanel() }
                Button(action: onStart) {
                    HStack(spacing: 4) {
                        Text("Continue").font(.system(size: 12, weight: .bold))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .disabled((store.script?.parts.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true)
            }
        }
    }

    private func pill(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.white.opacity(0.12)))
    }
    .buttonStyle(.plain)
    .help(help)
}

/// Speed, text size and the other settings.
private struct SettingsPanel: View {
    @ObservedObject private var store = TeleprompterStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelled("Text size", value: "\(Int(store.textSize)) pt") {
                Slider(value: $store.textSize, in: TeleprompterStore.sizeRange, step: 1)
            }
            labelled("Speed", value: "\(Int(store.speed))") {
                Slider(value: $store.speed, in: TeleprompterStore.speedRange, step: 1)
            }
            Toggle("Mirror the text", isOn: $store.mirrored)
            Toggle("Count down 3, 2, 1 first", isOn: $store.countdown)
            Toggle("Tick on each count", isOn: $store.countdownSound).disabled(!store.countdown)
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Hide from screen sharing while reading", isOn: $store.hideFromSharing)
                Text("Apps that capture the screen the modern way may still show it. Test with your own call app.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(14)
        .frame(width: 280)
    }

    private func labelled<Content: View>(_ title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.system(size: 12, weight: .semibold)); Spacer(); Text(value).font(.system(size: 11)).foregroundStyle(.secondary) }
            content()
        }
    }
}

/// Pick a note from Apple Notes to use as a part.
private struct NotesPickerView: View {
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var store = TeleprompterStore.shared
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var loadingID: String?

    private var matches: [NoteItem] {
        let q = query.lowercased()
        return notes.notes.filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.folder.lowercased().contains(q) }
            .sorted { $0.modified > $1.modified }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search notes", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(matches.prefix(60)) { note in
                        Button {
                            loadingID = note.id
                            Task {
                                if let text = await notes.plainText(for: note.id) {
                                    store.importText(text, title: note.title)
                                    isPresented = false
                                }
                                loadingID = nil
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(note.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(note.folder).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if loadingID == note.id { ProgressView().controlSize(.mini) }
                            }
                            .padding(.vertical, 3).padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(note.locked)
                    }
                }
            }
            .frame(height: 220)
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { notes.refresh() }
    }
}

// MARK: - Reading it

private struct ReadingView: View {
    @ObservedObject private var store = TeleprompterStore.shared
    let onExit: () -> Void

    @State private var playing = false
    @State private var base = 0.0
    @State private var startDate = Date()
    @State private var contentHeight: CGFloat = 0
    @State private var countdownValue: Int?
    @State private var ended = false
    @FocusState private var focused: Bool
    @State private var wheelMonitor: Any?

    /// How far the text has scrolled at a moment.
    private func offset(at date: Date) -> Double {
        let moving = playing ? store.speed * date.timeIntervalSince(startDate) : 0
        return min(max(0, base + moving), Double(contentHeight))
    }

    var body: some View {
        VStack(spacing: 4) {
            textArea
            controls
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { toggle(); return .handled }
        .onKeyPress(.upArrow) { store.speed = min(TeleprompterStore.speedRange.upperBound, store.speed + 5); return .handled }
        .onKeyPress(.downArrow) { store.speed = max(TeleprompterStore.speedRange.lowerBound, store.speed - 5); return .handled }
        .onChange(of: store.speed) { old, _ in
            if playing { base += old * Date().timeIntervalSince(startDate); startDate = Date() }
        }
        .onChange(of: store.partID) { _, _ in restart() }
        .onAppear {
            focused = true
            // The wheel or trackpad moves the text, running or paused: it carries on from where it was left.
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.window is BoringNotchSkyLightWindow else { return event }
                scroll(by: event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8))
                return nil
            }
        }
        .onDisappear {
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
            wheelMonitor = nil
        }
    }

    /// Fingers moving down bring earlier lines back; up, later ones.
    private func scroll(by delta: CGFloat) {
        guard contentHeight > 0, countdownValue == nil else { return }
        let now = Date()
        base = min(max(0, offset(at: now) - Double(delta)), Double(contentHeight))
        startDate = now
        if ended, base < Double(contentHeight) - 1 { ended = false }
    }

    // MARK: Text

    private var textArea: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: !playing)) { timeline in
                let y = offset(at: timeline.date)
                Text(store.part?.text ?? "")
                    .font(.system(size: store.textSize, weight: .semibold, design: .rounded))
                    .lineSpacing(store.textSize * 0.32)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .frame(width: min(geo.size.width - 40, 520))
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { proxy in
                        Color.clear.onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, h in contentHeight = h }
                    })
                    .scaleEffect(x: store.mirrored ? -1 : 1, y: 1)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .offset(y: -y + 2)
                    .onChange(of: timeline.date) { _, date in
                        if playing, offset(at: date) >= Double(contentHeight), contentHeight > 0 { finish() }
                    }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                            .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                if let countdownValue {
                    Text("\(countdownValue)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else if ended {
                    VStack(spacing: 6) {
                        Text(store.neighbour(1) == nil ? "End of the script" : "End of this part")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        if let next = store.neighbour(1) {
                            Button("Next part ›") { store.partID = next }
                                .buttonStyle(.plain).font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(Capsule().fill(.white))
                        }
                    }
                }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: { pause(); onExit() }) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                    Text("Edit").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            transport("backward.end.fill", help: "Previous part", enabled: store.neighbour(-1) != nil) {
                if let id = store.neighbour(-1) { store.partID = id }
            }
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Image(systemName: playing || countdownValue != nil ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    if !playing && countdownValue == nil {
                        Text(base > 0 && !ended ? "Resume" : "Start").font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            .help("Start or pause (space)")
            transport("forward.end.fill", help: "Next part", enabled: store.neighbour(1) != nil) {
                if let id = store.neighbour(1) { store.partID = id }
            }
            transport("arrow.counterclockwise", help: "Back to the start", enabled: true) { restart() }
            Spacer(minLength: 4)
            slider(icon: "hare.fill", value: $store.speed, range: TeleprompterStore.speedRange, help: "Speed (↑ ↓)")
            slider(icon: "textformat.size", value: $store.textSize, range: TeleprompterStore.sizeRange, help: "Text size")
            Button { store.mirrored.toggle() } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: 11))
                    .foregroundStyle(store.mirrored ? .black : .white.opacity(0.85))
                    .frame(width: 26, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(store.mirrored ? Color.white : Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Mirror the text")
        }
        .frame(height: 30)
    }

    private func transport(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.85 : 0.3))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private func slider(icon: String, value: Binding<Double>, range: ClosedRange<Double>, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(.gray)
            Slider(value: value, in: range).controlSize(.mini).frame(width: 74)
        }
        .help(help)
    }

    // MARK: Playing

    private func toggle() {
        if countdownValue != nil { countdownValue = nil; return }
        if playing { pause(); return }
        if ended { restart() }
        if store.countdown && base == 0 {
            Task { @MainActor in
                for n in [3, 2, 1] {
                    guard countdownValue != nil || n == 3 else { return }
                    withAnimation(.spring(response: 0.3)) { countdownValue = n }
                    if store.countdownSound { NSSound(named: "Tink")?.play() }
                    try? await Task.sleep(for: .seconds(1))
                    if countdownValue == nil { return }
                }
                withAnimation { countdownValue = nil }
                if store.countdownSound { NSSound(named: "Pop")?.play() }
                play()
            }
        } else {
            play()
        }
    }

    private func play() { startDate = Date(); playing = true; ended = false }

    private func pause() {
        base = offset(at: Date())
        playing = false
    }

    private func finish() {
        base = Double(contentHeight)
        playing = false
        withAnimation { ended = true }
    }

    private func restart() {
        playing = false
        base = 0
        ended = false
        countdownValue = nil
    }
}
