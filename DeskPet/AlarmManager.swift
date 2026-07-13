import Foundation

protocol AlarmManagerDelegate: AnyObject {
    func alarmTriggered(_ alarm: AlarmItem, strength: ReminderStrength)
}

class AlarmManager {
    static let shared = AlarmManager()

    weak var delegate: AlarmManagerDelegate?
    private var checkTimer: Timer?
    private var firedToday: Set<UUID> = []
    private var lastCheckMinute: Int = -1
    private let settings = SettingsManager.shared
    private var snoozeTimers: [UUID: Timer] = [:]

    func start() {
        checkTimer?.invalidate()
        resetFiredIfNewDay()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func rebuildAlarms() {
        snoozeTimers.values.forEach { $0.invalidate() }
        snoozeTimers.removeAll()
        firedToday.removeAll()
    }

    private func tick() {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let encoded = hour * 60 + minute

        if encoded == 0 && lastCheckMinute != 0 {
            firedToday.removeAll()
        }
        lastCheckMinute = encoded

        for alarm in settings.alarms where alarm.enabled {
            let alarmEncoded = alarm.hour * 60 + alarm.minute
            guard encoded == alarmEncoded else { continue }
            guard !firedToday.contains(alarm.id) else { continue }
            guard let strength = settings.effectiveAlarmStrength(for: alarm) else { continue }

            firedToday.insert(alarm.id)

            if !alarm.repeatDaily {
                var updated = alarm
                updated.enabled = false
                settings.updateAlarm(updated)
            }

            DispatchQueue.main.async {
                self.delegate?.alarmTriggered(alarm, strength: strength)
            }
        }
    }

    private func resetFiredIfNewDay() {
        lastCheckMinute = -1
        firedToday.removeAll()
    }

    func snooze(_ alarm: AlarmItem) {
        snoozeTimers[alarm.id]?.invalidate()
        snoozeTimers[alarm.id] = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.snoozeTimers.removeValue(forKey: alarm.id)
            guard let strength = self.settings.effectiveAlarmStrength(for: alarm) else { return }
            DispatchQueue.main.async {
                self.delegate?.alarmTriggered(alarm, strength: strength)
            }
        }
    }
}
