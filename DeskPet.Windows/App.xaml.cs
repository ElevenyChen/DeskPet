using System.Windows;
using System.Windows.Controls;
using H.NotifyIcon;

namespace DeskPet;

public partial class App : Application
{
    private TaskbarIcon? _tray;
    private CatWindow? _cat;
    private BehaviorController? _behavior;
    private ReminderPresenter? _presenter;

    private SettingsManager Settings => SettingsManager.Shared;

    private void OnStartup(object sender, StartupEventArgs e)
    {
        _cat = new CatWindow();
        _cat.Show();

        _behavior = new BehaviorController(_cat);
        _behavior.Start();

        _presenter = new ReminderPresenter(_cat, _behavior);
        ReminderManager.Shared.Triggered += (item, strength) => _presenter.ShowReminder(item, strength);
        AlarmManager.Shared.Triggered += (alarm, strength) => _presenter.ShowAlarm(alarm, strength);

        ReminderManager.Shared.Start();
        AlarmManager.Shared.Start();

        _tray = new TaskbarIcon { ToolTipText = "DeskPet" };
        _tray.ForceCreate();
        RefreshMenu();
    }

    private void RefreshMenu()
    {
        if (_tray is not null) _tray.ContextMenu = BuildMenu();
    }

    private ContextMenu BuildMenu()
    {
        var menu = new ContextMenu();

        // Show / Hide
        var toggle = new MenuItem { Header = Loc.ShowHideCat };
        toggle.Click += (_, _) =>
        {
            if (_cat is null) return;
            if (_cat.IsVisible) _cat.Hide(); else _cat.Show();
        };
        menu.Items.Add(toggle);

        // Mode
        var mode = new MenuItem { Header = Loc.Mode };
        foreach (var m in new[] { GlobalMode.Normal, GlobalMode.Quiet, GlobalMode.SuperDND })
        {
            var mi = new MenuItem
            {
                Header = Loc.ModeName(m),
                IsCheckable = true,
                IsChecked = m == Settings.GlobalMode,
            };
            mi.Click += (_, _) => { if (_behavior is not null) _behavior.Mode = m; RefreshMenu(); };
            mode.Items.Add(mi);
        }
        menu.Items.Add(mode);
        menu.Items.Add(new Separator());

        menu.Items.Add(BuildRemindersMenu());
        menu.Items.Add(BuildAlarmsMenu());
        menu.Items.Add(new Separator());

        // Toggles
        menu.Items.Add(Toggle(Loc.AlwaysOnTop, Settings.AlwaysOnTop, on =>
        {
            Settings.AlwaysOnTop = on;
            _cat?.ApplyAlwaysOnTop();
        }));
        menu.Items.Add(Toggle(Loc.AllowWalking, Settings.WalkingEnabled, on =>
        {
            if (_behavior is not null) _behavior.WalkingEnabled = on;
        }));
        menu.Items.Add(Toggle(Loc.CatSound, Settings.SoundEnabled, on => Settings.SoundEnabled = on));
        menu.Items.Add(Toggle(Loc.LaunchAtLogin, Settings.LaunchAtLogin, on => Settings.LaunchAtLogin = on));
        menu.Items.Add(new Separator());

        menu.Items.Add(BuildSizeSlider());
        menu.Items.Add(new Separator());

        menu.Items.Add(BuildLanguageMenu());
        menu.Items.Add(new Separator());

        menu.Items.Add(BuildPauseMenu());
        menu.Items.Add(new Separator());

        // Test
        var test = new MenuItem { Header = Loc.Test };
        var ts = new MenuItem { Header = Loc.TestSoft };
        ts.Click += (_, _) => _presenter?.TestSoft();
        var th = new MenuItem { Header = Loc.TestStrong };
        th.Click += (_, _) => _presenter?.TestHard();
        test.Items.Add(ts);
        test.Items.Add(th);
        menu.Items.Add(test);
        menu.Items.Add(new Separator());

        var quit = new MenuItem { Header = Loc.Quit };
        quit.Click += (_, _) => Shutdown();
        menu.Items.Add(quit);

        return menu;
    }

    // MARK: - Reminders / Alarms submenus

    private MenuItem BuildRemindersMenu()
    {
        var root = new MenuItem { Header = Loc.Reminders };

        foreach (var item in Settings.Reminders)
        {
            var sub = new MenuItem { Header = $"{item.Name}  ({item.IntervalMinutes} {Loc.MinutesShort})" };

            sub.Items.Add(Toggle(Loc.Enabled, item.Enabled, _ =>
            {
                Settings.ToggleReminder(item.Id);
                ReminderManager.Shared.RebuildTimers();
                RefreshMenu();
            }));

            var edit = new MenuItem { Header = Loc.Edit };
            edit.Click += (_, _) =>
            {
                var updated = ReminderEditor.Show(_cat!, item);
                if (updated is null) return;
                Settings.UpdateReminder(updated);
                ReminderManager.Shared.RebuildTimers();
                RefreshMenu();
            };
            sub.Items.Add(edit);

            var del = new MenuItem { Header = Loc.Delete };
            del.Click += (_, _) =>
            {
                Settings.RemoveReminder(item.Id);
                ReminderManager.Shared.RebuildTimers();
                RefreshMenu();
            };
            sub.Items.Add(del);

            root.Items.Add(sub);
        }

        root.Items.Add(new Separator());
        var add = new MenuItem { Header = Loc.AddReminder };
        add.Click += (_, _) =>
        {
            var created = ReminderEditor.Show(_cat!, null);
            if (created is null) return;
            Settings.AddReminder(created);
            ReminderManager.Shared.RebuildTimers();
            RefreshMenu();
        };
        root.Items.Add(add);
        return root;
    }

    private MenuItem BuildAlarmsMenu()
    {
        var root = new MenuItem { Header = Loc.Alarms };

        foreach (var alarm in Settings.Alarms)
        {
            var tag = alarm.StrengthOverride switch
            {
                ReminderStrength.Hard => Loc.TagStrong,
                ReminderStrength.Soft => Loc.TagSoft,
                _ => Loc.TagSystem,
            };
            var daily = alarm.RepeatDaily ? $", {Loc.TagDaily}" : "";
            var sub = new MenuItem { Header = $"{alarm.Name}  {alarm.TimeString}  [{tag}{daily}]" };

            sub.Items.Add(Toggle(Loc.Enabled, alarm.Enabled, _ =>
            {
                Settings.ToggleAlarm(alarm.Id);
                AlarmManager.Shared.RebuildAlarms();
                RefreshMenu();
            }));

            var edit = new MenuItem { Header = Loc.Edit };
            edit.Click += (_, _) =>
            {
                var updated = AlarmEditor.Show(_cat!, alarm);
                if (updated is null) return;
                Settings.UpdateAlarm(updated);
                AlarmManager.Shared.RebuildAlarms();
                RefreshMenu();
            };
            sub.Items.Add(edit);

            var del = new MenuItem { Header = Loc.Delete };
            del.Click += (_, _) =>
            {
                Settings.RemoveAlarm(alarm.Id);
                AlarmManager.Shared.RebuildAlarms();
                RefreshMenu();
            };
            sub.Items.Add(del);

            root.Items.Add(sub);
        }

        root.Items.Add(new Separator());
        var add = new MenuItem { Header = Loc.AddAlarm };
        add.Click += (_, _) =>
        {
            var created = AlarmEditor.Show(_cat!, null);
            if (created is null) return;
            Settings.AddAlarm(created);
            AlarmManager.Shared.RebuildAlarms();
            RefreshMenu();
        };
        root.Items.Add(add);
        return root;
    }

    // MARK: - Other menu pieces

    private MenuItem BuildSizeSlider()
    {
        var slider = new Slider
        {
            Minimum = 0.5,
            Maximum = 3.0,
            Value = Settings.CatScale,
            Width = 160,
        };
        slider.ValueChanged += (_, ev) =>
        {
            Settings.CatScale = ev.NewValue;
            _cat?.RefreshScale();
        };

        var content = new StackPanel { Margin = new Thickness(4) };
        content.Children.Add(new TextBlock { Text = Loc.CatSize });
        content.Children.Add(slider);

        return new MenuItem { Header = content, StaysOpenOnClick = true };
    }

    private MenuItem BuildLanguageMenu()
    {
        var root = new MenuItem { Header = Loc.Language };
        foreach (var (lang, name) in new[]
                 {
                     (AppLanguage.Chinese, "中文"),
                     (AppLanguage.English, "English"),
                 })
        {
            var mi = new MenuItem
            {
                Header = name,
                IsCheckable = true,
                IsChecked = Settings.Language == lang,
            };
            mi.Click += (_, _) => { Settings.Language = lang; RefreshMenu(); };
            root.Items.Add(mi);
        }
        return root;
    }

    private MenuItem BuildPauseMenu()
    {
        var root = new MenuItem { Header = Loc.Pause };
        foreach (var (label, mins) in new[]
                 {
                     (Loc.Pause30, 30),
                     (Loc.Pause60, 60),
                     (Loc.PauseTomorrow, 1440),
                 })
        {
            var mi = new MenuItem { Header = label };
            mi.Click += (_, _) => ReminderManager.Shared.Pause(mins);
            root.Items.Add(mi);
        }
        root.Items.Add(new Separator());
        var resume = new MenuItem { Header = Loc.ResumeNow };
        resume.Click += (_, _) => ReminderManager.Shared.Resume();
        root.Items.Add(resume);
        return root;
    }

    // A checkable menu item that reports its new state to <paramref name="onToggle"/>.
    private static MenuItem Toggle(string header, bool isChecked, Action<bool> onToggle)
    {
        var mi = new MenuItem { Header = header, IsCheckable = true, IsChecked = isChecked };
        mi.Click += (_, _) => onToggle(mi.IsChecked);
        return mi;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        base.OnExit(e);
    }
}
