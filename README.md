# DeskPet — macOS Desktop Pet Cat Reminder

A pixel cat lives on your desktop — it walks, naps, grooms itself, chases its tail, and can be picked up. It reminds you to drink water and take breaks.

macOS menu bar app built with Swift 5 + AppKit, targeting macOS 13+.

## Features

### Cat Behaviors
- **Idle** — pixel cat sitting, with randomized action groups (blinking, tail wagging)
- **Lying down** — settles after ~30-50s of idle, supports front/side action groups
- **Sleeping** — falls asleep after lying down, naps for 3-5 minutes with floating zzZ animation
- **Walking** — side-view pixel cat walking across the screen with eased acceleration, leaving paw prints
- **Playing** — randomly triggered from idle, batting at a toy (~20-30s)
- **Chasing tail** — randomly triggered from idle, spinning in circles (~15-25s)
- **Belly up** — randomly triggered from idle, rolling over to show belly (~20-35s)
- **Grooming** — randomly triggered from idle, licking paw or fur (~25-40s)
- **Attacking** — click the cat 5-15 times and it swipes its claws (plays once through then calms down)
- **Dragged** — pick up the cat by dragging, window stretches 1.3x tall
- **Reminder** — alert animation when a reminder fires

### Reminder System
- Default reminders: drink water (30min), rest eyes (25min)
- Add / edit / delete / toggle any reminder with custom text and interval
- Three global modes control reminder intensity:
  - **Normal** — strong reminder: cat walks to center, scales up 3x, fullscreen overlay with dismiss card
  - **Quiet** — soft reminder: speech bubble above the cat, auto-dismisses after 8s
  - **Do Not Disturb** — no reminders, cat stays asleep

### Alarm System
- Set alarms by specific time (HH:MM), separate from interval-based reminders
- Per-alarm strength override (strong / soft / follow system)
- Repeat daily option
- Snooze support (5 minutes), toggleable per alarm
- Non-repeating alarms auto-disable after firing

### Menu Bar
- Show/hide cat
- Mode switching (Normal / Quiet / Do Not Disturb)
- Reminder list management (toggle / edit / add / delete)
- Alarm list management (toggle / edit / add / delete)
- Cat size slider (0.5x – 3.0x)
- Always on top toggle
- Allow walking toggle
- Meow sound toggle
- Launch at login (SMAppService)
- Language switching (中文 / English)
- Pause options (30min / 1hr / until tomorrow / resume now)
- Test soft/strong reminders

### Custom Sprites
Drop PNGs into `Sprites/` subfolders, named `0.png, 1.png, 2.png...` — the app picks them up automatically. Create sub-subfolders for action groups that are randomly chosen on state transitions. See `Sprites/README.txt` for the full guide.

## Project Structure

```
DeskPet/
├── main.swift              # App entry point
├── AppDelegate.swift       # Menu bar, cat window, reminders, drag, behavior loop, scaling
├── Models.swift            # CatState, ReminderItem, AlarmItem, GlobalMode, AppLanguage
├── CatFrames.swift         # Unicode frames + PNG sprite loading (action groups) + custom icons
├── CatView.swift           # DraggableCatView — mouse drag handling + CatWindow/OverlayWindow
├── CatRenderer.swift       # Core Graphics cat drawing (reserved)
├── SettingsManager.swift   # UserDefaults persistence
├── ReminderManager.swift   # Timer management per GlobalMode
├── AlarmManager.swift      # Time-based alarm scheduling and snooze
├── Assets.xcassets/        # App icon (pixel cat, all 10 sizes)
└── Sprites/                # Custom PNG frames by state
    ├── icon/               # App icon source
    ├── idle/               # Idle (supports action group subfolders)
    ├── lying_down/         # Lying down + sleeping (shared sprites, code adds zzZ)
    ├── walk_right/         # Walking right
    ├── walk_left/          # Walking left
    ├── reminder/           # Reminder animation
    ├── dragged/            # Picked up (supports action groups)
    ├── attacking/          # Attack / claw swipe (action groups: mad, mild)
    ├── playing/            # Playing with toy
    ├── chasing_tail/       # Chasing tail
    ├── belly_up/           # Rolling over (action groups: quick_roll, lazy_stretch)
    ├── grooming/           # Grooming (action groups: paw, fur)
    └── paw_print/          # Paw prints
```

## Build & Run

```bash
# Build
xcodebuild -project DeskPet.xcodeproj -scheme DeskPet -configuration Release build

# Run
open ~/Library/Developer/Xcode/DerivedData/DeskPet-*/Build/Products/Release/DeskPet.app
```

Or open `DeskPet.xcodeproj` in Xcode and press Cmd+R.

### Package as DMG

```bash
xcodebuild -project DeskPet.xcodeproj -scheme DeskPet -configuration Release clean build

hdiutil create -volname DeskPet \
  -srcfolder Build/Products/Release/DeskPet.app \
  -ov -format UDZO DeskPet.dmg
```

## Requirements

- macOS 13+
- Xcode 14+ (for building)

## License

MIT
