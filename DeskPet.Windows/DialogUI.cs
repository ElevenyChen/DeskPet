using System.Windows;
using System.Windows.Controls;

namespace DeskPet;

/// <summary>Small shared builders for the editor dialogs (labeled rows + OK/Cancel).</summary>
internal static class DialogUI
{
    /// <summary>A left-aligned label followed by an editor control, on one row.</summary>
    public static UIElement Row(string label, UIElement editor)
    {
        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 0, 0, 8),
        };
        row.Children.Add(new TextBlock
        {
            Text = label,
            Width = 120,
            VerticalAlignment = VerticalAlignment.Center,
        });
        row.Children.Add(editor);
        return row;
    }

    /// <summary>
    /// A right-aligned confirm/cancel button pair. Confirm sets DialogResult=true,
    /// cancel is the window's Cancel button.
    /// </summary>
    public static UIElement Buttons(Window owner, string confirmText)
    {
        var confirm = new Button { Content = confirmText, IsDefault = true, Width = 84, Height = 26 };
        confirm.Click += (_, _) => owner.DialogResult = true;

        var cancel = new Button
        {
            Content = Loc.Cancel,
            IsCancel = true,
            Width = 84,
            Height = 26,
            Margin = new Thickness(8, 0, 0, 0),
        };

        return new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 8, 0, 0),
            Children = { confirm, cancel },
        };
    }
}
