//
//  NotchTimer.swift
//  boringNotch
//
//  The notch's timer: set minutes on the dial, start, pause, cancel. It never touches
//  Focus or Do Not Disturb. A running timer survives a relaunch.
//

import AppKit
import Combine

@MainActor
final class NotchTimer: ObservableObject {
    static let shared = NotchTimer()

    enum Phase { case idle, running, paused, finished }

    static let minuteRange = 1...120

    /// The minutes on the dial, kept for next time.
    @Published var minutes: Int {
        didSet { UserDefaults.standard.set(minutes, forKey: Keys.minutes) }
    }
    @Published private(set) var phase: Phase = .idle {
        didSet { syncBubble() }
    }
    /// Whole seconds left, published only when the second changes.
    @Published private(set) var secondsLeft = 0

    /// Called when the time runs out, after the chime.
    var onFinished: (() -> Void)?

    private enum Keys {
        static let minutes = "timerMinutes"
        static let end = "timerEndDate"
        static let total = "timerTotalSeconds"
        static let paused = "timerPausedRemaining"
    }

    private var endDate: Date?
    private var total: TimeInterval = 0
    private var pausedRemaining: TimeInterval = 0
    private var ticker: Timer?
    // Kept so the sound is not released while it plays.
    private var chime: NSSound?
    private var chimeTask: Task<Void, Never>?

    private init() {
        let saved = UserDefaults.standard.integer(forKey: Keys.minutes)
        minutes = Self.minuteRange.contains(saved) ? saved : 25
        restore()
        syncBubble()
    }

    /// Running or paused: the closed notch shows it.
    var isActive: Bool { phase == .running || phase == .paused }

    /// Seconds that have passed since the start, for the stopwatch hand.
    var elapsedSeconds: Int { max(0, Int(total) - secondsLeft) }

    private func syncBubble() {
        // The bubble stays through "Time's up", so the alarm can always be reached.
        if phase != .idle { BubbleDock.shared.show("timer") } else { BubbleDock.shared.hide("timer") }
    }

    /// Fraction of the time still left, 1 at the start and 0 at the end.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(secondsLeft) / total))
    }

    func start() {
        chimeTask?.cancel()
        total = TimeInterval(minutes * 60)
        endDate = Date().addingTimeInterval(total)
        secondsLeft = Int(total)
        phase = .running
        save()
        startTicker()
    }

    func pause() {
        guard phase == .running, let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        phase = .paused
        stopTicker()
        clearSaved()
        // A paused timer survives a relaunch too.
        UserDefaults.standard.set(pausedRemaining, forKey: Keys.paused)
        UserDefaults.standard.set(total, forKey: Keys.total)
    }

    func resume() {
        guard phase == .paused else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        UserDefaults.standard.removeObject(forKey: Keys.paused)
        phase = .running
        save()
        startTicker()
    }

    /// Stops the timer and goes back to the dial.
    func cancel() {
        silence()
        stopTicker()
        clearSaved()
        endDate = nil
        phase = .idle
        secondsLeft = 0
    }

    /// Time's up acknowledged.
    func dismiss() { cancel() }

    /// The system's Glass sound, over and over until the timer is dismissed or restarted,
    /// or the alarm is silenced. It gives up by itself after half an hour.
    private func playChime() {
        chimeTask?.cancel()
        chimeTask = Task { @MainActor [weak self] in
            for _ in 0..<1300 {
                guard let self, !Task.isCancelled else { return }
                let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: true)
                self.chime = sound
                if sound?.play() != true { NSSound.beep() }
                try? await Task.sleep(for: .seconds(1.4))
            }
        }
    }

    /// Stops the sound but leaves the "Time's up" page as it is.
    func silence() {
        chimeTask?.cancel()
        chime?.stop()
    }

    /// Time's up and still sounding or waiting to be dismissed.
    var isFinished: Bool { phase == .finished }

    // MARK: - Ticking

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let endDate else { return }
        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            finish()
            return
        }
        let seconds = Int(remaining.rounded(.up))
        if seconds != secondsLeft { secondsLeft = seconds }
    }

    private func finish() {
        stopTicker()
        clearSaved()
        endDate = nil
        secondsLeft = 0
        phase = .finished
        playChime()
        onFinished?()
    }

    // MARK: - Surviving a relaunch

    private func save() {
        guard let endDate else { return }
        UserDefaults.standard.set(endDate, forKey: Keys.end)
        UserDefaults.standard.set(total, forKey: Keys.total)
    }

    private func clearSaved() {
        UserDefaults.standard.removeObject(forKey: Keys.end)
        UserDefaults.standard.removeObject(forKey: Keys.total)
        UserDefaults.standard.removeObject(forKey: Keys.paused)
    }

    private func restore() {
        let pausedLeft = UserDefaults.standard.double(forKey: Keys.paused)
        if pausedLeft > 0 {
            total = UserDefaults.standard.double(forKey: Keys.total)
            pausedRemaining = pausedLeft
            secondsLeft = Int(pausedLeft.rounded(.up))
            phase = .paused
            return
        }
        guard let end = UserDefaults.standard.object(forKey: Keys.end) as? Date,
            end.timeIntervalSinceNow > 0
        else {
            clearSaved()
            return
        }
        total = UserDefaults.standard.double(forKey: Keys.total)
        endDate = end
        secondsLeft = Int(end.timeIntervalSinceNow.rounded(.up))
        phase = .running
        startTicker()
    }
}

/// "5:07" or "1:05:07".
func timerText(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}
