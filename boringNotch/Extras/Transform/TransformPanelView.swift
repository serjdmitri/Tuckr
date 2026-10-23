//
//  TransformPanelView.swift
//  The Shelf's fourth panel. A drag over it grows it into a grid of actions; dropping on one
//  runs it. Afterwards it shows what it made, which can be dragged out or revealed in Finder.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TransformPanelView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var model = TransformModel.shared
    @ObservedObject private var focus = ShelfPanelFocus.shared
    @Environment(\.shelfPanelCompact) private var compact
    @State private var panelTargeted = false

    private var expanded: Bool { focus.active == .transform }

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                expanded ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding(expanded ? 10 : 14)
            }
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $panelTargeted) { _ in false }
            .onChange(of: panelTargeted) { _, on in
                if on { model.refreshDragged() }
                focus.setTargeted(.transform, on)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .working(let action):
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if !compact {
                    Text(action.title + "…")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.gray)
                }
            }
        case .done(let result):
            ResultChip(result: result, compact: compact) { model.dismissResult() }
        case .idle:
            if expanded { tiles } else { idle }
        }
    }

    private var idle: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)
            if !compact {
                Text("Transform")
                    .foregroundStyle(.gray)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.medium)
                Text("Resize, convert, zip…")
                    .foregroundStyle(.gray.opacity(0.7))
                    .font(.system(.caption, design: .rounded))
            }
        }
    }

    /// What applies to the files being dragged; when the drag can't be read, everything.
    private var tiles: some View {
        let actions = TransformAction.allCases.filter { model.dragged.isEmpty || $0.applies(to: model.dragged) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: actions.count > 6 ? 4 : 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(actions) { action in
                ActionTile(action: action)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ActionTile: View {
    let action: TransformAction
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var model = TransformModel.shared
    @State private var dropTargeted = false
    private var targeted: Bool { dropTargeted || model.hoverTile == action }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: action.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.85))
            Text(action.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text(action.presetLabel ?? " ")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(targeted ? 0.18 : 0.07))
        )
        .scaleEffect(targeted ? 1.05 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .contentShape(Rectangle())
        .reportsShelfFrame(tile: action)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            vm.dropEvent = true
            TransformModel.shared.run(action, providers: providers)
            return true
        }
        // Over a tile the panel's own hover ends: keep it grown.
        .onChange(of: dropTargeted) { _, on in ShelfPanelFocus.shared.setTargeted(.transform, on) }
    }
}

private struct ResultChip: View {
    let result: TransformResult
    let compact: Bool
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: result.outputs.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(result.outputs.isEmpty ? .orange : .green)
            if !compact {
                Text(result.summary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let first = result.outputs.first {
                    HStack(spacing: 6) {
                        chip("Show", "folder") { NSWorkspace.shared.activateFileViewerSelecting(result.outputs) }
                        chip("Drag", "hand.draw") {}
                            .onDrag { NSItemProvider(contentsOf: first) ?? NSItemProvider() }
                    }
                }
            }
        }
        .onTapGesture { if compact { dismiss() } }
    }

    private func chip(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}
