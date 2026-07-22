using System.Windows;
using System.Windows.Controls;

namespace DeskPet;

/// <summary>
/// Add/edit dialog for a reminder — the Windows counterpart to the macOS NSAlert
/// accessory-view form (name, soft message, strong message, interval).
/// </summary>
public sealed class ReminderEditor : Window
{
    private readonly TextBox _name;
    private readonly TextBox _soft;
    private readonly TextBox _strong;
    private readonly TextBox _interval;

    private ReminderEditor(ReminderItem? existing)
    {
        Title = existing is null ? Loc.AddReminderTitle : Loc.EditReminderTitle;
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        _name = new TextBox { Width = 200 };
        _soft = new TextBox { Width = 200 };
        _strong = new TextBox { Width = 200 };
        _interval = new TextBox { Width = 200 };

        _name.Text = existing?.Name ?? "";
        _soft.Text = existing?.ShortMessage ?? "";
        _strong.Text = existing?.UrgentMessage ?? "";
        _interval.Text = (existing?.IntervalMinutes ?? 30).ToString();

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(DialogUI.Row(Loc.FieldName + ":", _name));
        panel.Children.Add(DialogUI.Row(Loc.FieldSoftMsg + ":", _soft));
        panel.Children.Add(DialogUI.Row(Loc.FieldStrongMsg + ":", _strong));
        panel.Children.Add(DialogUI.Row(Loc.FieldIntervalMin + ":", _interval));
        panel.Children.Add(DialogUI.Buttons(this, existing is null ? Loc.Add : Loc.Save));

        Content = panel;
    }

    /// <summary>Returns the edited item, or null if cancelled or the name is blank.</summary>
    public static ReminderItem? Show(Window owner, ReminderItem? existing)
    {
        var dlg = new ReminderEditor(existing) { Owner = owner };
        if (dlg.ShowDialog() != true) return null;

        var name = dlg._name.Text.Trim();
        if (name.Length == 0) return null;

        return new ReminderItem
        {
            Id = existing?.Id ?? Guid.NewGuid(),
            Enabled = existing?.Enabled ?? true,
            Name = name,
            ShortMessage = dlg._soft.Text.Length == 0 ? $"{name}~" : dlg._soft.Text,
            UrgentMessage = dlg._strong.Text.Length == 0 ? $"⚠️ {name}!" : dlg._strong.Text,
            IntervalMinutes = int.TryParse(dlg._interval.Text, out var m) && m > 0
                ? m : existing?.IntervalMinutes ?? 30,
        };
    }
}
