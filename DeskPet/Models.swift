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
    case attacking
    case playing
    case chasingTail
    case bellyUp
    case grooming
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

enum ReminderStrength: Int, Codable {
    case soft = 0
    case hard = 1
}

struct AlarmItem: Codable, Identifiable {
    var id: UUID
    var name: String
    var message: String
    var hour: Int
    var minute: Int
    var strengthOverride: ReminderStrength?
    var repeatDaily: Bool
    var weekdays: [Int]? = nil  // Calendar weekday numbers (1=Sun...7=Sat); nil = legacy repeatDaily semantics
    var snoozeEnabled: Bool
    var enabled: Bool

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    // Empty = one-time alarm (auto-disables after firing)
    var effectiveWeekdays: [Int] {
        if let days = weekdays { return days }
        return repeatDaily ? Array(1...7) : []
    }

    func weekdaysLabel(lang: AppLanguage) -> String {
        let days = effectiveWeekdays
        if days.isEmpty { return lang == .english ? "once" : "一次" }
        if days.count == 7 { return lang == .english ? "daily" : "每天" }
        let order = [2, 3, 4, 5, 6, 7, 1]
        let namesZH = ["日", "一", "二", "三", "四", "五", "六"]
        let namesEN = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sel = order.filter { days.contains($0) }
        if lang == .english { return sel.map { namesEN[$0 - 1] }.joined(separator: "·") }
        return "周" + sel.map { namesZH[$0 - 1] }.joined(separator: "·")
    }
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

enum WorkCategory: Int, Codable, CaseIterable {
    case deepWork = 0
    case admin = 1
    case meeting = 5
    case planning = 2
    case maintenance = 3
    case chores = 4

    // Chores are tracked but excluded from "total work time"
    var countsAsWork: Bool { self != .chores }

    var emoji: String {
        switch self {
        case .deepWork: return "🧠"
        case .admin: return "📮"
        case .meeting: return "👥"
        case .planning: return "🗺️"
        case .maintenance: return "🔧"
        case .chores: return "🧺"
        }
    }

    func displayName(lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.deepWork, .chinese): return "深度工作"
        case (.admin, .chinese): return "行政协调"
        case (.meeting, .chinese): return "会议"
        case (.planning, .chinese): return "规划准备"
        case (.maintenance, .chinese): return "维护整理"
        case (.chores, .chinese): return "生活杂务"
        case (.deepWork, .english): return "Deep Work"
        case (.admin, .english): return "Admin / Coordination"
        case (.meeting, .english): return "Meetings"
        case (.planning, .english): return "Planning / Prep"
        case (.maintenance, .english): return "Maintenance"
        case (.chores, .english): return "Chores"
        }
    }
}

struct FocusSession: Codable, Identifiable {
    var id: UUID
    var category: WorkCategory
    var start: Date
    var end: Date?
    var plannedMinutes: Int?  // nil = free mode, ended manually
    var note: String

    var durationMinutes: Int {
        let effectiveEnd = end ?? Date()
        return max(0, Int(effectiveEnd.timeIntervalSince(start) / 60.0 + 0.5))
    }
}

struct DutyPeriod: Codable, Identifiable {
    var id: UUID
    var onDuty: Date
    var offDuty: Date?
    var offDutyInferred: Bool  // true when clock-out time was estimated after a forgotten clock-out
    var offDutyFinal: Bool? = nil  // true = declared "done for today"; false/nil = stepping out, may return
}

// A break/personal block inside the duty envelope: counts toward duty span, not actual work
struct BreakPeriod: Codable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date?
}

// Coarse post-hoc labels for auto-tracked work stretches (state-first tracking).
// Asked lightly at Break / Clock-out — never while working. Default Mixed.
enum WorkKind: Int, Codable, CaseIterable {
    case mixed = 0
    case research = 1
    case admin = 2
    case teaching = 3
    case other = 4
    case tbd = 5

    var emoji: String {
        switch self {
        case .mixed: return "🌀"
        case .research: return "📚"
        case .admin: return "📮"
        case .teaching: return "🧑‍🏫"
        case .other: return "📦"
        case .tbd: return "❓"
        }
    }

    func displayName(lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.mixed, .chinese): return "混合 / 统筹"
        case (.research, .chinese): return "研究 / 写作"
        case (.admin, .chinese): return "行政事务"
        case (.teaching, .chinese): return "教学"
        case (.other, .chinese): return "其他"
        case (.tbd, .chinese): return "待定"
        case (.mixed, .english): return "Mixed / Orchestration"
        case (.research, .english): return "Research / Writing"
        case (.admin, .english): return "Admin"
        case (.teaching, .english): return "Teaching"
        case (.other, .english): return "Other"
        case (.tbd, .english): return "TBD"
        }
    }
}

// One auto-tracked stretch of active work: clock-in/resume → break/clock-out
struct WorkSegment: Codable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    var kind: WorkKind
    var note: String

    var durationMinutes: Int {
        max(0, Int(end.timeIntervalSince(start) / 60.0 + 0.5))
    }
}
