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

    static func dragBegan() {
        guard !dragActive else { return }
        dragActive = true
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
