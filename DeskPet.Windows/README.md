# DeskPet.Windows — WPF port

A Windows/C# (.NET 8 + WPF) port of the macOS DeskPet cat: a transparent, draggable,
always-on-top pixel cat with a behavior state machine, interval reminders + alarms,
soft/strong reminder UIs, a full bilingual tray menu, and cat sounds.

## Build & run (on Windows)

Requires the [.NET 8 SDK](https://dotnet.microsoft.com/download) with the desktop
workload. WPF only builds/runs on Windows — it will not compile on macOS/Linux.

```powershell
cd DeskPet.Windows
dotnet run
```

The build reuses `..\DeskPet\Sprites\**\*.png` and `..\DeskPet\Sounds\*` 1:1 (copied to
the output folder), so no assets are duplicated.

## What works

- Transparent borderless floating window (`WindowStyle=None` + `AllowsTransparency`)
- Drag anywhere on the cat (`DragMove()` — no AppKit alpha hack needed)
- Always-on-top (`Topmost`)
- Sprite animation with **action groups**: `idle/blink`, `idle/tail` etc. picked at
  random on state switch; flat `0.png,1.png` layouts also supported (`SpriteAnimator`)
- Window auto-sizes to the sprite's native pixel size × scale, nearest-neighbor scaling
- Tray icon with Show/Hide + Quit + Mode + Allow Walking; closing the cat doesn't
  quit the app (`ShutdownMode=OnExplicitShutdown`)
- **Behavior state machine** (`BehaviorController.cs`): 5s tick, idle→lying_down→sleeping,
  weighted random walk / zoomies / play / chase-tail / belly-up / groom — a direct port
  of the Swift `startBehaviorLoop` (same timings and weights). SuperDND mode → always sleep.
- **Reminders & Alarms** (`ReminderManager.cs` / `AlarmManager.cs`): interval reminders
  (one `DispatcherTimer` each, pause/resume), and HH:MM alarms (15s check, once-per-day,
  midnight reset, snooze, non-repeat auto-disable). Strength resolves from the global mode
  (`SettingsManager.EffectiveStrength` / `EffectiveAlarmStrength`). Both raise a `Triggered`
  event routed through `ReminderPresenter`.
- **Settings** (`SettingsManager.cs`): JSON at `%APPDATA%\DeskPet\settings.json` (mode, sound,
  always-on-top, walking, cat scale, language, reminders, alarms) — shared source of truth.
- **Full tray menu** (`App.xaml.cs`): Show/Hide, Mode, Reminders & Alarms submenus with
  per-item **Enabled / Edit… / Delete** and Add… (`ReminderEditor` / `AlarmEditor` modal
  dialogs), Always-on-Top, Allow Walking, Cat Sound, Launch at Login, a **Cat Size** slider
  (0.5–3.0), Language (中文/English), Pause (30 min / 1 hr / tomorrow / resume), Test, Quit.
  Bilingual via `Localization.cs`; the menu rebuilds on any change.
- **Cat sound** (`SoundManager.cs`): the macOS `DeskPet/Sounds/*.mp3` meow(s) are reused 1:1
  (copied to output `Sounds/`) and played at 30% volume on a strong reminder via WPF
  `MediaPlayer`, gated on the Cat Sound setting.
- **Launch at login** (`SettingsManager.LaunchAtLogin`): HKCU `…\Run` registry value.
- **Soft reminder** (`SoftBubbleWindow.cs`): click-through white rounded bubble above the
  cat, auto-dismiss after 8s (WS_EX_TRANSPARENT for the ignoresMouseEvents behavior).
- **Strong reminder** (`OverlayWindow.cs` + `ReminderPresenter.cs`): walk to center →
  scale the cat window 3× (8-step smoothstep) → full-screen 40% dim + white card below the
  cat with "Got it!" and optional 5-min snooze; dragging is locked and the behavior loop
  paused until acknowledged, then the cat scales back. Snooze re-fires after 5 minutes.
- Tray now has **Test Soft Reminder** / **Test Strong Reminder** to exercise both without waiting.
- **zzZ sleep overlay** (`CatWindow`): a click-through `TextBlock` over the cat that cycles
  `z` → `zZ` → `zZz` every 0.8s, drifting up and dimming on the third glyph; shown only while
  sleeping, driven from `SetState` (macOS start/stopZzzAnimation).

## Still to port (maps to the macOS code)

The core feature set is now ported. Remaining niceties: the app-icon `.ico` for the tray,
multi-monitor walking, and a couple of small behaviors (click-to-attack, paw prints).

### Known simplifications / possible first-build fixups

- **Strong reminder z-order**: the scaled cat sits **under** the 40% dim (still visible,
  just dimmed); macOS raises it above. Fixing needs a `SetWindowPos(HWND_TOPMOST)` bump
  after the overlay shows — deferred as cosmetic.
- **Reminder/alarm editing UX** diverges from macOS: instead of the NSAlert button-picker,
  each reminder/alarm is a submenu with Enabled / Edit… / Delete (cleaner in a WPF menu).
- **`Microsoft.Win32.Registry`** (launch-at-login) ships with the `net8.0-windows` TFM; if
  the compiler can't find it, add `<PackageReference Include="Microsoft.Win32.Registry" />`.
- Cat Size slider writes settings on every drag tick (a debounce would be tidier).

## Files

- `DeskPet.Windows.csproj` — .NET 8 WPF, links the shared sprites + sounds, `H.NotifyIcon.Wpf`
- `App.xaml(.cs)` — app entry, owns the tray icon + full menu, no main window
- `CatWindow.xaml(.cs)` — the floating cat, frame timer, zzZ overlay, walk/scale
- `SpriteAnimator.cs` — folder → frames, action-group selection
- `Models.cs` — `ReminderItem` / `AlarmItem` / `ReminderStrength` / `AppLanguage`
- `SettingsManager.cs` — JSON settings + launch-at-login registry
- `ReminderManager.cs` / `AlarmManager.cs` — the two timer subsystems
- `ReminderPresenter.cs` — soft/strong reminder orchestration
- `SoftBubbleWindow.cs` / `OverlayWindow.cs` — the reminder UIs
- `ReminderEditor.cs` / `AlarmEditor.cs` / `DialogUI.cs` — the add/edit dialogs
- `SoundManager.cs` — cat-meow playback
- `Localization.cs` — bilingual UI strings
- `app.manifest` — per-monitor DPI awareness
