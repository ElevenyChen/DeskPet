using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace DeskPet;

/// <summary>
/// Strong reminder: a full-screen 40%-black dim with a white card below the cat holding
/// the urgent message, a "Got it!" button, and (optionally) a 5-minute snooze button.
/// The user must click a button to leave. Port of the macOS showBlockingOverlay + OverlayWindow.
/// </summary>
public sealed class OverlayWindow : Window
{
    /// <summary>Raised when the user acknowledges ("Got it!" or ESC).</summary>
    public event Action? Dismissed;
    /// <summary>Raised when the user chooses "Remind in 5 min".</summary>
    public event Action? Snoozed;

    private const double CardW = 360;
    private const double CardH = 180;

    public OverlayWindow(string urgentMessage, CatWindow cat, bool showSnooze)
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = new SolidColorBrush(Color.FromArgb(102, 0, 0, 0)); // black @ 0.4
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        WindowState = WindowState.Maximized; // borderless maximized covers the whole monitor

        var canvas = new Canvas();

        var card = new Border
        {
            Width = CardW,
            Height = CardH,
            Background = Brushes.White,
            CornerRadius = new CornerRadius(16),
            Effect = new DropShadowEffect { BlurRadius = 20, ShadowDepth = 2, Opacity = 0.3, Direction = 270 },
        };

        var stack = new StackPanel
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };

        stack.Children.Add(new TextBlock
        {
            Text = urgentMessage,
            FontSize = 24,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.Black,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = CardW - 40,
            Margin = new Thickness(0, 0, 0, 18),
        });

        var got = new Button
        {
            Content = "Got it!",
            Width = 200,
            Height = 40,
            FontSize = 16,
            FontWeight = FontWeights.Medium,
            Foreground = Brushes.White,
            Background = new SolidColorBrush(Color.FromRgb(51, 128, 255)), // 0.2/0.5/1.0
            BorderThickness = new Thickness(0),
            Cursor = Cursors.Hand,
        };
        got.Click += (_, _) => Finish(Dismissed);
        stack.Children.Add(got);

        if (showSnooze)
        {
            var later = new Button
            {
                Content = "Remind in 5 min",
                Width = 200,
                Height = 30,
                FontSize = 13,
                Foreground = Brushes.DimGray,
                Background = new SolidColorBrush(Color.FromRgb(235, 235, 235)),
                BorderThickness = new Thickness(0),
                Cursor = Cursors.Hand,
                Margin = new Thickness(0, 10, 0, 0),
            };
            later.Click += (_, _) => Finish(Snoozed);
            stack.Children.Add(later);
        }

        card.Child = stack;
        canvas.Children.Add(card);
        Content = canvas;

        // ESC acknowledges, as a keyboard fallback.
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) Finish(Dismissed); };

        Loaded += (_, _) => PositionCardBelow(cat, card);
    }

    private void PositionCardBelow(CatWindow cat, Border card)
    {
        // Window is maximized at the monitor origin, so screen coords == canvas coords.
        double x = cat.Left + cat.ActualWidth / 2 - CardW / 2;
        double y = cat.Top + cat.ActualHeight + 20;

        x = Math.Clamp(x, 20, Math.Max(20, ActualWidth - CardW - 20));
        y = Math.Clamp(y, 20, Math.Max(20, ActualHeight - CardH - 20));

        Canvas.SetLeft(card, x);
        Canvas.SetTop(card, y);
    }

    private bool _finished;
    private void Finish(Action? raise)
    {
        if (_finished) return; // a button click and ESC can't both fire
        _finished = true;
        raise?.Invoke();
        Close();
    }
}
