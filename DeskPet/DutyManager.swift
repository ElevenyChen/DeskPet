import Foundation

// Tracks the higher-level "on duty / off duty" state, separate from
// individual focus sessions. One DutyPeriod per clock-in; reopening
// work after clocking out starts a new period on the same day.
class DutyManager {
    static let shared = DutyManager()

    private let settings = SettingsManager.shared

    // A "workday" runs 05:00 → 05:00 next morning: anything before 5am still
    // belongs to the previous evening's day (跨夜加班算前一天).
    static let dayCutoffHour = 5

    static func workdayKey(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date.addingTimeInterval(-TimeInterval(dayCutoffHour * 3600)))
    }

    static func workdayInterval(containing date: Date) -> DateInterval {
        let start = workdayKey(for: date).addingTimeInterval(TimeInterval(dayCutoffHour * 3600))
        return DateInterval(start: start, duration: 86400)
    }

    var periods: [DutyPeriod] {
        get { settings.dutyPeriods }
        set { settings.dutyPeriods = newValue }
    }

    var openPeriod: DutyPeriod? {
        periods.last(where: { $0.offDuty == nil })
    }

    var isOnDuty: Bool { openPeriod != nil }

    func periodsOn(day: Date) -> [DutyPeriod] {
        let interval = DutyManager.workdayInterval(containing: day)
        return periods.filter { $0.onDuty >= interval.start && $0.onDuty < interval.end }.sorted { $0.onDuty < $1.onDuty }
    }

    var hasClockedOutToday: Bool {
        periodsOn(day: Date()).contains { $0.offDuty != nil }
    }

    func clockIn(at date: Date = Date()) {
        guard openPeriod == nil else { return }
        var list = periods
        list.append(DutyPeriod(id: UUID(), onDuty: date, offDuty: nil, offDutyInferred: false))
        periods = list
        if stretchStart == nil { stretchStart = date }
    }

    func clockOut(at date: Date = Date(), final: Bool = true) {
        endBreak(at: date)
        closeStretch(at: date, kind: .mixed)  // safety net; callers label first
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

    // An open period left over from a previous workday (forgot to clock out)
    func staleOpenPeriod() -> DutyPeriod? {
        guard let open = openPeriod else { return nil }
        return DutyManager.workdayKey(for: open.onDuty) < DutyManager.workdayKey(for: Date()) ? open : nil
    }

    func close(id: UUID, at date: Date, inferred: Bool) {
        endBreak(at: date)
        if let start = stretchStart, start < date {
            closeStretch(at: date, kind: .mixed)
        } else {
            stretchStart = nil
        }
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
        closeStretch(at: date, kind: .mixed)  // safety net; callers label first
        var list = breaks
        list.append(BreakPeriod(id: UUID(), start: date, end: nil))
        breaks = list
    }

    // The whole "break" was actually work: drop the record and let the
    // running stretch start where the break began
    func convertOpenBreakToWork() {
        guard let brk = openBreak else { return }
        var list = breaks
        list.removeAll { $0.id == brk.id }
        breaks = list
        stretchStart = brk.start
    }

    // Retro-insert a break (e.g. confirmed idle time)
    func insertBreak(from: Date, to: Date) {
        var list = breaks
        list.append(BreakPeriod(id: UUID(), start: from, end: max(to, from)))
        breaks = list
    }

    func endBreak(at date: Date = Date()) {
        var list = breaks
        guard let idx = list.lastIndex(where: { $0.end == nil }) else { return }
        list[idx].end = max(date, list[idx].start)
        breaks = list
    }

    func breaksOn(day: Date) -> [BreakPeriod] {
        let interval = DutyManager.workdayInterval(containing: day)
        return breaks.filter { $0.start >= interval.start && $0.start < interval.end }.sorted { $0.start < $1.start }
    }

    // MARK: - Active stretch (state-first: clock in → work accumulates by itself)

    var stretchStart: Date? {
        get { settings.activeStretchStart }
        set { settings.activeStretchStart = newValue }
    }

    var segments: [WorkSegment] { settings.workSegments }

    func segmentsOn(day: Date) -> [WorkSegment] {
        let interval = DutyManager.workdayInterval(containing: day)
        return segments.filter { $0.start >= interval.start && $0.start < interval.end }.sorted { $0.start < $1.start }
    }

    @discardableResult
    func closeStretch(at date: Date = Date(), kind: WorkKind, note: String = "") -> WorkSegment? {
        guard let start = stretchStart else { return nil }
        let segment = WorkSegment(id: UUID(), start: start, end: max(date, start), kind: kind, note: note)
        settings.appendWorkSegment(segment)
        stretchStart = nil
        return segment
    }

    // Active work = closed segments + the currently running stretch
    func activeWorkMinutes(on day: Date) -> Int {
        var total = segmentsOn(day: day).reduce(0) { $0 + $1.durationMinutes }
        if let start = stretchStart, DutyManager.workdayKey(for: start) == DutyManager.workdayKey(for: day) {
            total += max(0, Int(Date().timeIntervalSince(start) / 60))
        }
        return total
    }

    // A stretch left running from a previous app run: close it at the last
    // heartbeat instead of counting hours nobody worked.
    func reconcileStretchOnLaunch() {
        if let start = stretchStart {
            let heartbeat = max(settings.workHeartbeat ?? start, start)
            if Date().timeIntervalSince(heartbeat) > 10 * 60 {
                closeStretch(at: heartbeat, kind: .mixed)
            }
        }
        // On duty but no stretch running (migration / recovery): start counting now
        if stretchStart == nil, isOnDuty, !isOnBreak {
            stretchStart = Date()
        }
    }
}
