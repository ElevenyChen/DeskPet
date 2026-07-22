namespace DeskPet;

/// <summary>
/// Bilingual UI strings (中文 / English), keyed off the current language setting.
/// The Windows counterpart to the inline `en ? "…" : "…"` ternaries in the macOS menu.
/// </summary>
public static class Loc
{
    private static bool En => SettingsManager.Shared.Language == AppLanguage.English;
    private static string T(string zh, string en) => En ? en : zh;

    // Tray menu
    public static string ShowHideCat => T("显示/隐藏猫咪", "Show / Hide Cat");
    public static string Reminders => T("提醒", "Reminders");
    public static string Alarms => T("闹钟", "Alarms");
    public static string AddReminder => T("添加提醒...", "Add Reminder...");
    public static string AddAlarm => T("添加闹钟...", "Add Alarm...");
    public static string Edit => T("编辑...", "Edit...");
    public static string Delete => T("删除", "Delete");
    public static string Enabled => T("启用", "Enabled");
    public static string AlwaysOnTop => T("始终置顶", "Always on Top");
    public static string AllowWalking => T("允许走动", "Allow Walking");
    public static string CatSound => T("猫叫声音", "Cat Sound");
    public static string LaunchAtLogin => T("开机自启动", "Launch at Login");
    public static string CatSize => T("猫咪大小", "Cat Size");
    public static string Language => T("语言", "Language");
    public static string Mode => T("模式", "Mode");
    public static string Pause => T("暂停", "Pause");
    public static string Pause30 => T("暂停 30 分钟", "Pause 30 min");
    public static string Pause60 => T("暂停 1 小时", "Pause 1 hour");
    public static string PauseTomorrow => T("暂停到明天", "Pause until tomorrow");
    public static string ResumeNow => T("立即恢复", "Resume Now");
    public static string Test => T("测试", "Test");
    public static string TestSoft => T("测试软提醒", "Test Soft Reminder");
    public static string TestStrong => T("测试强提醒", "Test Strong Reminder");
    public static string Quit => T("退出", "Quit");

    // Modes
    public static string ModeNormal => T("正常模式（强提醒）", "Normal (strong)");
    public static string ModeQuiet => T("安静模式（软提醒）", "Quiet (soft)");
    public static string ModeSuperDND => T("超级免打扰", "Super DND");
    public static string ModeName(GlobalMode m) => m switch
    {
        GlobalMode.Normal => ModeNormal,
        GlobalMode.Quiet => ModeQuiet,
        _ => ModeSuperDND,
    };

    // Editors — reminders
    public static string EditReminderTitle => T("编辑提醒", "Edit Reminder");
    public static string AddReminderTitle => T("添加新提醒", "Add Reminder");
    public static string FieldName => T("名称", "Name");
    public static string FieldSoftMsg => T("软提示文字", "Soft message");
    public static string FieldStrongMsg => T("硬提示文字", "Strong message");
    public static string FieldIntervalMin => T("间隔(分钟)", "Interval (min)");

    // Editors — alarms
    public static string EditAlarmTitle => T("编辑闹钟", "Edit Alarm");
    public static string AddAlarmTitle => T("添加闹钟", "Add Alarm");
    public static string FieldMessage => T("提示文字", "Message");
    public static string FieldTime => T("时间", "Time");
    public static string FieldStrength => T("提醒强度", "Strength");
    public static string StrengthFollow => T("跟随系统", "Follow system");
    public static string StrengthSoft => T("软提醒", "Soft");
    public static string StrengthStrong => T("强提醒", "Strong");
    public static string RepeatDaily => T("每天重复", "Repeat daily");
    public static string AllowSnooze => T("允许贪睡（5分钟）", "Allow snooze (5 min)");

    // Buttons
    public static string Save => T("保存", "Save");
    public static string Add => T("添加", "Add");
    public static string Cancel => T("取消", "Cancel");

    // Alarm menu label pieces
    public static string TagStrong => T("强", "strong");
    public static string TagSoft => T("软", "soft");
    public static string TagSystem => T("跟随系统", "system");
    public static string TagDaily => T("每天", "daily");
    public static string MinutesShort => T("分钟", "min");
}
