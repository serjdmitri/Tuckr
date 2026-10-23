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

        /// Out of the way of clicks; in the way only while a file is being dragged.
        override func hitTest(_ point: NSPoint) -> NSView? {
            MainActor.assumeIsolated { NotchHold.dragActive } ? super.hitTest(point) : nil
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
            MainActor.assumeIsolated {
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
            return panel == nil ? [] : .copy
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
            MainActor.assumeIsolated {
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
            clear()
            return panel != .transform || tile != nil
        }
    }
}
