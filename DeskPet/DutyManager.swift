import Foundation

// Tracks the higher-level "on duty / off duty" state, separate from
// individual focus sessions. One DutyPeriod per clock-in; reopening
// work after clocking out starts a new period on the same day.
class DutyManager {
    static let shared = DutyManager()

    private let settings = SettingsManager.shared

    var periods: [DutyPeriod] {
        get { settings.dutyPeriods }
        set { settings.dutyPeriods = newValue }
    }

    var openPeriod: DutyPeriod? {
        periods.last(where: { $0.offDuty == nil })
    }

    var isOnDuty: Bool { openPeriod != nil }

    func periodsOn(day: Date) -> [DutyPeriod] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return periods.filter { $0.onDuty >= start && $0.onDuty < end }.sorted { $0.onDuty < $1.onDuty }
    }

    var hasClockedOutToday: Bool {
        periodsOn(day: Date()).contains { $0.offDuty != nil }
    }

    func clockIn(at date: Date = Date()) {
        guard openPeriod == nil else { return }
        var list = periods
        list.append(DutyPeriod(id: UUID(), onDuty: date, offDuty: nil, offDutyInferred: false))
        periods = list
    }

    func clockOut(at date: Date = Date(), final: Bool = true) {
        endBreak(at: date)
        var list = periods
        guard let idx = list.lastIndex(where: { $0.offDuty == nil }) else { return }
        list[idx].offDuty = max(date, list[idx].onDuty)
        list[idx].offDutyInferred = false
        list[idx].offDutyFinal = final
        periods = list
    }

    // Last clock-out on this day that was declared "done for today"
    func finalClockOut(on day: Date) -> Date? {
        periodsOn(day: day).compactMap { $0.offDutyFinal == true ? $0.offDuty : nil }.max()
    }

    var hasFinalClockOutToday: Bool {
        finalClockOut(on: Date()) != nil
    }

    // Duty blocks started after the day was already declared done —
    // the metric worth watching (vs. normal multi-block days)
    func reopensAfterFinal(on day: Date) -> Int {
        let periods = periodsOn(day: day)
        guard let firstFinalOff = periods.compactMap({ $0.offDutyFinal == true ? $0.offDuty : nil }).min() else { return 0 }
        return periods.filter { $0.onDuty > firstFinalOff }.count
    }

    // An open period left over from a previous day (forgot to clock out)
    func staleOpenPeriod() -> DutyPeriod? {
        guard let open = openPeriod else { return nil }
        return open.onDuty < Calendar.current.startOfDay(for: Date()) ? open : nil
    }

    func close(id: UUID, at date: Date, inferred: Bool) {
        endBreak(at: date)
        var list = periods
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].offDuty = max(date, list[idx].onDuty)
        list[idx].offDutyInferred = inferred
        list[idx].offDutyFinal = true
        periods = list
    }

    // MARK: - Breaks (休息/私人时间, inside the duty envelope)

    var breaks: [BreakPeriod] {
        get { settings.breakPeriods }
        set { settings.breakPeriods = newValue }
    }

    var openBreak: BreakPeriod? {
        breaks.last(where: { $0.end == nil })
    }

    var isOnBreak: Bool { openBreak != nil }

    func startBreak(at date: Date = Date()) {
        guard isOnDuty, openBreak == nil else { return }
        var list = breaks
        list.append(BreakPeriod(id: UUID(), start: date, end: nil))
        breaks = list
    }

    func endBreak(at date: Date = Date()) {
        var list = breaks
        guard let idx = list.lastIndex(where: { $0.end == nil }) else { return }
        list[idx].end = max(date, list[idx].start)
        breaks = list
    }

    func breaksOn(day: Date) -> [BreakPeriod] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return breaks.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
    }
}
