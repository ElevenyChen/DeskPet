using System.IO;
using System.Text.Json;
using Microsoft.Win32;

namespace DeskPet;

/// <summary>
/// JSON-backed settings store — the Windows counterpart to the macOS UserDefaults-based
/// SettingsManager. Persists to %APPDATA%\DeskPet\settings.json. Single shared instance.
/// </summary>
public sealed class SettingsManager
{
    public static readonly SettingsManager Shared = new();

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
    };

    private readonly string _path;
    private Store _store;

    private SettingsManager()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "DeskPet");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "settings.json");
        _store = Load();

        // Seed and persist the default reminders on first run so their Ids are stable
        // (toggle/edit/delete match by Id, and Defaults() mints fresh Guids each call).
        if (_store.Reminders is null)
        {
            _store.Reminders = ReminderItem.Defaults();
            Save();
        }
    }

    // Serialized shape.
    private sealed class Store
    {
        public GlobalMode GlobalMode { get; set; } = GlobalMode.Normal;
        public bool SoundEnabled { get; set; } = true;
        public bool AlwaysOnTop { get; set; } = true;
        public bool WalkingEnabled { get; set; } = true;
        public double CatScale { get; set; } = 2.0;      // slider range 0.5–3.0
        public AppLanguage Language { get; set; } = AppLanguage.English;
        public List<ReminderItem>? Reminders { get; set; }
        public List<AlarmItem> Alarms { get; set; } = new();
    }

    private Store Load()
    {
        try
        {
            if (File.Exists(_path))
                return JsonSerializer.Deserialize<Store>(File.ReadAllText(_path)) ?? new Store();
        }
        catch { /* corrupt/partial file — fall back to defaults */ }
        return new Store();
    }

    private void Save()
    {
        try { File.WriteAllText(_path, JsonSerializer.Serialize(_store, JsonOpts)); }
        catch { /* best-effort; a failed write shouldn't crash the pet */ }
    }

    // MARK: - Mode

    public GlobalMode GlobalMode
    {
        get => _store.GlobalMode;
        set { _store.GlobalMode = value; Save(); }
    }

    public bool SoundEnabled
    {
        get => _store.SoundEnabled;
        set { _store.SoundEnabled = value; Save(); }
    }

    public bool AlwaysOnTop
    {
        get => _store.AlwaysOnTop;
        set { _store.AlwaysOnTop = value; Save(); }
    }

    public bool WalkingEnabled
    {
        get => _store.WalkingEnabled;
        set { _store.WalkingEnabled = value; Save(); }
    }

    public double CatScale
    {
        get => _store.CatScale;
        set { _store.CatScale = value; Save(); }
    }

    public AppLanguage Language
    {
        get => _store.Language;
        set { _store.Language = value; Save(); }
    }

    // MARK: - Launch at login (HKCU Run key — the Windows counterpart to SMAppService).

    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "DeskPet";

    public bool LaunchAtLogin
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
            return key?.GetValue(RunValueName) is not null;
        }
        set
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
                            ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (value)
            {
                var exe = Environment.ProcessPath;
                if (exe is not null) key.SetValue(RunValueName, $"\"{exe}\"");
            }
            else
            {
                key.DeleteValue(RunValueName, throwOnMissingValue: false);
            }
        }
    }

    // MARK: - Reminders

    /// <summary>Falls back to the built-in defaults when nothing is stored yet.</summary>
    public List<ReminderItem> Reminders
    {
        get => _store.Reminders ?? ReminderItem.Defaults();
        set { _store.Reminders = value; Save(); }
    }

    public void AddReminder(ReminderItem item)
    {
        var list = Reminders;
        list.Add(item);
        Reminders = list;
    }

    public void UpdateReminder(ReminderItem item)
    {
        var list = Reminders;
        var idx = list.FindIndex(r => r.Id == item.Id);
        if (idx >= 0) { list[idx] = item; Reminders = list; }
    }

    public void RemoveReminder(Guid id)
    {
        var list = Reminders;
        list.RemoveAll(r => r.Id == id);
        Reminders = list;
    }

    public void ToggleReminder(Guid id)
    {
        var list = Reminders;
        var item = list.Find(r => r.Id == id);
        if (item is not null) { item.Enabled = !item.Enabled; Reminders = list; }
    }

    /// <summary>Normal → given strength, Quiet → soft, SuperDND → null.</summary>
    public ReminderStrength? EffectiveStrength(ReminderStrength strength) => GlobalMode switch
    {
        GlobalMode.Normal => strength,
        GlobalMode.Quiet => ReminderStrength.Soft,
        _ => null, // SuperDND
    };

    // MARK: - Alarms

    public List<AlarmItem> Alarms
    {
        get => _store.Alarms;
        set { _store.Alarms = value; Save(); }
    }

    public void AddAlarm(AlarmItem item)
    {
        var list = Alarms;
        list.Add(item);
        Alarms = list;
    }

    public void UpdateAlarm(AlarmItem item)
    {
        var list = Alarms;
        var idx = list.FindIndex(a => a.Id == item.Id);
        if (idx >= 0) { list[idx] = item; Alarms = list; }
    }

    public void RemoveAlarm(Guid id)
    {
        var list = Alarms;
        list.RemoveAll(a => a.Id == id);
        Alarms = list;
    }

    public void ToggleAlarm(Guid id)
    {
        var list = Alarms;
        var item = list.Find(a => a.Id == id);
        if (item is not null) { item.Enabled = !item.Enabled; Alarms = list; }
    }

    /// <summary>SuperDND silences; else the alarm's override; else the mode strength.</summary>
    public ReminderStrength? EffectiveAlarmStrength(AlarmItem alarm)
    {
        if (GlobalMode == GlobalMode.SuperDND) return null;
        return alarm.StrengthOverride ?? GlobalMode.Strength();
    }
}
