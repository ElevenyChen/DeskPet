import Foundation

protocol FocusManagerDelegate: AnyObject {
    func focusSessionTimeUp(_ session: FocusSession)
}

class FocusManager {
    static let shared = FocusManager()

    weak var delegate: FocusManagerDelegate?
    private let settings = SettingsManager.shared
    private var endTimer: Timer?
    private var heartbeatTimer: Timer?

    private(set) var currentSession: FocusSession? {
        didSet { settings.activeFocusSession = currentSession }
    }

    // If the app was quit mid-session, pick the session back up. A planned
    // session whose time already passed while quit gets logged at its planned end.
    func restoreOnLaunch() {
        guard let session = settings.activeFocusSession else { return }
        let heartbeat = max(settings.focusHeartbeat ?? session.start, session.start)

        // Planned session whose time ran out while the app was closed:
        // log it ending at the planned end (or earlier, if the app died before that)
        if let planned = session.plannedMinutes {
            let plannedEnd = session.start.addingTimeInterval(TimeInterval(planned * 60))
            if Date() >= plannedEnd {
                var finished = session
                finished.end = min(plannedEnd, max(heartbeat, session.start))
                settings.appendFocusSession(finished)
                settings.activeFocusSession = nil
                settings.focusHeartbeat = nil
                return
            }
        }

        // Only continue the session if the app was gone briefly (quick restart).
        // A stale session (quit yesterday, shutdown...) gets closed at its last
        // heartbeat and logged, instead of silently resurrecting on every launch.
        if Date().timeIntervalSince(heartbeat) > 10 * 60 {
            var finished = session
            finished.end = heartbeat
            settings.appendFocusSession(finished)
            settings.activeFocusSession = nil
            settings.focusHeartbeat = nil
            return
        }

        currentSession = session
        scheduleEndTimer()
        startHeartbeat()
    }

    func start(category: WorkCategory, plannedMinutes: Int?, note: String) {
        stop()
        currentSession = FocusSession(
            id: UUID(),
            category: category,
            start: Date(),
            end: nil,
            plannedMinutes: plannedMinutes,
            note: note
        )
        scheduleEndTimer()
        startHeartbeat()
    }

    // Ends and logs the current session — always logged, however short.
    @discardableResult
    func stop(at endDate: Date = Date()) -> FocusSession? {
        endTimer?.invalidate()
        endTimer = nil
        guard var session = currentSession else { return nil }
        session.end = endDate
        settings.appendFocusSession(session)
        currentSession = nil
        stopHeartbeat()
        return session
    }

    func cancel() {
        endTimer?.invalidate()
        endTimer = nil
        currentSession = nil
        stopHeartbeat()
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        settings.focusHeartbeat = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.settings.focusHeartbeat = Date()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        settings.focusHeartbeat = nil
    }

    private func scheduleEndTimer() {
        endTimer?.invalidate()
        endTimer = nil
        guard let session = currentSession, let planned = session.plannedMinutes else { return }
        let fireDate = session.start.addingTimeInterval(TimeInterval(planned * 60))
        let interval = max(1, fireDate.timeIntervalSinceNow)
        endTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if let finished = self.stop() {
                DispatchQueue.main.async {
                    self.delegate?.focusSessionTimeUp(finished)
                }
            }
        }
        if let timer = endTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
