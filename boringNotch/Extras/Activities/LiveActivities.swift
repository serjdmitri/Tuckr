//
//  LiveActivities.swift
//  Things that happen on the Mac, said in the notch's popup: an event about to start, a
//  download finished, an AirDrop received. Each can be switched off in Settings → Activities.
//

import AppKit
import Defaults
import EventKit

extension NotificationFeed {
    /// A popup that is not a message: it never goes on the Messages list.
    func activity(
        appID: String, name: String, title: String, body: String, symbol: String? = nil,
        openURL: URL? = nil, revealURL: URL? = nil
    ) {
        announce(NotificationItem(
            id: 0, appID: appID, appName: name, title: title, subtitle: "", body: body, date: Date(), thread: "",
            openURL: openURL, symbol: symbol, revealURL: revealURL))
    }
}

// MARK: - Upcoming events

/// "Starts in 5 min": a popup shortly before a calendar event.
@MainActor
final class UpcomingEvents {
    static let shared = UpcomingEvents()

    private let store = EKEventStore()
    private var announced = Set<String>()
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { UpcomingEvents.shared.check() }
        }
        check()
    }

    private func check() {
        guard Defaults[.activityEvents] else { return }
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return }
        let lead = Double(max(1, Defaults[.activityEventLead])) * 60
        let now = Date()
        let selected = CalendarManager.shared.selectedCalendarIDs
        let calendars = store.calendars(for: .event).filter { selected.isEmpty || selected.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return }
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(lead + 60), calendars: calendars))
        for event in events where !event.isAllDay && event.startDate > now && event.startDate.timeIntervalSince(now) <= lead {
            // Not one the person has said no to.
            if event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) == true { continue }
            let key = "\(event.eventIdentifier ?? event.title ?? "")|\(event.startDate.timeIntervalSince1970)"
            guard announced.insert(key).inserted else { continue }
            let minutes = max(1, Int((event.startDate.timeIntervalSince(now) / 60).rounded(.up)))
            var line = "In \(minutes) min · " + event.startDate.formatted(date: .omitted, time: .shortened)
            if let place = event.location, !place.isEmpty, URL(string: place)?.scheme == nil { line += " · \(place)" }
            NotificationFeed.shared.activity(
                appID: "com.apple.ical", name: "Calendar", title: event.title ?? "Event", body: line,
                openURL: Self.meetingLink(event))
        }
        if announced.count > 200 { announced.removeAll() }
    }

    /// A video-call link in the event, so a click joins it.
    private static func meetingLink(_ event: EKEvent) -> URL? {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com"]
        let candidates = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in candidates {
            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { break }
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let url = match.url, hosts.contains(where: { url.host?.hasSuffix($0) == true }) { return url }
            }
        }
        return nil
    }
}

// MARK: - Downloads and AirDrop

/// Watches Downloads for a file that has just arrived from a browser or AirDrop. Both mark what
/// they bring with a "quarantine" flag; a file you copied there yourself has none.
@MainActor
final class DownloadsWatcher {
    static let shared = DownloadsWatcher()

    private let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    private var known = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?
    private static let partial = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    func start() {
        guard source == nil else { return }
        known = Set(listing())
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        watcher.setEventHandler { MainActor.assumeIsolated { DownloadsWatcher.shared.changed() } }
        watcher.setCancelHandler { close(fd) }
        watcher.resume()
        source = watcher
    }

    private func listing() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private func changed() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled else { return }
            let now = Set(self.listing())
            let arrived = now.subtracting(self.known)
            self.known = now
            for name in arrived { await self.consider(name) }
        }
    }

    private func consider(_ name: String) async {
        let url = folder.appendingPathComponent(name)
        guard !name.hasPrefix("."), !Self.partial.contains(url.pathExtension.lowercased()) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return }
        // Wait until it has stopped growing.
        var size = -1
        for _ in 0..<10 {
            let now = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if now == size && now > 0 { break }
            size = now
            try? await Task.sleep(for: .milliseconds(800))
        }
        guard let agent = Self.quarantineAgent(url) else { return }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        if agent.lowercased().contains("sharingd") {
            guard Defaults[.activityAirDrop] else { return }
            NotificationFeed.shared.activity(
                appID: "com.apple.finder", name: "AirDrop", title: name, body: "Received by AirDrop · \(bytes)",
                symbol: "dot.radiowaves.up.forward", revealURL: url)
        } else {
            guard Defaults[.activityDownloads] else { return }
            NotificationFeed.shared.activity(
                appID: "com.apple.finder", name: "Downloads", title: name, body: "Download finished · \(bytes)",
                symbol: "arrow.down.circle.fill", revealURL: url)
        }
    }

    /// Who put the quarantine flag on the file ("sharingd" for AirDrop, a browser's name for a
    /// download); nil when the file has none.
    private static func quarantineAgent(_ url: URL) -> String? {
        let name = "com.apple.quarantine"
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(url.path, name, &buffer, length, 0, 0) == length,
              let value = String(bytes: buffer, encoding: .utf8) else { return nil }
        // flags;timestamp;agent;uuid
        let parts = value.split(separator: ";", omittingEmptySubsequences: false)
        return parts.count > 2 ? String(parts[2]) : ""
    }
}
