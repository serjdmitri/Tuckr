//
//  BoringHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import CoucouCore
import Defaults
import SwiftUI

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    @ObservedObject var notchTimer = NotchTimer.shared
    @ObservedObject var notificationFeed = NotificationFeed.shared
    @Default(.notchLocked) private var notchLocked
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if coordinator.currentView == .agents {
                            CoucouHost.makeAgentsHeaderAccessory()
                        }
                        // One drop-down for the extras, so the header does not fill up: Notes,
                        // Timer and Teleprompter. While a timer runs, its stopwatch is the icon.
                        Menu {
                            Button { open(.notes) } label: { Label("Notes", systemImage: "note.text") }
                            Button { open(.timer) } label: { Label("Timer", systemImage: "timer") }
                            Button { open(.teleprompter) } label: { Label("Teleprompter", systemImage: "text.alignleft") }
                            Button { open(.inbox) } label: {
                                Label(notificationFeed.unread > 0 ? "Messages (\(notificationFeed.unread))" : "Messages", systemImage: "bubble.left.and.bubble.right")
                            }
                        } label: {
                            Capsule()
                                .fill([.notes, .timer, .teleprompter, .inbox].contains(coordinator.currentView) ? Color(nsColor: .secondarySystemFill) : .black)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if notchTimer.phase != .idle {
                                        TimerGlyph(size: 18)
                                    } else {
                                        Image(systemName: "square.grid.2x2")
                                            .foregroundColor(.white)
                                            .imageScale(.medium)
                                    }
                                }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Notes, Timer, Teleprompter, Messages")
                        .overlay(alignment: .topTrailing) {
                            // Messages waiting.
                            if notificationFeed.unread > 0 {
                                Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)).frame(width: 9, height: 9)
                                    .allowsHitTesting(false)
                            }
                        }
                        // Keeps the notch open until it is unlocked.
                        Button {
                            notchLocked.toggle()
                        } label: {
                            Capsule()
                                .fill(notchLocked ? Color(nsColor: .secondarySystemFill) : .black)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: notchLocked ? "lock.fill" : "lock.open")
                                        .foregroundColor(notchLocked ? Color.effectiveAccent : .white)
                                        .imageScale(.medium)
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(notchLocked ? "Unlock: let the notch close again" : "Lock the notch open")
                        if Defaults[.weatherEnabled] && coordinator.currentView == .home { WeatherChip() }
                        // The mirror is for the music (Home) and call-recording (Meetings) tabs.
                        if Defaults[.showMirror] && (coordinator.currentView == .home || coordinator.currentView == .meetings) {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "web.camera")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showBatteryIndicator] {
                            BoringBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    private func open(_ view: NotchViews) {
        withAnimation(.smooth) { coordinator.currentView = view }
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
