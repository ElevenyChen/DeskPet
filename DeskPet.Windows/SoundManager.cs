using System.IO;
using System.Windows.Media;

namespace DeskPet;

/// <summary>
/// Plays the cat-meow sounds ported from the macOS app. Loads every audio file from the
/// output Sounds/ folder and plays a random one at 30% volume — the Windows counterpart to
/// CatFrames.loadCustomSounds + playRandomSound (NSSound). Gated on the Cat Sound setting.
/// Uses WPF MediaPlayer (handles mp3; System.Media.SoundPlayer is WAV-only).
/// Must be called on the UI thread.
/// </summary>
public sealed class SoundManager
{
    public static readonly SoundManager Shared = new();

    private static readonly string[] Extensions = { ".mp3", ".wav", ".m4a", ".aiff", ".caf" };

    private readonly List<string> _files = new();
    // Keep players alive until they finish, or they get collected mid-playback.
    private readonly List<MediaPlayer> _playing = new();

    private SoundManager()
    {
        var dir = Path.Combine(AppContext.BaseDirectory, "Sounds");
        if (!Directory.Exists(dir)) return;
        foreach (var f in Directory.GetFiles(dir).OrderBy(x => x))
            if (Extensions.Contains(Path.GetExtension(f).ToLowerInvariant()))
                _files.Add(f);
    }

    public void PlayRandom()
    {
        if (!SettingsManager.Shared.SoundEnabled) return;
        if (_files.Count == 0) return;

        var path = _files[Random.Shared.Next(_files.Count)];
        var player = new MediaPlayer { Volume = 0.3 };
        player.MediaEnded += (_, _) => { player.Close(); _playing.Remove(player); };
        player.Open(new Uri(path, UriKind.Absolute));
        player.Play();
        _playing.Add(player);
    }
}
