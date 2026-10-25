//
//  ShelfDropLayer.swift
//  Drops of files onto the Shelf's panels, taken at the AppKit level. SwiftUI's own drop
//  targets (still there for text, links and the like) sometimes stopped telling the panels
//  that a file was over them, so a dragged file did nothing. This view sits over the panels,
//  works out from their frames which panel (or Transform tile) is under the pointer, and does
//  what the SwiftUI targets would have done.
//

import AppKit
import Defaults
import SwiftUI

/// Where the panels and the Transform tiles are, in the shelf row's own coordinates.
struct ShelfDropFrames: Equatable {
    var panels: [ShelfPanel: CGRect] = [:]
    var tiles: [TransformAction: CGRect] = [:]
}

struct ShelfDropFramesKey: PreferenceKey {
    static var defaultValue = ShelfDropFrames()
    static func reduce(value: inout ShelfDropFrames, nextValue: () -> ShelfDropFrames) {
        let next = nextValue()
        value.panels.merge(next.panels) { $1 }
        value.tiles.merge(next.tiles) { $1 }
    }
}

extension View {
    func reportsShelfFrame(panel: ShelfPanel) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(
                key: ShelfDropFramesKey.self,
                value: ShelfDropFrames(panels: [panel: proxy.frame(in: .named("shelfRow"))]))
        })
    }

    func reportsShelfFrame(tile: TransformAction) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(
                key: ShelfDropFramesKey.self,
                value: ShelfDropFrames(tiles: [tile: proxy.frame(in: .named("shelfRow"))]))
        })
    }
}

struct ShelfDropLayer: NSViewRepresentable {
    let frames: ShelfDropFrames
    let vm: BoringViewModel

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.vm = vm
        return view
    }

    func updateNSView(_ view: DropView, context: Context) {
        view.frames = frames
        view.vm = vm
    }

    final class DropView: NSView {
        var frames = ShelfDropFrames()
        weak var vm: BoringViewModel?
        private var current: ShelfPanel?

        override var isFlipped: Bool { true }

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.fileURL])
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hoverTimer?.invalidate()
            hoverTimer = nil
            if window != nil {
                Self.visible = self
                // The system does not always tell this view that a file is over it, so while one
                // is held the pointer's own place says which panel (or tile) it is on.
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.followHeldFile() }
                }
            } else if Self.visible === self { Self.visible = nil }
        }

        private var hoverTimer: Timer?
        private var idleTicks = 0

        @MainActor private func locate(screen: NSPoint) -> (panel: ShelfPanel?, tile: TransformAction?) {
            guard let window else { return (nil, nil) }
            let point = convert(window.convertPoint(fromScreen: screen), from: nil)
            if let tile = frames.tiles.first(where: { $0.value.contains(point) })?.key { return (.transform, tile) }
            return (frames.panels.first(where: { $0.value.contains(point) })?.key, nil)
        }

        @MainActor private func followHeldFile() {
            if NotchHold.dragActive, NSEvent.pressedMouseButtons & 1 != 0 {
                idleTicks = 0
                let (panel, tile) = locate(screen: NSEvent.mouseLocation)
                show(panel: panel, tile: tile)
            } else if current != nil || TransformModel.shared.hoverTile != nil {
                // Let go: a moment for the drop to be taken (it needs the panel still open), then reset.
                idleTicks += 1
                if idleTicks >= 10 { clear(); idleTicks = 0 }
            }
        }

        /// The layer that is on screen now, for a release the panels never heard about.
        nonisolated(unsafe) static weak var visible: DropView?
        /// Where a file was let go (screen coordinates): the panel under it takes it, or, with
        /// the shelf not showing, the notch's own area does.
        @MainActor static func handleRelease(at screen: NSPoint, vm: BoringViewModel?) {
            let urls = (NSPasteboard(name: .drag).readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            guard !urls.isEmpty else { return }
            if let view = visible {
                let (panel, tile) = view.locate(screen: screen)
                if let panel { view.apply(panel: panel, tile: tile, urls: urls); return }
            }
            guard let vm, vm.notchState == .open else { return }
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(urls.map { NSItemProvider(object: $0 as NSURL) })
        }

        /// Out of the way of clicks; in the way only while a file is being dragged.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let active = MainActor.assumeIsolated { NotchHold.dragActive }
            return active ? super.hitTest(point) : nil
        }

        // MARK: Dragging

        private func target(for info: NSDraggingInfo) -> (panel: ShelfPanel?, tile: TransformAction?) {
            let point = convert(info.draggingLocation, from: nil)
            if let tile = frames.tiles.first(where: { $0.value.contains(point) })?.key {
                return (.transform, tile)
            }
            let panel = frames.panels.first(where: { $0.value.contains(point) })?.key
            return (panel, nil)
        }

        private func track(_ info: NSDraggingInfo) -> NSDragOperation {
            let (panel, tile) = target(for: info)
            MainActor.assumeIsolated { show(panel: panel, tile: tile) }
            return panel == nil ? [] : .copy
        }

        /// Lights up the panel (and Transform tile) the held file is over.
        @MainActor private func show(panel: ShelfPanel?, tile: TransformAction?) {
            if panel != current {
                if let old = current { ShelfPanelFocus.shared.setTargeted(old, false) }
                if let panel { ShelfPanelFocus.shared.setTargeted(panel, true) }
                if panel == .transform { TransformModel.shared.refreshDragged() }
                current = panel
                vm?.dropZoneTargeting = panel == .share
                vm?.dragDetectorTargeting = panel == .shelf
            }
            if TransformModel.shared.hoverTile != tile { TransformModel.shared.hoverTile = tile }
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }

        override func draggingExited(_ sender: NSDraggingInfo?) { clear() }
        override func draggingEnded(_ sender: NSDraggingInfo) { clear() }

        private func clear() {
            MainActor.assumeIsolated {
                if let old = current { ShelfPanelFocus.shared.setTargeted(old, false) }
                current = nil
                vm?.dropZoneTargeting = false
                vm?.dragDetectorTargeting = false
                TransformModel.shared.hoverTile = nil
            }
        }

        // MARK: Dropping

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let (panel, tile) = target(for: sender)
            let urls = (sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            guard let panel, !urls.isEmpty else { return false }
            MainActor.assumeIsolated { apply(panel: panel, tile: tile, urls: urls) }
            clear()
            return panel != .transform || tile != nil
        }

        @MainActor fileprivate func apply(panel: ShelfPanel, tile: TransformAction?, urls: [URL]) {
            NotchHold.dropHandled = true
            do {
                vm?.dropEvent = true
                switch panel {
                case .share:
                    let providers = urls.map { NSItemProvider(object: $0 as NSURL) }
                    let shared = QuickShareService.shared
                    let chosen = shared.availableProviders.first(where: { $0.id == Defaults[.quickShareProvider] })
                        ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
                    Task { await shared.shareDroppedFiles(providers, using: chosen, from: self) }
                case .shelf:
                    guard !ShelfSelectionModel.shared.isDragging else { break }
                    ShelfStateViewModel.shared.load(urls.map { NSItemProvider(object: $0 as NSURL) })
                case .transcribe:
                    if let first = urls.first { TalkifyRuntime.current?.transcribeDropped(first) }
                case .transform:
                    if let tile { TransformModel.shared.run(tile, urls: urls) }
                }
            }
        }
    }
}
