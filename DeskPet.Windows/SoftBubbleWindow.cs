using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

namespace DeskPet;

/// <summary>
/// Soft reminder: a small white rounded bubble that floats just above the cat and is
/// click-through. Port of the macOS bubbleWindow. Caller auto-dismisses after 8s.
/// </summary>
public sealed class SoftBubbleWindow : Window
{
    private readonly CatWindow _cat;

    public SoftBubbleWindow(string message, CatWindow cat)
    {
        _cat = cat;

        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = false;
        SizeToContent = SizeToContent.WidthAndHeight;

        Content = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(235, 255, 255, 255)), // white @ ~0.92
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(12, 6, 12, 6),
            Child = new TextBlock
            {
                Text = message,
                FontSize = 13,
                FontWeight = FontWeights.Medium,
                Foreground = Brushes.Black,
                TextAlignment = TextAlignment.Center,
            },
        };

        Loaded += (_, _) => PositionAboveCat();
    }

    private void PositionAboveCat()
    {
        Left = _cat.Left + _cat.ActualWidth / 2 - ActualWidth / 2;
        Top = _cat.Top - ActualHeight - 6; // WPF Y grows downward → above the cat
    }

    // MARK: - Click-through (WS_EX_TRANSPARENT), matching ignoresMouseEvents=true.

    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x20;
    private const int WsExToolWindow = 0x80; // keep it out of Alt-Tab

    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var hwnd = new WindowInteropHelper(this).Handle;
        int ex = GetWindowLong(hwnd, GwlExStyle);
        SetWindowLong(hwnd, GwlExStyle, ex | WsExTransparent | WsExToolWindow);
    }
}
