//
//  TuckrWelcome.swift
//  The first screen: what Tuckr is, where things are, and the permissions it asks for with
//  what each one is for and whether it is already given. Shown on the first launch, and again
//  from Settings → About.
//

import AVFoundation
import AppKit
import ApplicationServices
import CoreBluetooth
import EventKit
import SwiftUI

// MARK: - Permissions

/// One permission the app can use, with how to look at it and how to ask for it.
struct WelcomePermission: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let title: String
    let reason: String
    let isGranted: () -> Bool
    let request: () -> Void

    static func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor static let bluetooth = BluetoothAsker()

    @MainActor static var all: [WelcomePermission] {
        [
            WelcomePermission(
                id: "accessibility", symbol: "hand.raised.fill", tint: .blue, title: "Accessibility",
                reason: "Swaps macOS's message banner for the notch popup, and shows incoming calls with Answer and Decline.",
                isGranted: { AXIsProcessTrusted() },
                request: {
                    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                    openPane("Privacy_Accessibility")
                }),
            WelcomePermission(
                id: "input", symbol: "keyboard.fill", tint: .indigo, title: "Input Monitoring",
                reason: "Lets the dictation key work in any app.",
                isGranted: { CGPreflightListenEventAccess() },
                request: { CGRequestListenEventAccess(); openPane("Privacy_ListenEvent") }),
            WelcomePermission(
                id: "disk", symbol: "internaldrive.fill", tint: .gray, title: "Full Disk Access",
                reason: "Reads macOS's notification list so Messages, WhatsApp and Telegram show in the notch. Read-only; nothing is saved.",
                isGranted: {
                    let dir = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2").path
                    return (try? FileManager.default.contentsOfDirectory(atPath: dir)) != nil
                },
                request: { openPane("Privacy_AllFiles") }),
            WelcomePermission(
                id: "microphone", symbol: "mic.fill", tint: .red, title: "Microphone",
                reason: "Dictation, the Transcribe panel's live mode and meeting notes.",
                isGranted: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
                request: {
                    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    } else {
                        openPane("Privacy_Microphone")
                    }
                }),
            WelcomePermission(
                id: "calendar", symbol: "calendar", tint: .orange, title: "Calendar",
                reason: "Shows your day on Home and pops up before an event starts.",
                isGranted: { EKEventStore.authorizationStatus(for: .event) == .fullAccess },
                request: {
                    if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                        Task { _ = try? await EKEventStore().requestFullAccessToEvents() }
                    } else {
                        openPane("Privacy_Calendars")
                    }
                }),
            WelcomePermission(
                id: "bluetooth", symbol: "airpodspro", tint: .cyan, title: "Bluetooth",
                reason: "Shows AirPods and other devices with their battery when they connect.",
                isGranted: { CBCentralManager.authorization == .allowedAlways },
                request: {
                    if CBCentralManager.authorization == .notDetermined { bluetooth.ask() } else { openPane("Privacy_Bluetooth") }
                }),
        ]
    }
}

/// Holds the Bluetooth manager long enough for macOS to show its question.
@MainActor
final class BluetoothAsker: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    func ask() { manager = CBCentralManager(delegate: self, queue: .main) }
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}
}

// MARK: - The screens

private enum WelcomeStep: Int, CaseIterable { case hello, tour, permissions, done }

struct TuckrWelcomeView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    @State private var step: WelcomeStep = .hello
    @State private var granted: Set<String> = []
    private let permissions = WelcomePermission.all
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .hello: hello.transition(.opacity)
                case .tour: tour.transition(.opacity)
                case .permissions: permissionsPage.transition(.opacity)
                case .done: done.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 520, height: 640)
        .background { VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea() }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        granted = Set(permissions.filter { $0.isGranted() }.map(\.id))
        // Accessibility given while the app was already running: start watching banners now.
        if granted.contains("accessibility") { BannerWatcher.shared.retry() }
    }

    private func go(_ next: WelcomeStep) { withAnimation(.easeInOut(duration: 0.35)) { step = next } }

    // MARK: Hello

    private var hello: some View {
        ZStack(alignment: .top) {
            Image("spotlight")
                .resizable().aspectRatio(contentMode: .fit)
                .blur(radius: 3).offset(y: -10)
                .background(SparkleView().opacity(0.6))
            VStack(spacing: 10) {
                Spacer().frame(height: 70)
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                Text("Tuckr")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("Everything you reach for, tucked into the notch.")
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 50)
                Spacer()
            }
        }
    }

    // MARK: Tour

    private let tourItems: [(String, Color, String, String)] = [
        ("music.note", .pink, "Home", "Music, your calendar and the weather. Tap the month to see all of it."),
        ("sparkles", .purple, "Agents", "Claude Code, Codex and friends, with Mochi telling you what they're up to."),
        ("tray.full.fill", .blue, "Shelf", "Drag a file at the notch: share it, transcribe it, resize, compress or cut it out."),
        ("message.fill", .green, "Messages and calls", "Popups for new messages, with a quick reply, and Answer / Decline for calls."),
        ("timer", .orange, "Timer, Notes, Teleprompter", "Small tools one click away. The notch stays open while you use them."),
        ("mic.fill", .red, "Dictation", "Hold the key, talk, and the words appear wherever you are typing."),
    ]

    private var tour: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What lives here").font(.system(size: 28, weight: .bold, design: .rounded))
            ForEach(tourItems, id: \.2) { item in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.0).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10).fill(item.1.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.2).font(.headline)
                        Text(item.3).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider().padding(.vertical, 2)
            Label("Point at the middle of the notch for Home. Point at its sides, when something is going on, to open that.", systemImage: "cursorarrow.motionlines")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36).padding(.top, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Permissions

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A few permissions").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Each one switches on something specific. Skip what you don't want; you can come back to this from Settings → About.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(permissions) { permission in
                        let isOn = granted.contains(permission.id)
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: permission.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 9).fill(permission.tint.gradient))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(permission.title).font(.headline)
                                Text(permission.reason).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            if isOn {
                                Label("On", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                                    .font(.callout.weight(.medium)).foregroundStyle(.green)
                            } else {
                                Button("Allow") { permission.request() }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 28).padding(.top, 44)
    }

    // MARK: Done

    private var done: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 58)).foregroundStyle(.green.gradient)
            Text("You're set").font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Move your pointer to the notch to begin. Everything can be changed in Settings, and this tour is always in Settings → About.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 54)
            Button { onOpenSettings() } label: { Label("Open Settings", systemImage: "gearshape") }
                .controlSize(.large).padding(.top, 6)
            Spacer()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(WelcomeStep.allCases, id: \.rawValue) { s in
                    Circle().fill(s == step ? Color.primary : Color.primary.opacity(0.2)).frame(width: 7, height: 7)
                }
            }
            Spacer()
            if step != .hello && step != .done {
                Button("Back") { go(WelcomeStep(rawValue: step.rawValue - 1) ?? .hello) }
            }
            Button(step == .done ? "Finish" : (step == .hello ? "Get started" : "Continue")) {
                if step == .done { onFinish() } else { go(WelcomeStep(rawValue: step.rawValue + 1) ?? .done) }
            }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
    }
}

// MARK: - Window

@MainActor
enum TuckrWelcome {
    private static var controller: NSWindowController?
    static let shownKey = "tuckrWelcomeShown"

    static var needed: Bool { !UserDefaults.standard.bool(forKey: shownKey) }

    static func show() {
        if controller == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.center()
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: TuckrWelcomeView(
                onFinish: { finish() },
                onOpenSettings: { finish(); SettingsWindowController.shared.showWindow() }))
            controller = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        controller?.window?.makeKeyAndOrderFront(nil)
    }

    private static func finish() {
        UserDefaults.standard.set(true, forKey: shownKey)
        BoringViewCoordinator.shared.firstLaunch = false
        controller?.window?.close()
        controller = nil
    }
}
