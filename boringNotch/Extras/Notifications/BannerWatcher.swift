//
//  BannerWatcher.swift
//  The notch's message popup in place of macOS's own banner. macOS draws its banner in the
//  Notification Center process; with Accessibility access this is told the moment that window
//  appears, reads who the banner is from and what it says, hands that to the notch, and
//  closes the banner. The notification stays in Notification Center: only the banner goes.
//  Without Accessibility the notch still shows the message, a few seconds late and next to
//  the banner (see NotificationFeed).
//

import AppKit
import ApplicationServices
import Defaults

@MainActor
final class BannerWatcher {
    static let shared = BannerWatcher()

    private static let bundleID = "com.apple.notificationcenterui"
    private var observer: AXObserver?
    private var handled = Set<String>()
    private var scanning = false

    func start() {
        attach()
        // The Notification Center process can be restarted by macOS: attach again then.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == BannerWatcher.bundleID else { return }
            MainActor.assumeIsolated { BannerWatcher.shared.attach() }
        }
    }

    private func attach() {
        guard observer == nil,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
        else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, _ in
            MainActor.assumeIsolated { BannerWatcher.shared.bannerWindowAppeared() }
        }
        guard AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Refused without Accessibility access: nothing is watched then.
        guard AXObserverAddNotification(created, root, kAXWindowCreatedNotification as CFString, nil) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    /// The banner's window exists a moment before its contents do: look a few times.
    private func bannerWindowAppeared() {
        guard Defaults[.notificationsEnabled], Defaults[.notificationReplaceBanners], !scanning else { return }
        scanning = true
        Task { @MainActor in
            for delay in [0.04, 0.08, 0.15, 0.3, 0.6] {
                try? await Task.sleep(for: .seconds(delay))
                if scan() { break }
            }
            scanning = false
        }
    }

    /// True once a banner was found.
    private func scan() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows)
        var found = false
        for window in (windows as? [AXUIElement]) ?? [] where Self.string(window, kAXSubroleAttribute) == "AXSystemDialog" {
            for banner in Self.banners(in: window, depth: 0) {
                let id = Self.string(banner, kAXIdentifierAttribute)
                guard !id.isEmpty, handled.insert(id).inserted else { found = true; continue }
                found = true
                take(banner)
            }
        }
        if handled.count > 200 { handled.removeAll() }
        return found
    }

    private func take(_ banner: AXUIElement) {
        // "App, title, subtitle, body": the parts also sit in the banner's text children.
        var fields: [String: String] = [:]
        for child in Self.children(banner) {
            let id = Self.string(child, kAXIdentifierAttribute)
            if ["title", "subtitle", "body"].contains(id) { fields[id] = Self.string(child, kAXValueAttribute) }
        }
        let description = Self.string(banner, kAXDescriptionAttribute)
        let appName = description.components(separatedBy: ", ").first ?? ""
        guard !appName.isEmpty else { return }
        let took = NotificationFeed.shared.captured(
            appName: appName, title: fields["title"] ?? "", subtitle: fields["subtitle"] ?? "", body: fields["body"] ?? "")
        guard took else { return }
        var names: CFArray?
        AXUIElementCopyActionNames(banner, &names)
        if let close = (names as? [String])?.first(where: { $0.hasPrefix("Name:Close") }) {
            AXUIElementPerformAction(banner, close as CFString)
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

    private static func banners(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < 6 else { return [] }
        if string(element, kAXSubroleAttribute) == "AXNotificationCenterBanner" { return [element] }
        return children(element).flatMap { banners(in: $0, depth: depth + 1) }
    }
}
