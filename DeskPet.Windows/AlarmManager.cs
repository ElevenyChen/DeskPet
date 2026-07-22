using System.Windows.Threading;

namespace DeskPet;

/// <summary>
/// Port of the macOS AlarmManager: a 15-second tick checks whether the current HH:MM
/// matches any enabled alarm. Each alarm fires at most once per day (tracked in
/// <c>_firedToday</c>, cleared at midnight). Non-repeating alarms auto-disable after
/// firing. Snooze re-fires once after 5 minutes.
/// </summary>
public sealed class AlarmManager
{
    public static readonly AlarmManager Shared = new();

    /// <summary>Raised when an alarm should be shown, with the resolved strength.</summary>
    public event Action<AlarmItem, ReminderStrength>? Triggered;

    private readonly DispatcherTimer _checkTimer = new() { Interval = TimeSpan.FromSeconds(15) };
    private readonly Dictionary<Guid, DispatcherTimer> _snoozeTimers = new();
    private readonly HashSet<Guid> _firedToday = new();
    private readonly SettingsManager _settings = SettingsManager.Shared;
    private int _lastCheckMinute = -1;

    private AlarmManager()
    {
        _checkTimer.Tick += (_, _) => Tick();
    }

    public void Start()
    {
        _checkTimer.Stop();
        _lastCheckMinute = -1;
        _firedToday.Clear();
        _checkTimer.Start();
    }

    /// <summary>Reset firing state (call after adding/editing alarms).</summary>
    public void RebuildAlarms()
    {
        foreach (var t in _snoozeTimers.Values) t.Stop();
        _snoozeTimers.Clear();
        _firedToday.Clear();
    }

    private void Tick()
    {
        var now = DateTime.Now;
        int encoded = now.Hour * 60 + now.Minute;

        // Clear the fired set once at the midnight minute.
        if (encoded == 0 && _lastCheckMinute != 0) _firedToday.Clear();
        _lastCheckMinute = encoded;

        // Snapshot so auto-disabling an alarm mid-loop doesn't mutate the collection we iterate.
        foreach (var alarm in _settings.Alarms.ToList())
        {
            if (!alarm.Enabled) continue;
            if (encoded != alarm.Hour * 60 + alarm.Minute) continue;
            if (_firedToday.Contains(alarm.Id)) continue;

            var strength = _settings.EffectiveAlarmStrength(alarm);
            if (strength is null) continue; // SuperDND

            _firedToday.Add(alarm.Id);

            if (!alarm.RepeatDaily)
            {
                alarm.Enabled = false;
                _settings.UpdateAlarm(alarm);
            }

            Triggered?.Invoke(alarm, strength.Value);
        }
    }

    /// <summary>Re-fire this alarm once, 5 minutes from now.</summary>
    public void Snooze(AlarmItem alarm)
    {
        if (_snoozeTimers.TryGetValue(alarm.Id, out var existing)) existing.Stop();

        var timer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(5) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            _snoozeTimers.Remove(alarm.Id);
            var strength = _settings.EffectiveAlarmStrength(alarm);
            if (strength is not null) Triggered?.Invoke(alarm, strength.Value);
        };
        _snoozeTimers[alarm.Id] = timer;
        timer.Start();
    }
}
