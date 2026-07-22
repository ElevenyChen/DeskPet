using System.IO;
using System.Windows.Media.Imaging;

namespace DeskPet;

/// <summary>
/// Loads PNG frames for a cat state from the Sprites/ folder and steps through them.
/// Mirrors the macOS CatFrames behavior:
///   - A state folder may contain "action group" subfolders (e.g. idle/blink, idle/tail).
///     On each state switch one group is picked at random and its frames play in order.
///   - Or the state folder may be flat (0.png, 1.png, ...) with no subfolders.
/// Frame files are named 0.png, 1.png, 2.png ... in play order.
/// </summary>
public sealed class SpriteAnimator
{
    private readonly string _spritesRoot;
    private readonly Random _rng = new();

    private List<BitmapImage> _frames = new();
    private int _index;

    public SpriteAnimator(string spritesRoot) => _spritesRoot = spritesRoot;

    /// <summary>The frame to show right now, or null if the state has no PNGs.</summary>
    public BitmapImage? Current => _frames.Count == 0 ? null : _frames[_index];

    public bool HasFrames => _frames.Count > 0;

    /// <summary>True if the state folder exists and contains at least one frame.</summary>
    public bool HasState(string state) => LoadFramesForState(state).Count > 0;

    /// <summary>
    /// Switch to a state folder (e.g. "idle", "walk_right"), picking a random action
    /// group if subfolders exist. Returns true if any frames were loaded.
    /// "sleeping" reuses the "lying_down" sprites when it has none of its own
    /// (matches the macOS behavior — sleep is lying_down + a zzZ overlay).
    /// </summary>
    public bool SetState(string state)
    {
        _frames = LoadFramesForState(state);
        if (_frames.Count == 0 && state == "sleeping")
            _frames = LoadFramesForState("lying_down");
        _index = 0;
        return _frames.Count > 0;
    }

    /// <summary>Advance to the next frame, looping. No-op if there are no frames.</summary>
    public void Advance()
    {
        if (_frames.Count == 0) return;
        _index = (_index + 1) % _frames.Count;
    }

    private List<BitmapImage> LoadFramesForState(string state)
    {
        var stateDir = Path.Combine(_spritesRoot, state);
        if (!Directory.Exists(stateDir))
            return new List<BitmapImage>();

        // Action groups = immediate subdirectories that contain 0.png.
        var groups = Directory.GetDirectories(stateDir)
            .Where(d => File.Exists(Path.Combine(d, "0.png")))
            .ToList();

        var frameDir = groups.Count > 0
            ? groups[_rng.Next(groups.Count)] // random action group
            : stateDir;                       // flat layout

        return LoadNumberedFrames(frameDir);
    }

    private static List<BitmapImage> LoadNumberedFrames(string dir)
    {
        var frames = new List<BitmapImage>();
        for (int i = 0; ; i++)
        {
            var path = Path.Combine(dir, $"{i}.png");
            if (!File.Exists(path)) break;
            frames.Add(LoadBitmap(path));
        }
        return frames;
    }

    private static BitmapImage LoadBitmap(string path)
    {
        // Load fully into memory so the file isn't locked and pixels stay crisp.
        var bmp = new BitmapImage();
        bmp.BeginInit();
        bmp.CacheOption = BitmapCacheOption.OnLoad;
        bmp.CreateOptions = BitmapCreateOptions.None;
        bmp.UriSource = new Uri(path, UriKind.Absolute);
        bmp.EndInit();
        bmp.Freeze(); // safe to share across the UI thread's timer callbacks
        return bmp;
    }
}
