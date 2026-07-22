using System.Windows.Threading;

namespace DeskPet;

/// <summary>
/// Owns the on-screen reminder lifecycle — the Windows counterpart to the macOS
/// showReminder / showSoftReminder / showHardReminder flow. Pauses the behavior loop
/// (and locks dragging) while a reminder is up, and drives the strong-reminder
/// choreography: walk to center → scale the cat 3× → full-screen blocking overlay.
/// </summary>
public sealed class ReminderPresenter
{
    private readonly CatWindow _cat;
    private readonly BehaviorController _behavior;

    private SoftBubbleWindow? _bubble;
    private OverlayWindow? _overlay;
    private DispatcherTimer? _softDismiss;
    private DispatcherTimer? _snooze;
    private bool _isReminding;

    public ReminderPresenter(CatWindow cat, BehaviorController behavior)
    {
        _cat = cat;
        _behavior = behavior;
    }

    // MARK: - Entry points (wired to the manager Triggered events)

    public void ShowReminder(ReminderItem item, ReminderStrength strength)
    {
        if (_isReminding) return;
        if (strength == ReminderStrength.Soft)
            ShowSoft(item.ShortMessage);
        else
            ShowHard(item.UrgentMessage, showSnooze: true, onSnooze: () => SnoozeReminder(item));
    }

    public void ShowAlarm(AlarmItem alarm, ReminderStrength strength)
    {
        if (_isReminding) return;
        var text = alarm.Message.Length > 0 ? alarm.Message
                 : alarm.Name.Length > 0 ? alarm.Name : alarm.TimeString;
        if (strength == ReminderStrength.Soft)
            ShowSoft(text);
        else
            ShowHard(text, showSnooze: alarm.SnoozeEnabled, onSnooze: () => AlarmManager.Shared.Snooze(alarm));
    }

    // MARK: - Soft

    private void ShowSoft(string message)
    {
        DismissBubble();
        _isReminding = true;
        _behavior.IsReminding = true;

        _bubble = new SoftBubbleWindow(message, _cat);
        _bubble.Show();

        _softDismiss = new DispatcherTimer { Interval = TimeSpan.FromSeconds(8) };
        _softDismiss.Tick += (_, _) => DismissSoft();
        _softDismiss.Start();
    }

    private void DismissSoft()
    {
        DismissBubble();
        _isReminding = false;
        _behavior.IsReminding = false;
    }

    private void DismissBubble()
    {
        _softDismiss?.Stop();
        _softDismiss = null;
        _bubble?.Close();
        _bubble = null;
    }

    // MARK: - Hard

    private void ShowHard(string urgentMessage, bool showSnooze, Action? onSnooze)
    {
        DismissBubble();
        _isReminding = true;
        _behavior.IsReminding = true;
        _cat.DragEnabled = false;

        SoundManager.Shared.PlayRandom(); // cat meow on strong reminder (macOS playRandomSound)

        var center = _cat.ScreenCenterTopLeft();
        _cat.WalkTo(center.X, center.Y, rush: false, onArrive: () =>
        {
            _cat.SetState(CatStates.Reminder);
            _cat.AnimateScale(3.0, steps: 8, intervalMs: 60, onDone: () =>
            {
                _overlay = new OverlayWindow(urgentMessage, _cat, showSnooze);
                _overlay.Dismissed += DismissHard;
                _overlay.Snoozed += () => { DismissHard(); onSnooze?.Invoke(); };
                _overlay.Show();
            });
        });
    }

    private void DismissHard()
    {
        _overlay?.Close();
        _overlay = null;
        _cat.DragEnabled = true;
        _isReminding = false;
        _behavior.IsReminding = false;
        _cat.AnimateScale(1.0, steps: 6, intervalMs: 40, onDone: () => _cat.SetState(CatStates.Idle));
    }

    private void SnoozeReminder(ReminderItem item)
    {
        _snooze?.Stop();
        _snooze = new DispatcherTimer { Interval = TimeSpan.FromMinutes(5) };
        _snooze.Tick += (_, _) =>
        {
            _snooze!.Stop();
            _snooze = null;
            ShowReminder(item, ReminderStrength.Hard);
        };
        _snooze.Start();
    }

    // MARK: - Test hooks (for the tray "Test …" items)

    public void TestSoft() => ShowReminder(
        SettingsManager.Shared.Reminders.FirstOrDefault()
            ?? new ReminderItem { Name = "Test", ShortMessage = "Soft reminder test~", UrgentMessage = "⚠️ Test!" },
        ReminderStrength.Soft);

    public void TestHard() => ShowReminder(
        SettingsManager.Shared.Reminders.FirstOrDefault()
            ?? new ReminderItem { Name = "Test", ShortMessage = "Test~", UrgentMessage = "⚠️ Strong reminder test!" },
        ReminderStrength.Hard);
}
