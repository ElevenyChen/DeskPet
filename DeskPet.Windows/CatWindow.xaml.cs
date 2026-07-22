using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;

namespace DeskPet;

/// <summary>Folder-name state constants (match the Sprites/ subfolders).</summary>
public static class CatStates
{
    public const string Idle = "idle";
    public const string LyingDown = "lying_down";
    public const string Sleeping = "sleeping";
    public const string WalkRight = "walk_right";
    public const string WalkLeft = "walk_left";
    public const string Reminder = "reminder";
    public const string Playing = "playing";
    public const string ChasingTail = "chasing_tail";
    public const string BellyUp = "belly_up";
    public const string Grooming = "grooming";
    public const string Dragged = "dragged";
}

public partial class CatWindow : Window
{
    // Base sprite scale, driven by the tray "Cat Size" slider (persisted in settings).
    private double CatScale => SettingsManager.Shared.CatScale;

    private readonly SpriteAnimator _animator;
    private readonly DispatcherTimer _frameTimer = new();
    private DispatcherTimer? _walkTimer;
    private DispatcherTimer? _scaleTimer;
    private readonly DispatcherTimer _zzzTimer = new() { Interval = TimeSpan.FromSeconds(0.8) };
    private int _zzzStep;
    private static readonly string[] ZzzTexts = { "z", "zZ", "zZz" };

    // Extra multiplier used only by the strong reminder (window grows to 3×).
    private double _reminderScale = 1.0;
    // Point the window stays centered on while _reminderScale != 1.
    private Point _scaleCenter;

    /// <summary>Current behavior state (a Sprites/ folder name).</summary>
    public string State { get; private set; } = CatStates.Idle;

    /// <summary>True while the user is dragging — the behavior loop pauses.</summary>
    public bool IsInteracting { get; private set; }

    /// <summary>Set false during a strong reminder to lock out dragging (matches macOS).</summary>
    public bool DragEnabled { get; set; } = true;

    private bool _isRushing;

    public CatWindow()
    {
        InitializeComponent();

        Topmost = SettingsManager.Shared.AlwaysOnTop;

        var spritesRoot = Path.Combine(AppContext.BaseDirectory, "Sprites");
        _animator = new SpriteAnimator(spritesRoot);
        _animator.SetState(State);
        RenderCurrentFrame();

        var wa = SystemParameters.WorkArea;
        Loaded += (_, _) =>
        {
            Left = wa.Right - ActualWidth - 40;
            Top = wa.Bottom - ActualHeight - 20;
        };

        _frameTimer.Tick += (_, _) => { _animator.Advance(); RenderCurrentFrame(); };
        ApplyFrameInterval();
        _frameTimer.Start();

        _zzzTimer.Tick += (_, _) => AdvanceZzz();
    }

    /// <summary>True if this state has dedicated sprites (used to gate random activities).</summary>
    public bool SpriteExists(string state) => _animator.HasState(state);

    /// <summary>Re-render at the current settings scale (called when the size slider moves).</summary>
    public void RefreshScale() => RenderCurrentFrame();

    /// <summary>Apply the always-on-top setting to the window.</summary>
    public void ApplyAlwaysOnTop() => Topmost = SettingsManager.Shared.AlwaysOnTop;

    /// <summary>Switch behavior state, re-selecting a random action group and frame rate.</summary>
    public void SetState(string state)
    {
        if (State == state) return;
        State = state;
        _animator.SetState(state); // resets to frame 0 and picks a new action group
        ApplyFrameInterval();
        RenderCurrentFrame();

        // zzZ glyphs float only while sleeping (matches macOS start/stopZzzAnimation).
        if (state == CatStates.Sleeping) StartZzz();
        else StopZzz();
    }

    // MARK: - zzZ sleep overlay

    private void StartZzz()
    {
        _zzzStep = 0;
        ZzzLabel.Text = ZzzTexts[0];
        ZzzLabel.Opacity = 1;
        PositionZzz();
        _zzzTimer.Start();
    }

    private void StopZzz()
    {
        _zzzTimer.Stop();
        ZzzLabel.Opacity = 0;
    }

    private void AdvanceZzz()
    {
        _zzzStep = (_zzzStep + 1) % ZzzTexts.Length;
        ZzzLabel.Text = ZzzTexts[_zzzStep];
        ZzzLabel.Opacity = _zzzStep == 2 ? 0.6 : 1.0; // dim on the third glyph
        PositionZzz();
    }

    private void PositionZzz()
    {
        // Upper-right of the cat, drifting up 6px per step (WPF Y grows downward, so up = smaller Top).
        Canvas.SetLeft(ZzzLabel, Width * 0.7);
        Canvas.SetTop(ZzzLabel, Height * 0.2 - _zzzStep * 6);
    }

    // Per-state frame interval, mirroring the macOS startFrameAnimation() switch.
    private void ApplyFrameInterval()
    {
        double ms = State switch
        {
            CatStates.Sleeping => 800,
            CatStates.LyingDown => 1000,
            CatStates.WalkRight or CatStates.WalkLeft => _isRushing ? 100 : 250,
            CatStates.Reminder => 400,
            CatStates.Dragged => 300,
            CatStates.Playing => 500,
            CatStates.ChasingTail => 250,
            CatStates.BellyUp => 600,
            CatStates.Grooming => 700,
            _ => 600, // idle and everything else
        };
        _frameTimer.Interval = TimeSpan.FromMilliseconds(ms);
    }

    private void RenderCurrentFrame()
    {
        var frame = _animator.Current;
        if (frame is null) return;
        CatImage.Source = frame;

        // Window is sized manually (no SizeToContent) so the strong reminder can scale it.
        double w = frame.PixelWidth * CatScale * _reminderScale;
        double h = frame.PixelHeight * CatScale * _reminderScale;
        CatImage.Width = w;
        CatImage.Height = h;
        Width = w;
        Height = h;

        // While scaled up, keep the window centered on the captured point.
        if (_reminderScale != 1.0)
        {
            Left = _scaleCenter.X - w / 2;
            Top = _scaleCenter.Y - h / 2;
        }
    }

    // MARK: - Walking

    /// <summary>Walk to a random spot in the work area, then invoke <paramref name="onArrive"/>.</summary>
    public void WalkToRandomSpot(bool rush, Action onArrive)
    {
        var wa = SystemParameters.WorkArea;
        var rng = Random.Shared;
        double targetX = rng.NextDouble() * Math.Max(1, wa.Width - ActualWidth) + wa.Left;
        double targetY = rng.NextDouble() * Math.Max(1, wa.Height - ActualHeight) + wa.Top;
        WalkTo(targetX, targetY, rush, onArrive);
    }

    /// <summary>Walk to an explicit point (top-left), then invoke <paramref name="onArrive"/>.</summary>
    public void WalkTo(double targetX, double targetY, bool rush, Action onArrive)
    {
        _isRushing = rush;
        bool goingRight = targetX > Left;
        SetState(goingRight ? CatStates.WalkRight : CatStates.WalkLeft);

        double speed = rush ? 24 : 8; // px per step
        _walkTimer?.Stop();
        _walkTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        _walkTimer.Tick += (_, _) =>
        {
            double dx = targetX - Left, dy = targetY - Top;
            double dist = Math.Sqrt(dx * dx + dy * dy);
            if (dist <= speed)
            {
                Left = targetX; Top = targetY;
                _walkTimer!.Stop();
                _isRushing = false;
                onArrive();
                return;
            }
            Left += dx / dist * speed;
            Top += dy / dist * speed;
        };
        _walkTimer.Start();
    }

    // MARK: - Reminder scaling

    /// <summary>
    /// Animate the window's reminder scale from its current value to <paramref name="target"/>
    /// over <paramref name="steps"/> smoothstep steps, staying centered on the current center.
    /// </summary>
    public void AnimateScale(double target, int steps, int intervalMs, Action? onDone = null)
    {
        _scaleTimer?.Stop();
        _scaleCenter = new Point(Left + Width / 2, Top + Height / 2);
        double start = _reminderScale;
        int step = 0;

        _scaleTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(intervalMs) };
        _scaleTimer.Tick += (_, _) =>
        {
            step++;
            if (step >= steps)
            {
                _scaleTimer!.Stop();
                _reminderScale = target;
                if (target == 1.0) _scaleCenter = default; // stop recentering when back to normal
                RenderCurrentFrame();
                onDone?.Invoke();
                return;
            }
            double t = (double)step / steps;
            double eased = t * t * (3 - 2 * t); // smoothstep
            _reminderScale = start + (target - start) * eased;
            RenderCurrentFrame();
        };
        _scaleTimer.Start();
    }

    /// <summary>Center of the primary work area, in top-left window coordinates, for this cat.</summary>
    public Point ScreenCenterTopLeft()
    {
        var wa = SystemParameters.WorkArea;
        return new Point(wa.Left + (wa.Width - ActualWidth) / 2,
                         wa.Top + (wa.Height - ActualHeight) / 2);
    }

    // MARK: - Dragging

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (!DragEnabled) return; // locked during a strong reminder
        if (e.ButtonState != MouseButtonState.Pressed) return;
        IsInteracting = true;
        var wasWalking = State is CatStates.WalkLeft or CatStates.WalkRight;
        if (wasWalking) _walkTimer?.Stop();
        if (_animator.HasState(CatStates.Dragged)) SetState(CatStates.Dragged);

        DragMove(); // blocks until the mouse is released

        IsInteracting = false;
        SetState(CatStates.Idle);
    }
}
