//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import AppKit
import CoucouCore
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Agents", icon: "terminal.fill", view: .agents),
    TabModel(label: "Meetings", icon: "mic.fill", view: .meetings)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            // A click on the Agents tab while it shows the chat or Mochi's settings goes back to his cards.
                            if tab.view == .agents, coordinator.currentView == .agents { CoucouHost.AgentsPages.shared.back() }
                            coordinator.currentView = tab.view
                        }
                    }
                    // Agents tab: a double click opens the chat with Mochi, a right click his quick settings.
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        guard tab.view == .agents else { return }
                        withAnimation(.smooth) { coordinator.currentView = .agents }
                        CoucouHost.AgentsPages.shared.openChat()
                    })
                    .overlay {
                        if tab.view == .agents {
                            RightClickCatcher {
                                withAnimation(.smooth) { coordinator.currentView = .agents }
                                CoucouHost.AgentsPages.shared.openSettings()
                            }
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        // Only the selected tab carries the capsule. With more than two tabs the
                        // hidden copies the upstream code kept on the others all claimed the same
                        // matched-geometry id, and the glow could land on the wrong tab.
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(Color(nsColor: .secondarySystemFill))
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}

/// Catches a right click on what it covers and lets every other click through to what is below.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { action() }
    }
}
