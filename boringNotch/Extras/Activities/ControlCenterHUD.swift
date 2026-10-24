//
//  ControlCenterHUD.swift
//  macOS draws its Focus pill ("Do Not Disturb · On") as a small window of Control Center. With
//  Accessibility access this is told the moment such a window appears and moves it out of
//  sight, so the notch's own inline version is the only one you see. Control Center's
//  menu-bar items are windows too and are never touched: a pill is recognised by what is in
//  it (an icon and two lines of text, no menu-bar item).
//

import AppKit
import ApplicationServices
import Defaults

@MainActor
final class ControlCenterHUD {
    static let shared = ControlCenterHUD()

    private static let bundleID = "com.apple.controlcenter"
    private var observer: AXObserver?
    private var handled = Set<UInt>()

    func start() {
        attach()
        repairMenuBarItems()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == ControlCenterHUD.bundleID else { return }
            MainActor.assumeIsolated { ControlCenterHUD.shared.observer = nil; ControlCenterHUD.shared.attach() }
        }
    }

    private func attach() {
        guard observer == nil,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, _ in
            MainActor.assumeIsolated { ControlCenterHUD.shared.windowAppeared(element) }
        }
        guard AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard AXObserverAddNotification(created, root, kAXWindowCreatedNotification as CFString, nil) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    private func windowAppeared(_ window: AXUIElement) {
        guard Defaults[.activityFocus], Defaults[.focusHideSystemPill] else { return }
        Task { @MainActor in
            // Its contents arrive a moment after the window: look quickly, a few times.
            for _ in 0..<40 {
                switch Self.kind(of: window) {
                case .pill:
                    Self.moveAway(window)
                    return
                case .menuItem:
                    return
                case .unknown:
                    try? await Task.sleep(for: .milliseconds(8))
                }
            }
        }
    }

    // MARK: Recognising a window

    private enum Kind { case pill, menuItem, unknown }

    private static func kind(of window: AXUIElement) -> Kind {
        guard string(window, kAXSubroleAttribute) == "AXHostedViewSceneWindow" else { return .menuItem }
        var found = (image: false, texts: 0, menuItem: false)
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < 6 else { return }
            switch string(element, kAXRoleAttribute) {
            case "AXMenuBarItem": found.menuItem = true
            case "AXImage": found.image = true
            case "AXStaticText": found.texts += 1
            default: break
            }
            for child in children(element) { walk(child, depth + 1) }
        }
        walk(window, 0)
        if found.menuItem { return .menuItem }
        return found.image && found.texts >= 2 ? .pill : .unknown
    }

    private static func moveAway(_ window: AXUIElement) {
        var point = CGPoint(x: 6000, y: 100)
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    /// An earlier test of mine pushed Control Center's Focus menu-bar item out of sight: put any
    /// menu-bar item that is parked far off-screen back.
    private func repairMenuBarItems() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows)
        for window in (windows as? [AXUIElement]) ?? [] where Self.kind(of: window) == .menuItem {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID() else { continue }
            var point = CGPoint.zero
            AXValueGetValue(value as! AXValue, .cgPoint, &point)
            guard point.x >= 4000 else { continue }
            var home = CGPoint(x: 1562, y: 0)
            if let target = AXValueCreate(.cgPoint, &home) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, target)
            }
        }
    }

    // MARK: Accessibility helpers

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return (value as? [AXUIElement]) ?? []
    }
}
