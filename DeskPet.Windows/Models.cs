namespace DeskPet;

/// <summary>How intrusive a reminder is. Mirrors the macOS ReminderStrength.</summary>
public enum ReminderStrength { Soft = 0, Hard = 1 }

/// <summary>UI language. Mirrors the macOS AppLanguage.</summary>
public enum AppLanguage { Chinese = 0, English = 1 }

/// <summary>Interval-based reminder (every N minutes). Port of ReminderItem.</summary>
public sealed class ReminderItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string ShortMessage { get; set; } = "";
    public string UrgentMessage { get; set; } = "";
    public int IntervalMinutes { get; set; } = 30;
    public bool Enabled { get; set; } = true;

    public static List<ReminderItem> Defaults() => new()
    {
        new ReminderItem { Name = "Drink Water", ShortMessage = "Time for water~", UrgentMessage = "⚠️ Drink water!", IntervalMinutes = 30, Enabled = true },
        new ReminderItem { Name = "Rest Eyes",   ShortMessage = "Rest your eyes",  UrgentMessage = "⚠️ Rest your eyes!", IntervalMinutes = 25, Enabled = true },
    };
}

/// <summary>Time-of-day alarm (HH:MM). Port of AlarmItem.</summary>
public sealed class AlarmItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Message { get; set; } = "";
    public int Hour { get; set; }
    public int Minute { get; set; }

    /// <summary>Null = follow the global mode; otherwise force soft/hard.</summary>
    public ReminderStrength? StrengthOverride { get; set; }
    public bool RepeatDaily { get; set; }
    public bool SnoozeEnabled { get; set; }
    public bool Enabled { get; set; } = true;

    public string TimeString => $"{Hour:D2}:{Minute:D2}";
}

/// <summary>Strength helpers for the global mode (declared in BehaviorController.cs).</summary>
public static class GlobalModeExtensions
{
    /// <summary>Normal → hard, Quiet → soft, SuperDND → null (silent).</summary>
    public static ReminderStrength? Strength(this GlobalMode mode) => mode switch
    {
        GlobalMode.Normal => ReminderStrength.Hard,
        GlobalMode.Quiet => ReminderStrength.Soft,
        _ => null, // SuperDND
    };
}
