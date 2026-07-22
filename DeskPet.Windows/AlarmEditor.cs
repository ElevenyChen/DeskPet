using System.Windows;
using System.Windows.Controls;

namespace DeskPet;

/// <summary>
/// Add/edit dialog for an alarm — name, message, HH:MM, strength override, repeat-daily,
/// allow-snooze. Windows counterpart to the macOS openAddAlarm / edit alarm NSAlert form.
/// </summary>
public sealed class AlarmEditor : Window
{
    private readonly TextBox _name;
    private readonly TextBox _message;
    private readonly TextBox _hour;
    private readonly TextBox _minute;
    private readonly ComboBox _strength;
    private readonly CheckBox _repeat;
    private readonly CheckBox _snooze;

    private AlarmEditor(AlarmItem? existing)
    {
        Title = existing is null ? Loc.AddAlarmTitle : Loc.EditAlarmTitle;
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        _name = new TextBox { Width = 200, Text = existing?.Name ?? "" };
        _message = new TextBox { Width = 200, Text = existing?.Message ?? "" };
        _hour = new TextBox { Width = 44, Text = (existing?.Hour ?? 9).ToString("D2") };
        _minute = new TextBox { Width = 44, Text = (existing?.Minute ?? 0).ToString("D2") };

        _strength = new ComboBox { Width = 200 };
        _strength.Items.Add(Loc.StrengthFollow);
        _strength.Items.Add(Loc.StrengthSoft);
        _strength.Items.Add(Loc.StrengthStrong);
        _strength.SelectedIndex = existing?.StrengthOverride switch
        {
            ReminderStrength.Soft => 1,
            ReminderStrength.Hard => 2,
            _ => 0,
        };

        _repeat = new CheckBox { Content = Loc.RepeatDaily, IsChecked = existing?.RepeatDaily ?? true };
        _snooze = new CheckBox { Content = Loc.AllowSnooze, IsChecked = existing?.SnoozeEnabled ?? true };

        var time = new StackPanel { Orientation = Orientation.Horizontal };
        time.Children.Add(_hour);
        time.Children.Add(new TextBlock { Text = " : ", VerticalAlignment = VerticalAlignment.Center });
        time.Children.Add(_minute);

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(DialogUI.Row(Loc.FieldName + ":", _name));
        panel.Children.Add(DialogUI.Row(Loc.FieldMessage + ":", _message));
        panel.Children.Add(DialogUI.Row(Loc.FieldTime + ":", time));
        panel.Children.Add(DialogUI.Row(Loc.FieldStrength + ":", _strength));
        panel.Children.Add(DialogUI.Row("", _repeat));
        panel.Children.Add(DialogUI.Row("", _snooze));
        panel.Children.Add(DialogUI.Buttons(this, existing is null ? Loc.Add : Loc.Save));

        Content = panel;
    }

    /// <summary>Returns the edited alarm, or null if cancelled or the name is blank.</summary>
    public static AlarmItem? Show(Window owner, AlarmItem? existing)
    {
        var dlg = new AlarmEditor(existing) { Owner = owner };
        if (dlg.ShowDialog() != true) return null;

        var name = dlg._name.Text.Trim();
        if (name.Length == 0) return null;

        int hour = Math.Clamp(int.TryParse(dlg._hour.Text, out var h) ? h : 9, 0, 23);
        int minute = Math.Clamp(int.TryParse(dlg._minute.Text, out var m) ? m : 0, 0, 59);
        ReminderStrength? strength = dlg._strength.SelectedIndex switch
        {
            1 => ReminderStrength.Soft,
            2 => ReminderStrength.Hard,
            _ => null,
        };

        return new AlarmItem
        {
            Id = existing?.Id ?? Guid.NewGuid(),
            Enabled = existing?.Enabled ?? true,
            Name = name,
            Message = dlg._message.Text.Length == 0 ? $"{name}!" : dlg._message.Text,
            Hour = hour,
            Minute = minute,
            StrengthOverride = strength,
            RepeatDaily = dlg._repeat.IsChecked == true,
            SnoozeEnabled = dlg._snooze.IsChecked == true,
        };
    }
}
