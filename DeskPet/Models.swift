import Foundation

enum CatState: String {
    case idle
    case sleeping
    case lyingDown
    case walkingRight
    case walkingLeft
    case lookingOut
    case watchingUser
    case reminder
    case dragged
    case clicked
}

struct ReminderItem: Codable, Identifiable {
    var id: UUID
    var name: String
    var shortMessage: String
    var urgentMessage: String
    var intervalMinutes: Int
    var enabled: Bool

    static let defaults: [ReminderItem] = [
        ReminderItem(id: UUID(), name: "喝水", shortMessage: "喝口水吧~", urgentMessage: "⚠️ 快喝水！", intervalMinutes: 30, enabled: true),
        ReminderItem(id: UUID(), name: "休息眼睛", shortMessage: "眼睛休息一下", urgentMessage: "⚠️ 休息眼睛！", intervalMinutes: 25, enabled: true),
    ]

    static let defaultsEN: [ReminderItem] = [
        ReminderItem(id: UUID(), name: "Drink Water", shortMessage: "Time for water~", urgentMessage: "⚠️ Drink water!", intervalMinutes: 30, enabled: true),
        ReminderItem(id: UUID(), name: "Rest Eyes", shortMessage: "Rest your eyes", urgentMessage: "⚠️ Rest your eyes!", intervalMinutes: 25, enabled: true),
    ]
}

enum ReminderStrength: Int {
    case soft = 0
    case hard = 1
}

enum AppLanguage: Int, CaseIterable {
    case chinese = 0
    case english = 1

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

enum GlobalMode: Int, CaseIterable {
    case normal = 0
    case quiet = 1
    case superDND = 2

    func displayName(lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.normal, .chinese): return "正常模式（强提醒）"
        case (.quiet, .chinese): return "安静模式（软提醒）"
        case (.superDND, .chinese): return "超级免打扰"
        case (.normal, .english): return "Normal (strong)"
        case (.quiet, .english): return "Quiet (soft)"
        case (.superDND, .english): return "Super DND"
        }
    }

    var strength: ReminderStrength? {
        switch self {
        case .normal: return .hard
        case .quiet: return .soft
        case .superDND: return nil
        }
    }
}
