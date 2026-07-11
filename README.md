# DeskPet — macOS Desktop Pet Cat Reminder

A pixel cat lives on your desktop — it walks, lies down, sleeps, and can be picked up. It reminds you to drink water and take breaks.

macOS menu bar app built with Swift 5 + AppKit, targeting macOS 13+.

## Features

### Cat Behaviors
- **Idle** — pixel cat sitting, with randomized action groups (blinking, tail wagging)
- **Lying down** — settles after ~25s of idle, supports front/side action groups
- **Sleeping** — falls asleep after ~25s lying down, with floating zzZ animation
- **Walking** — side-view pixel cat walking across the screen, leaving paw prints
- **Reminder** — pixel cat reminder animation
- **Dragged** — pick up the cat by dragging, window stretches 1.3x tall

### Reminder System
- Default reminders: drink water (30min), rest eyes (25min)
- Add / edit / delete / toggle any reminder with custom text and interval
- Three global modes control reminder intensity:
  - **Normal** — strong reminder: cat walks to center, scales up 3x, fullscreen overlay with dismiss card
  - **Quiet** — soft reminder: speech bubble above the cat, auto-dismisses after 8s
  - **Do Not Disturb** — no reminders, cat stays asleep

### Menu Bar
- Show/hide cat
- Mode switching (Normal / Quiet / Do Not Disturb)
- Reminder list management
- Cat size slider (0.5x – 3.0x)
- Always on top toggle
- Meow sound toggle
- Launch at login (SMAppService)
- Language switching (中文 / English)
- Pause options (30min / 1hr / until tomorrow / resume now)
- Test soft/strong reminders

### Custom Sprites
Drop PNGs into `Sprites/` subfolders (`idle/`, `walk_right/`, `dragged/`, etc.), named `0.png, 1.png, 2.png...` — the app picks them up automatically. Create sub-subfolders for action groups that are randomly chosen on state transitions.

## Project Structure

```
DeskPet/
├── main.swift              # App entry point
├── AppDelegate.swift       # Menu bar, cat window, reminders, drag, behavior loop, scaling
├── Models.swift            # CatState, ReminderItem, GlobalMode, AppLanguage
├── CatFrames.swift         # Unicode frames + PNG sprite loading (action groups) + custom icons
├── CatView.swift           # DraggableCatView — mouse drag handling + CatWindow/OverlayWindow
├── CatRenderer.swift       # Core Graphics cat drawing (reserved)
├── SettingsManager.swift   # UserDefaults persistence
├── ReminderManager.swift   # Timer management per GlobalMode
├── Assets.xcassets/        # App icon (pixel cat, all 10 sizes)
└── Sprites/                # Custom PNG frames by state
    ├── icon/               # App icon source
    ├── idle/               # Idle (supports action group subfolders)
    ├── lying_down/         # Lying down + sleeping (shared sprites, code adds zzZ)
    ├── walk_right/         # Walking right
    ├── walk_left/          # Walking left
    ├── reminder/           # Reminder animation
    ├── dragged/            # Picked up (supports action groups)
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
