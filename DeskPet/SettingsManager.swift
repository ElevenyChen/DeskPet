import Foundation
import ServiceManagement

class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let remindersKey = "customReminders"
    private let alarmsKey = "customAlarms"

    var globalMode: GlobalMode {
        get { GlobalMode(rawValue: defaults.integer(forKey: "globalMode")) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "globalMode") }
    }

    var soundEnabled: Bool {
        get { defaults.object(forKey: "soundEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundEnabled") }
    }

    var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.integer(forKey: "appLanguage")) ?? .chinese }
        set { defaults.set(newValue.rawValue, forKey: "appLanguage") }
    }

    var alwaysOnTop: Bool {
        get { defaults.object(forKey: "alwaysOnTop") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alwaysOnTop") }
    }

    var walkingEnabled: Bool {
        get { defaults.object(forKey: "walkingEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "walkingEnabled") }
    }

    var catScale: Double {
        get {
            let v = defaults.double(forKey: "catScale")
            return v > 0 ? v : 1.0
        }
        set { defaults.set(newValue, forKey: "catScale") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at login error: \(error)")
            }
        }
    }

    // MARK: - Custom Reminders

    var reminders: [ReminderItem] {
        get {
            guard let data = defaults.data(forKey: remindersKey),
                  let items = try? JSONDecoder().decode([ReminderItem].self, from: data) else {
                return ReminderItem.defaults
            }
            return items
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: remindersKey)
            }
        }
    }

    func addReminder(_ item: ReminderItem) {
        var list = reminders
        list.append(item)
        reminders = list
    }

    func updateReminder(_ item: ReminderItem) {
        var list = reminders
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list[idx] = item
            reminders = list
        }
    }

    func removeReminder(id: UUID) {
        var list = reminders
        list.removeAll { $0.id == id }
        reminders = list
    }

    func toggleReminder(id: UUID) {
        var list = reminders
        if let idx = list.firstIndex(where: { $0.id == id }) {
            list[idx].enabled.toggle()
            reminders = list
        }
    }

    func effectiveStrength(for strength: ReminderStrength) -> ReminderStrength? {
        switch globalMode {
        case .normal: return strength
        case .quiet: return .soft
        case .superDND: return nil
        }
    }

    // MARK: - Alarms

    var alarms: [AlarmItem] {
        get {
            guard let data = defaults.data(forKey: alarmsKey),
                  let items = try? JSONDecoder().decode([AlarmItem].self, from: data) else {
                return []
            }
            return items
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: alarmsKey)
            }
        }
    }

    func addAlarm(_ item: AlarmItem) {
        var list = alarms
        list.append(item)
        alarms = list
    }

    func updateAlarm(_ item: AlarmItem) {
        var list = alarms
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list[idx] = item
            alarms = list
        }
    }

    func removeAlarm(id: UUID) {
        var list = alarms
        list.removeAll { $0.id == id }
        alarms = list
    }

    func toggleAlarm(id: UUID) {
        var list = alarms
        if let idx = list.firstIndex(where: { $0.id == id }) {
            list[idx].enabled.toggle()
            alarms = list
        }
    }

    func effectiveAlarmStrength(for alarm: AlarmItem) -> ReminderStrength? {
        if globalMode == .superDND { return nil }
        if let override = alarm.strengthOverride { return override }
        return globalMode.strength
    }

    // MARK: - Focus Sessions

    var focusSessions: [FocusSession] {
        get {
            guard let data = defaults.data(forKey: "focusSessions"),
                  let items = try? JSONDecoder().decode([FocusSession].self, from: data) else {
                return []
            }
            return items
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "focusSessions")
            }
        }
    }

    func appendFocusSession(_ session: FocusSession) {
        var list = focusSessions
        list.append(session)
        focusSessions = list
        exportWorkLog(list)
    }

    // Mirror the log to ~/Library/Application Support/DeskPet/worklog.json —
    // outside the repo, so it never gets committed or pushed.
    private func exportWorkLog(_ sessions: [FocusSession]) {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let dir = base.appendingPathComponent("DeskPet", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(sessions) {
            try? data.write(to: dir.appendingPathComponent("worklog.json"))
        }
    }

    var breakPeriods: [BreakPeriod] {
        get {
            guard let data = defaults.data(forKey: "breakPeriods"),
                  let items = try? JSONDecoder().decode([BreakPeriod].self, from: data) else {
                return []
            }
            return items
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "breakPeriods")
            }
        }
    }

    // Preferred work window: a reference for gentle prompts, never automatic clock-in/out
    var workWindowEnabled: Bool {
        get { defaults.object(forKey: "workWindowEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "workWindowEnabled") }
    }

    var workWindowStart: Int {  // minutes since midnight
        get { defaults.object(forKey: "workWindowStart") as? Int ?? 570 }
        set { defaults.set(newValue, forKey: "workWindowStart") }
    }

    var workWindowEnd: Int {
        get { defaults.object(forKey: "workWindowEnd") as? Int ?? 1080 }
        set { defaults.set(newValue, forKey: "workWindowEnd") }
    }

    // Updated every minute while a focus session runs; lets a relaunch tell
    // "just restarted mid-session" apart from "stale session from yesterday"
    var focusHeartbeat: Date? {
        get { defaults.object(forKey: "focusHeartbeat") as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: "focusHeartbeat")
            } else {
                defaults.removeObject(forKey: "focusHeartbeat")
            }
        }
    }

    var dutyPeriods: [DutyPeriod] {
        get {
            guard let data = defaults.data(forKey: "dutyPeriods"),
                  let items = try? JSONDecoder().decode([DutyPeriod].self, from: data) else {
                return []
            }
            return items
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "dutyPeriods")
            }
        }
    }

    var activeFocusSession: FocusSession? {
        get {
            guard let data = defaults.data(forKey: "activeFocusSession"),
                  let item = try? JSONDecoder().decode(FocusSession.self, from: data) else {
                return nil
            }
            return item
        }
        set {
            if let session = newValue, let data = try? JSONEncoder().encode(session) {
                defaults.set(data, forKey: "activeFocusSession")
            } else {
                defaults.removeObject(forKey: "activeFocusSession")
            }
        }
    }
}
