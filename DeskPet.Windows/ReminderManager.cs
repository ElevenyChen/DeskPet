using System.Windows.Threading;

namespace DeskPet;

/// <summary>
/// Port of the macOS ReminderManager: one repeating timer per enabled reminder,
/// firing at its interval. Strength is not stored on the item — it's decided by the
/// current global mode at fire time (null strength = SuperDND, so nothing fires).
/// Uses DispatcherTimer so <see cref="Triggered"/> is raised on the UI thread.
/// </summary>
public sealed class ReminderManager
{
    public static readonly ReminderManager Shared = new();

    /// <summary>Raised when a reminder should be shown, with the resolved strength.</summary>
    public event Action<ReminderItem, ReminderStrength>? Triggered;

    private readonly Dictionary<Guid, DispatcherTimer> _timers = new();
    private readonly SettingsManager _settings = SettingsManager.Shared;
    private DateTime? _pauseUntil;

    private ReminderManager() { }

    public void Start() => RebuildTimers();

    /// <summary>Recreate all timers from the current enabled reminders. Call after edits.</summary>
    public void RebuildTimers()
    {
        foreach (var t in _timers.Values) t.Stop();
        _timers.Clear();

        foreach (var item in _settings.Reminders)
        {
            if (!item.Enabled) continue;
            var id = item.Id;
            var timer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMinutes(item.IntervalMinutes),
            };
            timer.Tick += (_, _) => Fire(id);
            timer.Start();
            _timers[id] = timer;
        }
    }

    public void Pause(int minutes) => _pauseUntil = DateTime.Now.AddMinutes(minutes);

    public void Resume() => _pauseUntil = null;

    private bool IsPaused
    {
        get
        {
            if (_pauseUntil is null) return false;
            if (DateTime.Now > _pauseUntil) { _pauseUntil = null; return false; }
            return true;
        }
    }

    private void Fire(Guid id)
    {
        if (IsPaused) return;

        // Re-read the item — it may have been edited/disabled since the timer was made.
        var item = _settings.Reminders.Find(r => r.Id == id);
        if (item is null || !item.Enabled) return;

        var strength = _settings.GlobalMode.Strength();
        if (strength is null) return; // SuperDND

        Triggered?.Invoke(item, strength.Value);
    }
}
