import Foundation
import ServiceManagement

class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let remindersKey = "customReminders"

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
}
