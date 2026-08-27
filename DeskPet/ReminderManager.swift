import Foundation

protocol ReminderManagerDelegate: AnyObject {
    func reminderTriggered(_ item: ReminderItem, strength: ReminderStrength)
}

class ReminderManager {
    static let shared = ReminderManager()

    weak var delegate: ReminderManagerDelegate?
    private var timers: [UUID: Timer] = [:]
    private var nextFires: [UUID: Date] = [:]
    private var intervals: [UUID: TimeInterval] = [:]
    private var pauseUntil: Date?
    private let settings = SettingsManager.shared

    func start() {
        rebuildTimers()
    }

    func rebuildTimers() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        nextFires.removeAll()
        intervals.removeAll()
        for item in settings.reminders where item.enabled {
            let interval = TimeInterval(item.intervalMinutes * 60)
            let itemID = item.id
            timers[itemID] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.fire(itemID: itemID)
            }
            if let timer = timers[itemID] {
                RunLoop.main.add(timer, forMode: .common)
            }
            intervals[itemID] = interval
            nextFires[itemID] = Date().addingTimeInterval(interval)
        }
    }

    // Self-maintained schedule: a Timer that missed its window (sleep/wake,
    // long modal) leaves fireDate in the past — roll forward for display.
    var nextFireDate: Date? {
        let now = Date()
        var best: Date?
        for (id, date) in nextFires {
            var d = date
            if let interval = intervals[id], interval > 0 {
                while d <= now { d += interval }
            }
            if best == nil || d < best! { best = d }
        }
        return best
    }

    func pause(minutes: Int) {
        pauseUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func resume() {
        pauseUntil = nil
    }

    private var isPaused: Bool {
        guard let until = pauseUntil else { return false }
        if Date() > until {
            pauseUntil = nil
            return false
        }
        return true
    }

    private func fire(itemID: UUID) {
        if let interval = intervals[itemID] {
            nextFires[itemID] = Date().addingTimeInterval(interval)
        }
        guard !isPaused else { return }
        guard let item = settings.reminders.first(where: { $0.id == itemID }),
              item.enabled else { return }
        guard let strength = settings.globalMode.strength else { return }

        DispatchQueue.main.async {
            self.delegate?.reminderTriggered(item, strength: strength)
        }
    }
}
