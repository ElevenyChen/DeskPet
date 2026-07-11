import Foundation

protocol ReminderManagerDelegate: AnyObject {
    func reminderTriggered(_ item: ReminderItem, strength: ReminderStrength)
}

class ReminderManager {
    static let shared = ReminderManager()

    weak var delegate: ReminderManagerDelegate?
    private var timers: [UUID: Timer] = [:]
    private var pauseUntil: Date?
    private let settings = SettingsManager.shared

    func start() {
        rebuildTimers()
    }

    func rebuildTimers() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        for item in settings.reminders where item.enabled {
            let interval = TimeInterval(item.intervalMinutes * 60)
            let itemID = item.id
            timers[itemID] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.fire(itemID: itemID)
            }
        }
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
        guard !isPaused else { return }
        guard let item = settings.reminders.first(where: { $0.id == itemID }),
              item.enabled else { return }
        guard let strength = settings.globalMode.strength else { return }

        DispatchQueue.main.async {
            self.delegate?.reminderTriggered(item, strength: strength)
        }
    }
}
