//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    private let spacing: CGFloat = 8

    @ObservedObject private var focus = ShelfPanelFocus.shared
    private let gap: CGFloat = 12

    /// A panel a drag is over grows and the others shrink to their icon.
    private func weight(_ panel: ShelfPanel) -> CGFloat {
        guard let active = focus.active else { return 1 }
        return active == panel ? 2.1 : 0.6
    }

    private func width(_ panel: ShelfPanel, in total: CGFloat) -> CGFloat {
        let weights = ShelfPanel.allCases.map(weight)
        let usable = total - gap * CGFloat(weights.count - 1)
        return max(0, usable * weight(panel) / weights.reduce(0, +))
    }

    private func isCompact(_ panel: ShelfPanel) -> Bool {
        focus.active != nil && focus.active != panel
    }

    /// The shelf panel's own drop target, which also tells the others to make room.
    private var shelfTargeted: Binding<Bool> {
        Binding(
            get: { vm.dragDetectorTargeting },
            set: { on in
                vm.dragDetectorTargeting = on
                focus.setTargeted(.shelf, on)
            })
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: gap) {
                FileShareView()
                    .environmentObject(vm)
                    .environment(\.shelfPanelCompact, isCompact(.share))
                    .frame(width: width(.share, in: geo.size.width))
                panel
                    .environment(\.shelfPanelCompact, isCompact(.shelf))
                    .frame(width: width(.shelf, in: geo.size.width))
                    .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: shelfTargeted) { providers in
                        handleDrop(providers: providers)
                    }
                TranscribePanelView()
                    .environment(\.shelfPanelCompact, isCompact(.transcribe))
                    .frame(width: width(.transcribe, in: geo.size.width))
                TransformPanelView()
                    .environment(\.shelfPanelCompact, isCompact(.transform))
                    .frame(width: width(.transform, in: geo.size.width))
            }
        }
        .onChange(of: vm.dropZoneTargeting) { _, on in focus.setTargeted(.share, on) }
        .onDisappear { focus.reset() }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    if !isCompact(.shelf) {
                        Text("Drop files here")
                            .foregroundStyle(.gray)
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.medium)
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: shelfTargeted) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
