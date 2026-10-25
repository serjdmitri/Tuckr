//
//  TransformModel.swift
//  What the Shelf's panels share: which one a drag is over (it grows, the others shrink), and
//  the state of a Transform job.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ShelfPanel: CaseIterable {
    case share, shelf, transcribe, transform
}

/// Which Shelf panel is the centre of attention. A drag over a panel grows it; after a job the
/// Transform panel stays grown for a moment so its result can be read.
@MainActor
final class ShelfPanelFocus: ObservableObject {
    static let shared = ShelfPanelFocus()

    @Published private(set) var active: ShelfPanel?

    private var targeted: [ShelfPanel] = []
    private var held: (panel: ShelfPanel, until: Date)?
    private var task: Task<Void, Never>?

    func setTargeted(_ panel: ShelfPanel, _ on: Bool) {
        targeted.removeAll { $0 == panel }
        if on { targeted.append(panel) }
        schedule(after: on ? 0.1 : 0.35)
    }

    func hold(_ panel: ShelfPanel, seconds: Double) {
        held = (panel, Date().addingTimeInterval(seconds))
        schedule(after: 0)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 0.05))
            self?.schedule(after: 0)
        }
    }

    func reset() {
        task?.cancel()
        targeted.removeAll()
        held = nil
        active = nil
    }

    /// A short delay both ways, so panels sliding under the pointer don't make the layout flicker.
    private func schedule(after delay: Double) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            var next = targeted.last
            if next == nil, let held, held.until > Date() { next = held.panel }
            if next != active {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { active = next }
            }
        }
    }
}

private struct ShelfPanelCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True for a Shelf panel that is shrunk to make room for another.
    var shelfPanelCompact: Bool {
        get { self[ShelfPanelCompactKey.self] }
        set { self[ShelfPanelCompactKey.self] = newValue }
    }
}

@MainActor
final class TransformModel: ObservableObject {
    static let shared = TransformModel()

    enum Phase {
        case idle
        case working(TransformAction)
        case done(TransformResult)
    }

    @Published private(set) var phase: Phase = .idle
    /// The tile a dragged file is over, set by the AppKit drop layer.
    @Published var hoverTile: TransformAction?
    /// The files being dragged, read from the drag pasteboard when the drag reaches the panel,
    /// so the panel can offer only what applies to them.
    @Published private(set) var dragged: [URL] = []

    private var clearTask: Task<Void, Never>?

    var isBusy: Bool {
        if case .working = phase { return true }
        return false
    }

    func refreshDragged() {
        let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        dragged = urls ?? []
    }

    func clearDragged() { dragged = [] }

    func run(_ action: TransformAction, providers: [NSItemProvider]) {
        guard !isBusy else { return }
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        let group = DispatchGroup()
        let found = LockedURLs()
        for provider in files {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { found.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            Task { @MainActor in self?.start(action, on: found.values) }
        }
    }

    func run(_ action: TransformAction, urls: [URL]) {
        guard !isBusy else { return }
        start(action, on: urls)
    }

    private func start(_ action: TransformAction, on urls: [URL]) {
        guard !urls.isEmpty else { return }
        clearTask?.cancel()
        phase = .working(action)
        ShelfPanelFocus.shared.hold(.transform, seconds: 60)
        let settings = TransformEngine.Settings.current()
        Task { @MainActor in
            let result = await TransformEngine.run(action, on: urls, settings: settings)
            phase = .done(result)
            // A job that did nothing only needs a glance; one that made files stays a little longer.
            let worked = !result.outputs.isEmpty
            ShelfPanelFocus.shared.hold(.transform, seconds: worked ? 6 : 2.5)
            clearTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(worked ? 8 : 3))
                guard !Task.isCancelled else { return }
                phase = .idle
            }
        }
    }

    func dismissResult() {
        clearTask?.cancel()
        phase = .idle
    }
}

/// Collects the URLs the item providers hand back on their own queues.
private final class LockedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        urls.append(url)
    }

    var values: [URL] {
        lock.lock(); defer { lock.unlock() }
        return urls
    }
}
