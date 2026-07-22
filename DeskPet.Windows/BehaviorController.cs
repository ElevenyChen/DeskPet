using System.Windows.Threading;

namespace DeskPet;

/// <summary>Global reminder mode — governs the behavior loop's sleep override.</summary>
public enum GlobalMode { Normal, Quiet, SuperDND }

/// <summary>
/// Port of the macOS AppDelegate behavior loop (startBehaviorLoop): a 5-second tick
/// that walks the cat through idle → lying_down → sleeping, with weighted random
/// activities (walk / zoomies / play / chase-tail / belly-up / groom) fired from idle.
/// Timings and weights match the Swift original.
/// </summary>
public sealed class BehaviorController
{
    private readonly CatWindow _cat;
    private readonly DispatcherTimer _tick = new() { Interval = TimeSpan.FromSeconds(5) };
    private readonly Random _rng = Random.Shared;

    private int _idleCounter;

    /// <summary>
    /// The global mode, backed by shared settings so the behavior loop, reminders,
    /// and alarms all agree. SuperDND drives super-do-not-disturb (always sleep).
    /// </summary>
    public GlobalMode Mode
    {
        get => SettingsManager.Shared.GlobalMode;
        set => SettingsManager.Shared.GlobalMode = value;
    }

    /// <summary>Mirrors the "Allow Walking" menu toggle (persisted in settings).</summary>
    public bool WalkingEnabled
    {
        get => SettingsManager.Shared.WalkingEnabled;
        set => SettingsManager.Shared.WalkingEnabled = value;
    }

    /// <summary>Set true while a strong/soft reminder is on screen (pauses the loop).</summary>
    public bool IsReminding { get; set; }

    public BehaviorController(CatWindow cat)
    {
        _cat = cat;
        _tick.Tick += (_, _) => Step();
    }

    public void Start() => _tick.Start();
    public void Stop() => _tick.Stop();

    private void Step()
    {
        // Paused while the user is dragging or a reminder is showing.
        if (IsReminding || _cat.IsInteracting) return;
        // Walking is animated by CatWindow; don't advance the loop mid-walk.
        if (_cat.State is CatStates.WalkLeft or CatStates.WalkRight) return;

        if (Mode == GlobalMode.SuperDND)
        {
            if (_cat.State != CatStates.Sleeping) _cat.SetState(CatStates.Sleeping);
            return;
        }

        _idleCounter++;

        // Auto-end the random activities after a few ticks.
        if (EndActivityAfter(CatStates.Playing, 4, 6)) return;
        if (EndActivityAfter(CatStates.ChasingTail, 3, 5)) return;
        if (EndActivityAfter(CatStates.BellyUp, 4, 7)) return;
        if (EndActivityAfter(CatStates.Grooming, 5, 8)) return;

        // From idle: maybe start a weighted-random activity.
        if (_cat.State == CatStates.Idle && TryStartRandomActivity()) return;

        // idle → lie down (~30–50s)
        if (_cat.State == CatStates.Idle && _idleCounter >= _rng.Next(6, 11))
        {
            _cat.SetState(CatStates.LyingDown);
            return;
        }

        // lying → asleep (~70–130s)
        if (_cat.State == CatStates.LyingDown && _idleCounter >= _rng.Next(14, 27))
        {
            _cat.SetState(CatStates.Sleeping);
            return;
        }

        // asleep → wake (~3–5 min)
        if (_cat.State == CatStates.Sleeping && _idleCounter >= _rng.Next(36, 61))
        {
            _idleCounter = 0;
            _cat.SetState(CatStates.Idle);
        }
    }

    private bool EndActivityAfter(string state, int minTicks, int maxTicksInclusive)
    {
        if (_cat.State == state && _idleCounter >= _rng.Next(minTicks, maxTicksInclusive + 1))
        {
            _idleCounter = 0;
            _cat.SetState(CatStates.Idle);
            return true;
        }
        return false;
    }

    private bool TryStartRandomActivity()
    {
        var actions = new List<(int weight, Action run)>();

        if (WalkingEnabled)
        {
            actions.Add((6, () => Walk(rush: false)));
            actions.Add((2, () => Walk(rush: true)));
        }
        if (_cat.SpriteExists(CatStates.Playing)) actions.Add((3, () => _cat.SetState(CatStates.Playing)));
        if (_cat.SpriteExists(CatStates.ChasingTail)) actions.Add((2, () => _cat.SetState(CatStates.ChasingTail)));
        if (_cat.SpriteExists(CatStates.BellyUp)) actions.Add((2, () => _cat.SetState(CatStates.BellyUp)));
        if (_cat.SpriteExists(CatStates.Grooming)) actions.Add((3, () => _cat.SetState(CatStates.Grooming)));

        if (actions.Count == 0) return false;

        // Same shape as Swift: roll over weight*3, so ~1/3 of eligible ticks do something.
        int total = actions.Sum(a => a.weight);
        int roll = _rng.Next(0, total * 3);
        int cumulative = 0;
        foreach (var (weight, run) in actions)
        {
            cumulative += weight;
            if (roll < cumulative)
            {
                _idleCounter = 0;
                run();
                return true;
            }
        }
        return false; // roll landed in the "do nothing" upper 2/3
    }

    private void Walk(bool rush)
    {
        _idleCounter = 0;
        _cat.WalkToRandomSpot(rush, () =>
        {
            _idleCounter = 0;
            _cat.SetState(CatStates.Idle);
        });
    }
}
