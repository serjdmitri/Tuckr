//
//  NotchHold.swift
//  What keeps the notch from closing or resetting: a file being dragged, the lock, and how long
//  a closed notch remembers its tab.
//

import AppKit
import Defaults

@MainActor
enum NotchHold {
    // MARK: Dragging a file

    /// A file is being held. The notch stays open until it is let go, or until it has been
    /// dragged away from the notch for `awayLimit` seconds.
    private(set) static var dragActive = false
    static let awayLimit = 20.0

    private static var awayTask: Task<Void, Never>?
    private static var pollTask: Task<Void, Never>?

    /// A drop reached one of the panels since the drag began; if none did by the time the
    /// button is let go, `releasedWithoutDrop` takes the file instead.
    static var dropHandled = false
    /// The held file is one of the Shelf's own, on its way out: the release is not ours to take.
    static var ownDrag = false
    /// Last place the held file was seen, and what to do with it when no drop arrived.
    static var lastDragPoint = NSPoint.zero
    static var releasedWithoutDrop: @MainActor (NSPoint) -> Void = { _ in }
    private static var moveMonitor: Any?

    static func dragBegan() {
        guard !dragActive else { return }
        dragActive = true
        dropHandled = false
        ownDrag = false
        if moveMonitor == nil {
            moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
                MainActor.assumeIsolated { lastDragPoint = NSEvent.mouseLocation }
            }
        }
        lastDragPoint = NSEvent.mouseLocation
        // The mouse-up of a drag is not always seen by other apps, so watch the button too.
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while dragActive, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if NSEvent.pressedMouseButtons & 1 == 0 { dragEnded(closing: closingAfterRelease); return }
            }
        }
    }

    /// Set by the app: closes the notch the file was dragged to, unless the pointer is on it.
    static var closingAfterRelease: @MainActor () -> Void = {}

    static func dragEntered() { awayTask?.cancel() }

    static func dragLeft(closing: @escaping @MainActor () -> Void) {
        awayTask?.cancel()
        awayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(awayLimit))
            guard !Task.isCancelled, dragActive else { return }
            dragActive = false
            closing()
        }
    }

    static func dragEnded(closing: @escaping @MainActor () -> Void) {
        guard dragActive else { return }
        awayTask?.cancel()
        pollTask?.cancel()
        dragActive = false
        // The panels did not get the drop (something else took the drag): do it from here.
        let point = lastDragPoint
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            if !dropHandled, !ownDrag { releasedWithoutDrop(point) }
        }
        // A drop is handled first (its result shows), then the notch goes if nobody is on it.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            closing()
        }
    }

    // MARK: Lock

    static var locked: Bool { Defaults[.notchLocked] }

    // MARK: Remembering the tab

    private static var forgetTask: Task<Void, Never>?

    /// The notch closed: after the set time the next open starts from Home again.
    static func notchClosed(forget: @escaping @MainActor () -> Void) {
        forgetTask?.cancel()
        let seconds = Defaults[.tabMemorySeconds]
        guard seconds > 0 else { forget(); return }
        forgetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            forget()
        }
    }

    static func notchOpened() { forgetTask?.cancel() }
}
