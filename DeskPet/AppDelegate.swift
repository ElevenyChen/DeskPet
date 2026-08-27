import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var catWindow: NSWindow!
    private var catTextField: NSTextField!
    private var catImageView: NSImageView!
    private var usingPNG = false
    private var bubbleWindow: NSWindow?
    private let reminderManager = ReminderManager.shared
    private let alarmManager = AlarmManager.shared
    private let settings = SettingsManager.shared

    private var catState: CatState = .idle
    private var frameIndex = 0
    private var currentSpriteGroup: String?
    private var zzzLabel: NSTextField!
    private var zzzTimer: Timer?
    private var exclamationLabel: NSTextField!
    private var animTimer: Timer?
    private var walkTimer: Timer?
    private var idleCounter = 0
    var isReminding = false
    var isAttacking: Bool { catState == .attacking }

    private var pawPrintWindows: [NSWindow] = []
    private var overlayWindow: NSWindow?
    private var originalCatWindowFrame: NSRect?
    private var activeHardReminderItem: ReminderItem?
    private var activeHardAlarmItem: AlarmItem?
    private var scaleTimer: Timer?
    private var walkAnimTimer: Timer?
    private var stateBeforeDrag: CatState?
    private var customSounds: [NSSound] = []
    private var clickCount = 0
    private var attackThreshold = Int.random(in: 5...15)
    private var playWiggleTimer: Timer?
    private var isRushing = false
    private let focusManager = FocusManager.shared
    private var focusStatusTimer: Timer?
    private var hardReminderShowsSnooze = true
    var isFocusOverlay = false
    var isSoftReminderActive = false
    private var sleepAfterOverlay = false
    private var idleCheckTimer: Timer?
    private var idleCandidateStart: Date?
    private var idleLongPromptShown = false
    private var idlePromptActive = false
    private var overworkNotifiedMark = 0
    private var lastOverworkStretchStart: Date?
    private var hardReminderButtonTitle: String?
    private var pendingOverlayItem: ReminderItem?
    private var pendingOverlayScreen: NSScreen?
    private weak var dutyStatusMenuItem: NSMenuItem?
    private weak var dutyTodayMenuItem: NSMenuItem?
    private var workWindowTimer: Timer?
    private var promptedWindowStartDay: Date?
    private var promptedWindowEndDay: Date?
    private var statsWindow: NSWindow?
    private var statsTextView: NSTextView?
    private var statsSegment: NSSegmentedControl?
    private var focusHUDWindow: NSWindow?
    private var focusHUDLabel: NSTextField?
    private var focusHUDTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupCatWindow()
        // Keep the focus HUD glued to the cat on every kind of movement
        // (walking, wiggle, rush, drag, reminder scale-up)
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: catWindow, queue: .main) { [weak self] _ in
            self?.repositionFocusHUD()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: catWindow, queue: .main) { [weak self] _ in
            self?.repositionFocusHUD()
        }
        reminderManager.delegate = self
        reminderManager.start()
        alarmManager.delegate = self
        alarmManager.start()
        focusManager.delegate = self
        focusManager.restoreOnLaunch()
        updateFocusMenuBar()
        focusStatusTimer = commonTimer(1, repeats: true) { [weak self] _ in
            self?.updateFocusMenuBar()
        }
        workWindowTimer = commonTimer(60, repeats: true) { [weak self] _ in
            self?.checkWorkWindow()
        }
        DutyManager.shared.reconcileStretchOnLaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.checkStaleDutyOnLaunch()
        }
        idleCheckTimer = commonTimer(30, repeats: true) { [weak self] _ in
            self?.checkIdleAndOverwork()
        }
        if focusManager.currentSession != nil {
            showFocusHUD()
        }
        startBehaviorLoop()
        customSounds = CatFrames.loadCustomSounds()
        if let customIcon = CatFrames.customIcon() {
            NSApp.applicationIconImage = customIcon
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        if let icon = CatFrames.customIcon() ?? NSImage(named: "AppIcon") {
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
        } else {
            button.title = "🐱"
        }
        button.imagePosition = .imageLeft
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statusItem.menu = buildMenu()
    }

    private var L: AppLanguage { settings.language }

    // Timers registered in .common mode keep firing while modal dialogs
    // (NSAlert.runModal) or menu tracking are active — otherwise every
    // animation freezes whenever a dialog is open.
    @discardableResult
    private func commonTimer(_ interval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let en = L == .english

        // ── Work state (state-first: clock in → tracking runs by itself) ──
        let duty = DutyManager.shared
        let dutyStatus = NSMenuItem(title: dutyStatusLine(), action: nil, keyEquivalent: "")
        dutyStatus.isEnabled = false
        menu.addItem(dutyStatus)
        dutyStatusMenuItem = dutyStatus
        let todayItem = NSMenuItem(title: todayWorkLine(), action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        menu.addItem(todayItem)
        dutyTodayMenuItem = todayItem
        menu.addItem(.separator())

        if duty.isOnDuty {
            if duty.isOnBreak {
                let backItem = NSMenuItem(title: "", action: #selector(endBreakFromMenu), keyEquivalent: "")
                backItem.attributedTitle = highlightedTitle(en ? "▶ Resume Working" : "▶ 回来继续工作")
                backItem.target = self
                menu.addItem(backItem)
            } else {
                let breakItem = NSMenuItem(title: en ? "☕️ Break (stepping away)" : "☕️ 休息 / 暂时离开", action: #selector(startBreakFromMenu), keyEquivalent: "")
                breakItem.target = self
                menu.addItem(breakItem)
                if focusManager.currentSession != nil {
                    let endFocus = NSMenuItem(title: en ? "🎯 End Deep Focus" : "🎯 结束 Deep Focus", action: #selector(endFocusFromMenu), keyEquivalent: "")
                    endFocus.target = self
                    menu.addItem(endFocus)
                } else {
                    let deepItem = NSMenuItem(title: en ? "🎯 Deep Focus..." : "🎯 Deep Focus（专注冲刺）...", action: #selector(openDeepFocus), keyEquivalent: "")
                    deepItem.target = self
                    menu.addItem(deepItem)
                }
            }
            let clockOutItem = NSMenuItem(title: "", action: #selector(clockOutFromMenu), keyEquivalent: "")
            clockOutItem.attributedTitle = highlightedTitle(en ? "⏹ Clock Out..." : "⏹ 下班打卡...")
            clockOutItem.target = self
            menu.addItem(clockOutItem)
        } else {
            let clockInItem = NSMenuItem(title: "", action: #selector(clockInFromMenu), keyEquivalent: "")
            clockInItem.attributedTitle = highlightedTitle(en ? "▶ Clock In (workday starts)" : "▶ 上班打卡（自动开始计时）")
            clockInItem.target = self
            menu.addItem(clockInItem)
        }
        let statsItem = NSMenuItem(title: en ? "Work Stats..." : "工作统计...", action: #selector(openWorkStats), keyEquivalent: "")
        statsItem.target = self
        menu.addItem(statsItem)
        menu.addItem(.separator())

        let showHide = NSMenuItem(title: en ? "Show / Hide Cat" : "显示 / 隐藏猫咪", action: #selector(toggleCat), keyEquivalent: "")
        showHide.target = self
        menu.addItem(showHide)
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        let modeItem = NSMenuItem(title: en ? "Mode" : "当前模式", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        for mode in GlobalMode.allCases {
            let item = NSMenuItem(title: mode.displayName(lang: L), action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.state = settings.globalMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        menu.addItem(modeItem)
        menu.addItem(.separator())


        let reminderItem = NSMenuItem(title: en ? "Reminders" : "提醒", action: nil, keyEquivalent: "")
        let reminderMenu = NSMenu()
        reminderItem.submenu = reminderMenu
        for (index, item) in settings.reminders.enumerated() {
            let label = en ? "\(item.name) (\(item.intervalMinutes) min)" : "\(item.name)（\(item.intervalMinutes)分钟）"
            let mi = NSMenuItem(title: label, action: #selector(toggleReminderItem(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = index
            mi.state = item.enabled ? .on : .off
            reminderMenu.addItem(mi)
        }
        reminderMenu.addItem(.separator())
        let editItem = NSMenuItem(title: en ? "Edit Reminders..." : "编辑提醒...", action: #selector(openEditReminders), keyEquivalent: "")
        editItem.target = self
        reminderMenu.addItem(editItem)
        let addItem = NSMenuItem(title: en ? "Add Reminder..." : "添加提醒...", action: #selector(openAddReminder), keyEquivalent: "")
        addItem.target = self
        reminderMenu.addItem(addItem)
        menu.addItem(reminderItem)
        menu.addItem(.separator())

        let alarmItem = NSMenuItem(title: en ? "Alarms" : "闹钟", action: nil, keyEquivalent: "")
        let alarmMenu = NSMenu()
        alarmItem.submenu = alarmMenu
        for (index, alarm) in settings.alarms.enumerated() {
            let strengthLabel: String
            if let s = alarm.strengthOverride {
                strengthLabel = s == .hard ? (en ? "strong" : "强") : (en ? "soft" : "软")
            } else {
                strengthLabel = en ? "system" : "跟随系统"
            }
            let repeatLabel = ", " + alarm.weekdaysLabel(lang: L)
            let label = "\(alarm.name) \(alarm.timeString) [\(strengthLabel)\(repeatLabel)]"
            let mi = NSMenuItem(title: label, action: #selector(toggleAlarmItem(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = index
            mi.state = alarm.enabled ? .on : .off
            alarmMenu.addItem(mi)
        }
        alarmMenu.addItem(.separator())
        let editAlarmItem = NSMenuItem(title: en ? "Edit Alarms..." : "编辑闹钟...", action: #selector(openEditAlarms), keyEquivalent: "")
        editAlarmItem.target = self
        alarmMenu.addItem(editAlarmItem)
        let addAlarmItem = NSMenuItem(title: en ? "Add Alarm..." : "添加闹钟...", action: #selector(openAddAlarm), keyEquivalent: "")
        addAlarmItem.target = self
        alarmMenu.addItem(addAlarmItem)
        menu.addItem(alarmItem)
        menu.addItem(.separator())

        let alwaysOnTopItem = NSMenuItem(title: en ? "Always on Top" : "始终置顶", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = settings.alwaysOnTop ? .on : .off
        menu.addItem(alwaysOnTopItem)

        let walkItem = NSMenuItem(title: en ? "Allow Walking" : "允许走动", action: #selector(toggleWalking), keyEquivalent: "")
        walkItem.target = self
        walkItem.state = settings.walkingEnabled ? .on : .off
        menu.addItem(walkItem)

        let soundItem = NSMenuItem(title: en ? "Cat Sound" : "猫叫声音", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = settings.soundEnabled ? .on : .off
        menu.addItem(soundItem)

        let loginItem = NSMenuItem(title: en ? "Launch at Login" : "开机自启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(loginItem)
        let windowItem = NSMenuItem(title: en ? "Preferred Work Window..." : "设置工作时间窗...", action: #selector(openWorkWindowSettings), keyEquivalent: "")
        windowItem.target = self
        menu.addItem(windowItem)
        menu.addItem(.separator())

        let scaleLabel = NSMenuItem(title: en ? "Cat Size" : "猫咪大小", action: nil, keyEquivalent: "")
        scaleLabel.isEnabled = false
        menu.addItem(scaleLabel)
        let sliderItem = NSMenuItem()
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let slider = NSSlider(frame: NSRect(x: 20, y: 5, width: 160, height: 20))
        slider.minValue = 0.5
        slider.maxValue = 3.0
        slider.doubleValue = settings.catScale
        slider.target = self
        slider.action = #selector(catScaleChanged(_:))
        slider.isContinuous = true
        slider.trackFillColor = .controlAccentColor
        sliderView.addSubview(slider)
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        menu.addItem(.separator())

        let langMenu = NSMenu()
        let langItem = NSMenuItem(title: en ? "Language" : "语言", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.tag = lang.rawValue
            item.state = settings.language == lang ? .on : .off
            langMenu.addItem(item)
        }
        menu.addItem(langItem)
        menu.addItem(.separator())



        let testMenu = NSMenu()
        let testItem = NSMenuItem(title: en ? "Test" : "测试", action: nil, keyEquivalent: "")
        testItem.submenu = testMenu
        let testSoft = NSMenuItem(title: en ? "Test Soft Reminder" : "测试软提醒", action: #selector(testSoftReminder), keyEquivalent: "")
        testSoft.target = self
        testMenu.addItem(testSoft)
        let testHard = NSMenuItem(title: en ? "Test Strong Reminder" : "测试强提醒", action: #selector(testHardReminder), keyEquivalent: "")
        testHard.target = self
        testMenu.addItem(testHard)
        menu.addItem(testItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: en ? "Quit" : "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func refreshMenu() {
        statusItem.menu = buildMenu()
    }

    // MARK: - Cat Window

    private let defaultCatWindowSize = CGSize(width: 160, height: 110)
    private var catWindowSize = CGSize(width: 160, height: 110)

    private func setupCatWindow() {
        guard let screen = NSScreen.main else { return }
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - catWindowSize.width - 40,
            y: screen.visibleFrame.minY + 20
        )

        catWindow = CatWindow(
            contentRect: NSRect(origin: origin, size: catWindowSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        catWindow.isOpaque = false
        catWindow.backgroundColor = NSColor.white.withAlphaComponent(0.001)
        catWindow.level = settings.alwaysOnTop ? .floating : .normal
        catWindow.hasShadow = false
        catWindow.isMovableByWindowBackground = false
        catWindow.acceptsMouseMovedEvents = true
        catWindow.ignoresMouseEvents = false
        catWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let contentView = DraggableCatView(frame: NSRect(origin: .zero, size: catWindowSize))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.001).cgColor
        contentView.appDelegate = self

        catTextField = MouseTransparentTextField(labelWithString: CatFrames.idle[0])
        catTextField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        catTextField.textColor = .white
        catTextField.backgroundColor = .clear
        catTextField.drawsBackground = false
        catTextField.isBezeled = false
        catTextField.isEditable = false
        catTextField.isSelectable = false
        catTextField.maximumNumberOfLines = 0
        catTextField.frame = NSRect(x: 5, y: 5, width: 150, height: 100)
        catTextField.wantsLayer = true
        catTextField.layer?.shadowColor = NSColor.black.cgColor
        catTextField.layer?.shadowOffset = CGSize(width: 1, height: -1)
        catTextField.layer?.shadowRadius = 2
        catTextField.layer?.shadowOpacity = 0.8
        contentView.addSubview(catTextField)

        catImageView = MouseTransparentImageView(frame: NSRect(x: 5, y: 5, width: 150, height: 100))
        catImageView.imageScaling = .scaleProportionallyUpOrDown
        catImageView.isHidden = true
        contentView.addSubview(catImageView)

        zzzLabel = MouseTransparentTextField(labelWithString: "z")
        zzzLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        zzzLabel.textColor = .white
        zzzLabel.backgroundColor = .clear
        zzzLabel.drawsBackground = false
        zzzLabel.isBezeled = false
        zzzLabel.isEditable = false
        zzzLabel.isSelectable = false
        zzzLabel.wantsLayer = true
        zzzLabel.layer?.shadowColor = NSColor.black.cgColor
        zzzLabel.layer?.shadowOffset = CGSize(width: 1, height: -1)
        zzzLabel.layer?.shadowRadius = 2
        zzzLabel.layer?.shadowOpacity = 0.8
        zzzLabel.alphaValue = 0
        zzzLabel.frame = NSRect(x: 5, y: 80, width: 50, height: 25)
        contentView.addSubview(zzzLabel)

        exclamationLabel = MouseTransparentTextField(labelWithString: "!")
        exclamationLabel.font = NSFont.systemFont(ofSize: 24, weight: .heavy)
        exclamationLabel.textColor = .systemYellow
        exclamationLabel.backgroundColor = .clear
        exclamationLabel.drawsBackground = false
        exclamationLabel.isBezeled = false
        exclamationLabel.isEditable = false
        exclamationLabel.isSelectable = false
        exclamationLabel.wantsLayer = true
        exclamationLabel.layer?.shadowColor = NSColor.black.cgColor
        exclamationLabel.layer?.shadowOffset = CGSize(width: 1, height: -1)
        exclamationLabel.layer?.shadowRadius = 2
        exclamationLabel.layer?.shadowOpacity = 0.8
        exclamationLabel.alphaValue = 0
        exclamationLabel.frame = NSRect(x: 5, y: 80, width: 30, height: 30)
        contentView.addSubview(exclamationLabel)

        catWindow.contentView = contentView
        catWindow.orderFrontRegardless()

        checkForPNGSprites()
        startFrameAnimation()
    }

    private func checkForPNGSprites() {
        currentSpriteGroup = CatFrames.randomGroup(for: .idle)
        if let frames = CatFrames.pngFrames(for: .idle, group: currentSpriteGroup), !frames.isEmpty {
            usingPNG = true
            catTextField.isHidden = true
            catImageView.isHidden = false
            catImageView.image = frames[0]
            resizeCatWindow(for: frames[0])
        }
    }

    private func resizeCatWindow(for image: NSImage) {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }
        let scale = CGFloat(settings.catScale)
        let baseW: CGFloat = 160
        let baseH: CGFloat = 160
        let aspect = imgSize.width / imgSize.height
        var w: CGFloat
        var h: CGFloat
        if aspect >= 1 {
            w = baseW * scale
            h = w / aspect
        } else {
            h = baseH * scale
            w = h * aspect
        }
        let padding: CGFloat = 10
        catWindowSize = CGSize(width: w + padding, height: h + padding)
        let frame = catWindow.frame
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y - (catWindowSize.height - frame.height),
            width: catWindowSize.width,
            height: catWindowSize.height
        )
        catWindow.setFrame(newFrame, display: true)
        catWindow.contentView?.frame = NSRect(origin: .zero, size: catWindowSize)
        let inset: CGFloat = 5
        let contentRect = NSRect(x: inset, y: inset, width: catWindowSize.width - inset * 2, height: catWindowSize.height - inset * 2)
        catTextField.frame = contentRect
        catImageView.frame = contentRect
    }

    // MARK: - Frame Animation

    private func startFrameAnimation() {
        animTimer?.invalidate()
        frameIndex = 0
        let interval: TimeInterval
        switch catState {
        case .sleeping: interval = 0.8
        case .lyingDown: interval = 1.0
        case .walkingLeft, .walkingRight: interval = isRushing ? 0.1 : 0.25
        case .reminder: interval = 0.4
        case .dragged: interval = 0.3
        case .clicked: interval = 0.4
        case .attacking: interval = 0.2
        case .playing: interval = 0.5
        case .chasingTail: interval = 0.25
        case .bellyUp: interval = 0.6
        case .grooming: interval = 0.7
        default: interval = 0.6
        }

        animTimer = commonTimer(interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if self.usingPNG, let pf = CatFrames.pngFrames(for: self.catState, group: self.currentSpriteGroup), !pf.isEmpty {
                let nextFrame = self.frameIndex + 1
                if self.catState == .attacking && nextFrame >= pf.count {
                    timer.invalidate()
                    self.animTimer = nil
                    self.idleCounter = 0
                    self.setCatState(.idle)
                    return
                }
                self.frameIndex = nextFrame % pf.count
                self.catImageView.image = pf[self.frameIndex]
            } else {
                let frames = CatFrames.frames(for: self.catState)
                let nextFrame = self.frameIndex + 1
                if self.catState == .attacking && nextFrame >= frames.count {
                    timer.invalidate()
                    self.animTimer = nil
                    self.idleCounter = 0
                    self.setCatState(.idle)
                    return
                }
                self.frameIndex = nextFrame % frames.count
                self.catTextField.stringValue = frames[self.frameIndex]
            }
        }
    }

    func setCatState(_ state: CatState) {
        guard catState != state else { return }
        catState = state
        frameIndex = 0
        currentSpriteGroup = CatFrames.randomGroup(for: state)
        if usingPNG, let pf = CatFrames.pngFrames(for: state, group: currentSpriteGroup), !pf.isEmpty {
            catImageView.image = pf[0]
            if state != .dragged {
                resizeCatWindow(for: pf[0])
            }
        } else {
            catTextField.stringValue = CatFrames.frames(for: state)[0]
        }
        if state == .sleeping {
            startZzzAnimation()
        } else {
            stopZzzAnimation()
        }
        if state == .playing {
            startPlayWiggle()
        } else {
            stopPlayWiggle()
        }
        let showBang = state == .attacking && !CatFrames.hasDedicatedSprites(for: .attacking)
        if showBang {
            showExclamation()
        } else {
            hideExclamation()
        }
        startFrameAnimation()
    }

    private func startZzzAnimation() {
        zzzTimer?.invalidate()
        var zzzStep = 0
        let zzzTexts = ["z", "zZ", "zZz"]
        zzzLabel.alphaValue = 1
        zzzLabel.stringValue = zzzTexts[0]
        zzzTimer = commonTimer(0.8, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            zzzStep = (zzzStep + 1) % zzzTexts.count
            self.zzzLabel.stringValue = zzzTexts[zzzStep]
            let bounds = self.catWindow.frame.size
            let baseX = bounds.width * 0.7
            let baseY = bounds.height * 0.65
            let floatY = baseY + CGFloat(zzzStep) * 6
            self.zzzLabel.frame = NSRect(x: baseX, y: floatY, width: 50, height: 25)
            self.zzzLabel.alphaValue = zzzStep == 2 ? 0.6 : 1.0
        }
    }

    private func stopZzzAnimation() {
        zzzTimer?.invalidate()
        zzzTimer = nil
        zzzLabel.alphaValue = 0
    }

    // While playing, occasionally shuffle a little left or right so she looks
    // like a real cat chasing something rather than animating in place.
    // Only when walking is allowed; otherwise she plays in place.
    private func startPlayWiggle() {
        playWiggleTimer?.invalidate()
        guard settings.walkingEnabled else { return }
        playWiggleTimer = commonTimer(0.7, repeats: true) { [weak self] _ in
            guard let self = self, self.catState == .playing, self.settings.walkingEnabled,
                  let screen = NSScreen.main else { return }
            let vis = screen.visibleFrame
            let catSize = self.catWindow.frame.size
            let current = self.catWindow.frame.origin

            // Fresh coin flip each time: nudge a little left or right.
            let dir: CGFloat = Bool.random() ? 1 : -1
            let mag = CGFloat.random(in: 6...16)
            var newX = current.x + dir * mag
            newX = min(max(newX, vis.minX), vis.maxX - catSize.width)
            self.catWindow.setFrameOrigin(NSPoint(x: newX, y: current.y))
        }
    }

    private func stopPlayWiggle() {
        playWiggleTimer?.invalidate()
        playWiggleTimer = nil
    }

    private func showExclamation() {
        let bounds = catWindow.frame.size
        let x = bounds.width * 0.7
        let y = bounds.height * 0.7
        exclamationLabel.frame = NSRect(x: x, y: y, width: 30, height: 30)
        exclamationLabel.alphaValue = 1
    }

    private func hideExclamation() {
        exclamationLabel.alphaValue = 0
    }

    // MARK: - Behavior Loop (idle -> lying -> sleeping, occasional walk)

    private func startBehaviorLoop() {
        walkTimer = commonTimer(5, repeats: true) { [weak self] _ in
            guard let self = self, !self.isReminding else { return }
            if self.catState == .dragged || self.catState == .clicked || self.catState == .attacking { return }
            if self.settings.globalMode == .superDND {
                if self.catState != .sleeping { self.setCatState(.sleeping) }
                return
            }

            self.idleCounter += 1

            // Auto-end random activities
            if self.catState == .playing && self.idleCounter >= Int.random(in: 4...6) {
                self.idleCounter = 0
                self.setCatState(.idle)
                return
            }
            if self.catState == .chasingTail && self.idleCounter >= Int.random(in: 3...5) {
                self.idleCounter = 0
                self.setCatState(.idle)
                return
            }
            if self.catState == .bellyUp && self.idleCounter >= Int.random(in: 4...7) {
                self.idleCounter = 0
                self.setCatState(.idle)
                return
            }
            if self.catState == .grooming && self.idleCounter >= Int.random(in: 5...8) {
                self.idleCounter = 0
                self.setCatState(.idle)
                return
            }

            // From idle: random activity
            if self.catState == .idle {
                var actions: [(weight: Int, action: () -> Void)] = []
                if self.settings.walkingEnabled {
                    actions.append((6, { self.walkToRandomSpot() }))
                    actions.append((2, { self.suddenRush() }))
                }
                if CatFrames.hasDedicatedSprites(for: .playing) {
                    actions.append((3, { self.setCatState(.playing) }))
                }
                if CatFrames.hasDedicatedSprites(for: .chasingTail) {
                    actions.append((2, { self.setCatState(.chasingTail) }))
                }
                if CatFrames.hasDedicatedSprites(for: .bellyUp) {
                    actions.append((2, { self.setCatState(.bellyUp) }))
                }
                if CatFrames.hasDedicatedSprites(for: .grooming) {
                    actions.append((3, { self.setCatState(.grooming) }))
                }
                if !actions.isEmpty {
                    let totalWeight = actions.reduce(0) { $0 + $1.weight }
                    let roll = Int.random(in: 0..<totalWeight * 3)
                    var cumulative = 0
                    for (weight, action) in actions {
                        cumulative += weight
                        if roll < cumulative {
                            self.idleCounter = 0
                            action()
                            return
                        }
                    }
                }
            }

            // After ~30-50s idle → lie down
            if self.catState == .idle && self.idleCounter >= Int.random(in: 6...10) {
                self.setCatState(.lyingDown)
                return
            }

            // After ~40-80s lying → fall asleep
            if self.catState == .lyingDown && self.idleCounter >= Int.random(in: 14...26) {
                self.setCatState(.sleeping)
                return
            }

            // After ~3-5 min sleeping → wake up
            if self.catState == .sleeping && self.idleCounter >= Int.random(in: 36...60) {
                self.idleCounter = 0
                self.setCatState(.idle)
                return
            }
        }
    }

    // MARK: - Walking

    private func walkToRandomSpot() {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let catSize = catWindow.frame.size

        let targetX = CGFloat.random(in: vis.minX...(vis.maxX - catSize.width))
        let targetY = CGFloat.random(in: vis.minY...(vis.maxY - catSize.height))
        let target = NSPoint(x: targetX, y: targetY)

        let goingRight = target.x > catWindow.frame.origin.x
        setCatState(goingRight ? .walkingRight : .walkingLeft)

        animateWalkTo(target, leavePawPrints: true) { [weak self] in
            self?.idleCounter = 0
            self?.setCatState(.idle)
        }
    }

    // A sudden excited dash: 1-3 fast bursts with a brief pause between them,
    // like a real cat getting the zoomies.
    private func suddenRush() {
        guard settings.walkingEnabled, NSScreen.main != nil else {
            idleCounter = 0
            setCatState(.idle)
            return
        }
        isRushing = true
        performRushSegment(remaining: Int.random(in: 1...3))
    }

    private func performRushSegment(remaining: Int) {
        guard remaining > 0, let screen = NSScreen.main else {
            isRushing = false
            idleCounter = 0
            setCatState(.idle)
            return
        }
        let vis = screen.visibleFrame
        let catSize = catWindow.frame.size
        let current = catWindow.frame.origin

        let dashDist = CGFloat.random(in: 200...440)
        let roomRight = (vis.maxX - catSize.width) - current.x
        let roomLeft = current.x - vis.minX
        let goRight: Bool
        if roomRight < dashDist * 0.4 {
            goRight = false
        } else if roomLeft < dashDist * 0.4 {
            goRight = true
        } else {
            goRight = Bool.random()
        }
        var targetX = goRight ? current.x + dashDist : current.x - dashDist
        targetX = min(max(targetX, vis.minX), vis.maxX - catSize.width)
        var targetY = current.y + CGFloat.random(in: -30...30)
        targetY = min(max(targetY, vis.minY), vis.maxY - catSize.height)
        let target = NSPoint(x: targetX, y: targetY)

        setCatState(goRight ? .walkingRight : .walkingLeft)
        animateWalkTo(target, leavePawPrints: true, fast: true) { [weak self] in
            guard let self = self else { return }
            self.setCatState(.idle)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.2...0.55)) {
                // Abort the rush if the cat got dragged, reminded, or clicked mid-dash.
                guard self.isRushing, self.catState == .idle, !self.isReminding else {
                    self.isRushing = false
                    return
                }
                self.performRushSegment(remaining: remaining - 1)
            }
        }
    }

    private func animateWalkTo(_ target: NSPoint, leavePawPrints: Bool, fast: Bool = false, completion: @escaping () -> Void) {
        let current = catWindow.frame.origin
        let dx = target.x - current.x
        let dy = target.y - current.y
        let distance = sqrt(dx * dx + dy * dy)
        let speed = fast ? CGFloat.random(in: 9...14) : CGFloat.random(in: 2.5...8.0)
        let steps = max(Int(distance / speed), 1)
        let dirX = dx / distance
        let dirY = dy / distance
        var step = 0
        var pawCounter = 0
        let interval: TimeInterval = fast ? 0.016 : 0.025

        walkAnimTimer?.invalidate()
        walkAnimTimer = commonTimer(interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            step += 1
            if step >= steps {
                timer.invalidate()
                self.walkAnimTimer = nil
                self.catWindow.setFrameOrigin(target)
                completion()
                return
            }
            let t = CGFloat(step) / CGFloat(steps)
            // Rush: burst out fast, decelerate into an abrupt stop (ease-out).
            // Normal walk: smooth ease-in-out.
            let eased = fast
                ? 1 - pow(1 - t, 3)
                : (t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
            let traveled = eased * distance
            let newX = current.x + dirX * traveled
            let newY = current.y + dirY * traveled
            self.catWindow.setFrameOrigin(NSPoint(x: newX, y: newY))

            if leavePawPrints {
                pawCounter += 1
                if pawCounter % 15 == 0 {
                    self.dropPawPrint(at: NSPoint(x: newX + 80, y: newY + 5))
                }
            }
        }
    }

    // MARK: - Drag

    private var draggedWindowHeight: CGFloat {
        catWindowSize.height * 1.3
    }

    private func playRandomSound() {
        guard settings.soundEnabled, settings.globalMode != .superDND else { return }
        let sound: NSSound?
        if !customSounds.isEmpty {
            sound = customSounds.randomElement()
        } else {
            sound = NSSound(named: "Purr")
        }
        sound?.volume = 0.3
        sound?.play()
    }

    func onClicked() {
        if isReminding { return }
        guard catState != .attacking else { return }
        // Don't hijack an in-progress walk/rush with click logic.
        if catState == .walkingLeft || catState == .walkingRight { return }
        isRushing = false
        walkAnimTimer?.invalidate()
        walkAnimTimer = nil

        // ~18% chance she just gets startled and scurries off instead of engaging.
        if settings.walkingEnabled, Int.random(in: 0..<100) < 18 {
            clickCount = 0
            attackThreshold = Int.random(in: 5...15)
            playRandomSound()
            walkAwayShort()
            return
        }

        clickCount += 1

        if clickCount >= attackThreshold {
            clickCount = 0
            attackThreshold = Int.random(in: 5...15)
            playRandomSound()
            setCatState(.attacking)
            return
        }
    }

    // A short, quick scurry away from the cursor — used when a click startles her.
    private func walkAwayShort() {
        guard let screen = NSScreen.main else {
            setCatState(.idle)
            return
        }
        let vis = screen.visibleFrame
        let catSize = catWindow.frame.size
        let current = catWindow.frame.origin

        let dist = CGFloat.random(in: 120...260)
        let roomRight = (vis.maxX - catSize.width) - current.x
        let roomLeft = current.x - vis.minX
        let goRight: Bool
        if roomRight < dist {
            goRight = false
        } else if roomLeft < dist {
            goRight = true
        } else {
            goRight = Bool.random()
        }
        var targetX = goRight ? current.x + dist : current.x - dist
        targetX = min(max(targetX, vis.minX), vis.maxX - catSize.width)
        let target = NSPoint(x: targetX, y: current.y)

        setCatState(goRight ? .walkingRight : .walkingLeft)
        animateWalkTo(target, leavePawPrints: true, fast: true) { [weak self] in
            self?.idleCounter = 0
            self?.setCatState(.idle)
        }
    }

    func onDragStart() {
        if isReminding && isFocusOverlay {
            playRandomSound()
            walkAnimTimer?.invalidate()
            walkAnimTimer = nil
            scaleTimer?.invalidate()
            scaleTimer = nil
            return
        }
        stateBeforeDrag = catState
        isRushing = false
        walkAnimTimer?.invalidate()
        walkAnimTimer = nil
        playRandomSound()
        setCatState(.dragged)
        let frame = catWindow.frame
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y - (draggedWindowHeight - catWindowSize.height),
            width: catWindowSize.width,
            height: draggedWindowHeight
        )
        catWindow.setFrame(newFrame, display: true)
        let inset: CGFloat = 5
        let contentRect = NSRect(x: inset, y: inset, width: newFrame.width - inset * 2, height: newFrame.height - inset * 2)
        catTextField.frame = contentRect
        catImageView.frame = contentRect
    }

    func onDragEnd() {
        if isReminding && isFocusOverlay {
            if overlayWindow == nil, let item = pendingOverlayItem, let screen = pendingOverlayScreen {
                // drag interrupted the scale-up — show the card where the cat was dropped
                if originalCatWindowFrame == nil { originalCatWindowFrame = catWindow.frame }
                setCatState(.reminder)
                showBlockingOverlay(item, screen: screen)
            } else if var original = originalCatWindowFrame {
                let current = catWindow.frame
                original.origin = NSPoint(
                    x: current.midX - original.width / 2,
                    y: current.midY - original.height / 2
                )
                originalCatWindowFrame = original
            }
            return
        }
        idleCounter = 0
        let wasWalking = stateBeforeDrag == .walkingLeft || stateBeforeDrag == .walkingRight
        stateBeforeDrag = nil

        let frame = catWindow.frame
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y + (draggedWindowHeight - catWindowSize.height),
            width: catWindowSize.width,
            height: catWindowSize.height
        )
        catWindow.setFrame(newFrame, display: true)

        if wasWalking {
            walkToRandomSpot()
        } else {
            setCatState(.idle)
            layoutCatContent()
        }
    }

    // MARK: - Paw Prints

    private func dropPawPrint(at point: NSPoint) {
        let pawSize = NSSize(width: 30, height: 16)
        let pawWindow = NSWindow(
            contentRect: NSRect(origin: point, size: pawSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        pawWindow.isOpaque = false
        pawWindow.backgroundColor = .clear
        pawWindow.level = .floating
        pawWindow.hasShadow = false
        pawWindow.ignoresMouseEvents = true

        if let pawImg = CatFrames.pawPrintImage() {
            let imgView = NSImageView(frame: NSRect(origin: .zero, size: pawSize))
            imgView.image = pawImg
            pawWindow.contentView = imgView
        } else {
            let label = NSTextField(labelWithString: CatFrames.pawPrint)
            label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            label.textColor = NSColor.white.withAlphaComponent(0.5)
            label.backgroundColor = .clear
            label.drawsBackground = false
            label.isBezeled = false
            label.frame = NSRect(origin: .zero, size: pawSize)
            pawWindow.contentView = label
        }

        pawWindow.orderFrontRegardless()
        pawPrintWindows.append(pawWindow)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 1.0
                pawWindow.animator().alphaValue = 0
            }, completionHandler: {
                pawWindow.orderOut(nil)
                self?.pawPrintWindows.removeAll { $0 === pawWindow }
            })
        }
    }

    // MARK: - Soft Reminder

    private func showSoftReminder(_ item: ReminderItem) {
        guard !isReminding else { return }
        isReminding = true
        isSoftReminderActive = true
        dismissBubble()

        let label = NSTextField(labelWithString: item.shortMessage)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .black
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.isBezeled = false
        label.alignment = .center
        label.sizeToFit()

        let padding: CGFloat = 24
        let bubbleW = label.frame.width + padding
        let bubbleH: CGFloat = 32

        let catFrame = catWindow.frame
        let bx = catFrame.midX - bubbleW / 2
        var by = catFrame.maxY + 6
        if let hud = focusHUDWindow, focusManager.currentSession != nil {
            by = hud.frame.maxY + 6
        }

        let bw = NSWindow(
            contentRect: NSRect(x: bx, y: by, width: bubbleW, height: bubbleH),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        bw.isOpaque = false
        bw.backgroundColor = .clear
        bw.level = .floating
        bw.hasShadow = false
        bw.ignoresMouseEvents = true
        bw.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let bgView = NSView(frame: NSRect(x: 0, y: 0, width: bubbleW, height: bubbleH))
        bgView.wantsLayer = true
        bgView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        bgView.layer?.cornerRadius = 10

        label.frame = NSRect(x: padding / 2, y: 4, width: label.frame.width, height: 22)
        bgView.addSubview(label)
        bw.contentView = bgView
        bw.orderFrontRegardless()
        bubbleWindow = bw

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.dismissSoftReminder()
        }
    }

    private func dismissBubble() {
        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil
    }

    private func dismissSoftReminder() {
        dismissBubble()
        isReminding = false
        isSoftReminderActive = false
    }

    // MARK: - Hard Reminder

    private func showHardReminder(_ item: ReminderItem) {
        guard !isReminding else { return }
        dismissBubble()
        isReminding = true
        activeHardReminderItem = item

        playRandomSound()

        guard let screen = NSScreen.main else {
            isReminding = false
            activeHardReminderItem = nil
            return
        }
        pendingOverlayItem = item
        pendingOverlayScreen = screen

        // Focus clock cards scale up right where the cat is — no walk to
        // center, so the cat never fights the drag or freezes mid-path
        if isFocusOverlay {
            setCatState(.reminder)
            originalCatWindowFrame = catWindow.frame
            animateScaleUp(screen: screen, item: item)
            return
        }

        let catSize = catWindow.frame.size
        let goingRight = screen.frame.midX > catWindow.frame.origin.x
        setCatState(goingRight ? .walkingRight : .walkingLeft)

        let centerTarget = NSPoint(
            x: screen.frame.midX - catSize.width / 2,
            y: screen.frame.midY + 20
        )

        animateWalkTo(centerTarget, leavePawPrints: true) { [weak self] in
            guard let self = self, self.isReminding else { return }
            self.setCatState(.reminder)
            self.originalCatWindowFrame = self.catWindow.frame
            self.animateScaleUp(screen: screen, item: item)
        }
    }

    private func animateScaleUp(screen: NSScreen, item: ReminderItem) {
        let targetScale: CGFloat = 3.0
        let steps = 8
        let originalFrame = catWindow.frame
        var step = 0

        scaleTimer = commonTimer(0.06, repeats: true) { [weak self] timer in
            guard let self = self, self.isReminding else { timer.invalidate(); return }
            step += 1
            if step >= steps {
                timer.invalidate()
                self.scaleTimer = nil
                let finalW = originalFrame.width * targetScale
                let finalH = originalFrame.height * targetScale
                let finalX = originalFrame.midX - finalW / 2
                let finalY = originalFrame.midY - finalH / 2
                self.catWindow.setFrame(NSRect(x: finalX, y: finalY, width: finalW, height: finalH), display: true)
                self.layoutCatContent()
                self.showBlockingOverlay(item, screen: screen)
                return
            }
            let t = CGFloat(step) / CGFloat(steps)
            let eased = t * t * (3 - 2 * t)
            let scale = 1.0 + (targetScale - 1.0) * eased
            let newW = originalFrame.width * scale
            let newH = originalFrame.height * scale
            let newX = originalFrame.midX - newW / 2
            let newY = originalFrame.midY - newH / 2
            self.catWindow.setFrame(NSRect(x: newX, y: newY, width: newW, height: newH), display: true)
            self.layoutCatContent()
        }
    }

    private func layoutCatContent() {
        let bounds = catWindow.contentView?.bounds ?? .zero
        let inset: CGFloat = 5
        let contentRect = NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: bounds.height - inset * 2)
        catTextField.frame = contentRect
        let fontSize = min(bounds.height / 8, bounds.width / 12)
        catTextField.font = NSFont.monospacedSystemFont(ofSize: max(fontSize, 14), weight: .regular)
        catImageView.frame = contentRect
        repositionFocusHUD()
    }

    private func restoreCatWindowSize() {
        guard let original = originalCatWindowFrame else {
            setCatState(sleepAfterOverlay ? .sleeping : .idle)
            sleepAfterOverlay = false
            return
        }
        scaleTimer?.invalidate()
        scaleTimer = nil

        let steps = 6
        let currentFrame = catWindow.frame
        var step = 0

        commonTimer(0.04, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            step += 1
            if step >= steps {
                timer.invalidate()
                self.catWindow.setFrame(original, display: true)
                self.originalCatWindowFrame = nil
                self.setCatState(self.sleepAfterOverlay ? .sleeping : .idle)
                self.sleepAfterOverlay = false
                return
            }
            let t = CGFloat(step) / CGFloat(steps)
            let eased = t * t * (3 - 2 * t)
            let newW = currentFrame.width + (original.width - currentFrame.width) * eased
            let newH = currentFrame.height + (original.height - currentFrame.height) * eased
            let newX = currentFrame.midX + (original.midX - currentFrame.midX) * eased - newW / 2
            let newY = currentFrame.midY + (original.midY - currentFrame.midY) * eased - newH / 2
            self.catWindow.setFrame(NSRect(x: newX, y: newY, width: newW, height: newH), display: true)
            self.layoutCatContent()
        }
    }

    private func showBlockingOverlay(_ item: ReminderItem, screen: NSScreen) {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil

        let sf = screen.frame

        let overlay = OverlayWindow(
            contentRect: sf,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlay.isOpaque = false
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0.4)
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlay.ignoresMouseEvents = false

        let cv = NSView(frame: NSRect(origin: .zero, size: sf.size))
        cv.wantsLayer = true

        let cardW: CGFloat = 360
        let cardH: CGFloat = 180
        let catFrame = catWindow.frame
        let cardY = catFrame.origin.y - sf.origin.y - cardH - 20
        let cardX = catFrame.midX - sf.origin.x - cardW / 2

        let card = NSView(frame: NSRect(x: max(20, cardX), y: max(20, cardY), width: cardW, height: cardH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 16
        card.shadow = NSShadow()
        card.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        card.layer?.shadowOffset = CGSize(width: 0, height: -2)
        card.layer?.shadowRadius = 10
        card.layer?.shadowOpacity = 1
        cv.addSubview(card)

        let msg = NSTextField(labelWithString: item.urgentMessage)
        msg.font = .systemFont(ofSize: item.urgentMessage.count > 12 ? 18 : 24, weight: .bold)
        msg.textColor = .black
        msg.backgroundColor = .clear
        msg.drawsBackground = false
        msg.isBezeled = false
        msg.alignment = .center
        msg.frame = NSRect(x: 20, y: cardH - 60, width: cardW - 40, height: 40)
        card.addSubview(msg)

        let btn = NSButton(title: hardReminderButtonTitle ?? (L == .english ? "Got it!" : "知道了！"), target: self, action: #selector(dismissHardReminder))
        btn.font = .systemFont(ofSize: 16, weight: .medium)
        btn.bezelStyle = .rounded
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0).cgColor
        btn.layer?.cornerRadius = 10
        btn.contentTintColor = .white
        btn.frame = NSRect(x: (cardW - 200) / 2, y: 55, width: 200, height: 40)
        card.addSubview(btn)

        let showSnooze = hardReminderShowsSnooze && (activeHardAlarmItem?.snoozeEnabled ?? true)
        if showSnooze {
            let laterBtn = NSButton(title: L == .english ? "Remind in 5 min" : "5分钟后再提醒", target: self, action: #selector(snoozeReminder))
            laterBtn.font = .systemFont(ofSize: 13)
            laterBtn.bezelStyle = .rounded
            laterBtn.isBordered = false
            laterBtn.wantsLayer = true
            laterBtn.layer?.backgroundColor = NSColor(white: 0.92, alpha: 1.0).cgColor
            laterBtn.layer?.cornerRadius = 8
            laterBtn.contentTintColor = .darkGray
            laterBtn.frame = NSRect(x: (cardW - 200) / 2, y: 14, width: 200, height: 30)
            card.addSubview(laterBtn)
        }

        overlay.contentView = cv
        overlay.orderFrontRegardless()
        overlay.makeKeyAndOrderFront(nil)
        overlayWindow = overlay

        // One level above the overlay: even if the overlay gets clicked and
        // raised within its own level, the cat stays on top and draggable
        catWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        catWindow.orderFrontRegardless()
    }

    @objc func dismissHardReminderPublic() {
        dismissHardReminder()
    }

    @objc private func dismissHardReminder() {
        walkAnimTimer?.invalidate()
        walkAnimTimer = nil
        scaleTimer?.invalidate()
        scaleTimer = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        activeHardReminderItem = nil
        activeHardAlarmItem = nil
        hardReminderShowsSnooze = true
        hardReminderButtonTitle = nil
        isFocusOverlay = false
        pendingOverlayItem = nil
        pendingOverlayScreen = nil
        catWindow.level = settings.alwaysOnTop ? .floating : .normal
        isReminding = false
        idleCounter = 0
        restoreCatWindowSize()
    }

    @objc private func snoozeReminder() {
        if let alarm = activeHardAlarmItem {
            dismissHardReminder()
            alarmManager.snooze(alarm)
        } else {
            let items = settings.reminders
            let snoozedItem = items.first(where: { $0.enabled })
            dismissHardReminder()
            if let item = snoozedItem {
                DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
                    self?.showHardReminder(item)
                }
            }
        }
    }

    // MARK: - Reminder Entry

    func showReminder(_ item: ReminderItem, strength: ReminderStrength) {
        guard !isReminding else { return }
        if strength == .soft {
            showSoftReminder(item)
        } else {
            showHardReminder(item)
        }
    }

    // MARK: - Test

    @objc private func testSoftReminder() {
        let en = L == .english
        let item = settings.reminders.first ?? ReminderItem(id: UUID(), name: en ? "Test" : "测试", shortMessage: en ? "Soft reminder test~" : "测试软提醒~", urgentMessage: en ? "⚠️ Test!" : "⚠️ 测试！", intervalMinutes: 1, enabled: true)
        showSoftReminder(item)
    }

    @objc private func testHardReminder() {
        let en = L == .english
        let item = settings.reminders.first ?? ReminderItem(id: UUID(), name: en ? "Test" : "测试", shortMessage: en ? "Test~" : "测试~", urgentMessage: en ? "⚠️ Strong reminder test!" : "⚠️ 测试强提醒！", intervalMinutes: 1, enabled: true)
        showHardReminder(item)
    }

    // MARK: - Edit Reminders

    @objc private func openEditReminders() {
        let en = L == .english
        let items = settings.reminders
        guard !items.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = en ? "Edit Reminders" : "编辑提醒"
        alert.informativeText = en ? "Choose a reminder to edit:" : "选择要编辑的提醒项目："
        for item in items {
            alert.addButton(withTitle: item.name)
        }
        alert.addButton(withTitle: en ? "Delete Reminder..." : "删除提醒...")
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let response = alert.runModal()
        let idx = response.rawValue - 1000
        if idx < items.count {
            editReminderDialog(items[idx])
        } else if idx == items.count {
            deleteReminderDialog()
        }
    }

    private func editReminderDialog(_ item: ReminderItem) {
        let en = L == .english
        let alert = NSAlert()
        alert.messageText = (en ? "Edit: " : "编辑: ") + item.name
        alert.addButton(withTitle: en ? "Save" : "保存")
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        let labels = en ? ["Name:", "Soft message:", "Strong message:", "Interval (min):"] : ["名称:", "软提示文字:", "硬提示文字:", "间隔(分钟):"]
        let values = [item.name, item.shortMessage, item.urgentMessage, "\(item.intervalMinutes)"]
        var fields: [NSTextField] = []

        for (i, label) in labels.enumerated() {
            let y = CGFloat(160 - (i + 1) * 36)
            let lbl = NSTextField(labelWithString: label)
            lbl.frame = NSRect(x: 0, y: y, width: en ? 110 : 90, height: 24)
            container.addSubview(lbl)
            let field = NSTextField(string: values[i])
            field.frame = NSRect(x: en ? 115 : 95, y: y, width: en ? 180 : 200, height: 24)
            container.addSubview(field)
            fields.append(field)
        }

        alert.accessoryView = container
        if alert.runModal() == .alertFirstButtonReturn {
            var updated = item
            updated.name = fields[0].stringValue
            updated.shortMessage = fields[1].stringValue
            updated.urgentMessage = fields[2].stringValue
            updated.intervalMinutes = Int(fields[3].stringValue) ?? item.intervalMinutes
            settings.updateReminder(updated)
            reminderManager.rebuildTimers()
            refreshMenu()
        }
    }

    private func deleteReminderDialog() {
        let en = L == .english
        let items = settings.reminders
        let alert = NSAlert()
        alert.messageText = en ? "Delete Reminder" : "删除提醒"
        alert.informativeText = en ? "Choose a reminder to delete:" : "选择要删除的提醒："
        for item in items {
            alert.addButton(withTitle: (en ? "Delete " : "删除 ") + item.name)
        }
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let response = alert.runModal()
        let idx = response.rawValue - 1000
        if idx < items.count {
            settings.removeReminder(id: items[idx].id)
            reminderManager.rebuildTimers()
            refreshMenu()
        }
    }

    @objc private func openAddReminder() {
        let en = L == .english
        let alert = NSAlert()
        alert.messageText = en ? "Add Reminder" : "添加新提醒"
        alert.addButton(withTitle: en ? "Add" : "添加")
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        let labels = en ? ["Name:", "Soft message:", "Strong message:", "Interval (min):"] : ["名称:", "软提示文字:", "硬提示文字:", "间隔(分钟):"]
        let defaults = ["", "", "", "30"]
        var fields: [NSTextField] = []

        for (i, label) in labels.enumerated() {
            let y = CGFloat(160 - (i + 1) * 36)
            let lbl = NSTextField(labelWithString: label)
            lbl.frame = NSRect(x: 0, y: y, width: en ? 110 : 90, height: 24)
            container.addSubview(lbl)
            let field = NSTextField(string: defaults[i])
            field.frame = NSRect(x: en ? 115 : 95, y: y, width: en ? 180 : 200, height: 24)
            field.placeholderString = labels[i].replacingOccurrences(of: ":", with: "")
            container.addSubview(field)
            fields.append(field)
        }

        alert.accessoryView = container
        if alert.runModal() == .alertFirstButtonReturn {
            let name = fields[0].stringValue
            guard !name.isEmpty else { return }
            let item = ReminderItem(
                id: UUID(),
                name: name,
                shortMessage: fields[1].stringValue.isEmpty ? "\(name)~" : fields[1].stringValue,
                urgentMessage: fields[2].stringValue.isEmpty ? "⚠️ \(name)！" : fields[2].stringValue,
                intervalMinutes: Int(fields[3].stringValue) ?? 30,
                enabled: true
            )
            settings.addReminder(item)
            reminderManager.rebuildTimers()
            refreshMenu()
        }
    }

    // MARK: - Alarm UI

    @objc private func toggleAlarmItem(_ sender: NSMenuItem) {
        let items = settings.alarms
        guard sender.tag < items.count else { return }
        settings.toggleAlarm(id: items[sender.tag].id)
        alarmManager.rebuildAlarms()
        refreshMenu()
    }

    @objc private func openAddAlarm() {
        let en = L == .english
        let alert = NSAlert()
        alert.messageText = en ? "Add Alarm" : "添加闹钟"
        alert.addButton(withTitle: en ? "Add" : "添加")
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 230))

        let nameLabel = NSTextField(labelWithString: en ? "Name:" : "名称:")
        nameLabel.frame = NSRect(x: 0, y: 200, width: 90, height: 24)
        container.addSubview(nameLabel)
        let nameField = NSTextField(string: "")
        nameField.frame = NSRect(x: 95, y: 200, width: 240, height: 24)
        nameField.placeholderString = en ? "Alarm name" : "闹钟名称"
        container.addSubview(nameField)

        let msgLabel = NSTextField(labelWithString: en ? "Message:" : "提示文字:")
        msgLabel.frame = NSRect(x: 0, y: 168, width: 90, height: 24)
        container.addSubview(msgLabel)
        let msgField = NSTextField(string: "")
        msgField.frame = NSRect(x: 95, y: 168, width: 240, height: 24)
        msgField.placeholderString = en ? "Reminder message" : "提示文字"
        container.addSubview(msgField)

        let timeLabel = NSTextField(labelWithString: en ? "Time:" : "时间:")
        timeLabel.frame = NSRect(x: 0, y: 136, width: 90, height: 24)
        container.addSubview(timeLabel)
        let hourField = NSTextField(string: "09")
        hourField.frame = NSRect(x: 95, y: 136, width: 40, height: 24)
        container.addSubview(hourField)
        let colonLabel = NSTextField(labelWithString: ":")
        colonLabel.frame = NSRect(x: 138, y: 136, width: 10, height: 24)
        container.addSubview(colonLabel)
        let minField = NSTextField(string: "00")
        minField.frame = NSRect(x: 152, y: 136, width: 40, height: 24)
        container.addSubview(minField)

        let strengthLabel = NSTextField(labelWithString: en ? "Strength:" : "提醒强度:")
        strengthLabel.frame = NSRect(x: 0, y: 104, width: 90, height: 24)
        container.addSubview(strengthLabel)
        let strengthPopup = NSPopUpButton(frame: NSRect(x: 95, y: 102, width: 160, height: 28))
        strengthPopup.addItems(withTitles: en ? ["Follow system", "Soft", "Strong"] : ["跟随系统", "软提醒", "强提醒"])
        container.addSubview(strengthPopup)

        let daysLabel = NSTextField(labelWithString: en ? "Days:" : "重复:")
        daysLabel.frame = NSRect(x: 0, y: 72, width: 90, height: 24)
        container.addSubview(daysLabel)
        let dayOrder = [2, 3, 4, 5, 6, 7, 1]
        let dayTitles = en ? ["M", "T", "W", "T", "F", "S", "S"] : ["一", "二", "三", "四", "五", "六", "日"]
        var dayChecks: [NSButton] = []
        for (i, wd) in dayOrder.enumerated() {
            let cb = NSButton(checkboxWithTitle: dayTitles[i], target: nil, action: nil)
            cb.frame = NSRect(x: 95 + i * 34, y: 72, width: 34, height: 24)
            cb.state = .on
            cb.tag = wd
            container.addSubview(cb)
            dayChecks.append(cb)
        }

        let snoozeCheck = NSButton(checkboxWithTitle: en ? "Allow snooze (5 min)" : "允许贪睡（5分钟）", target: nil, action: nil)
        snoozeCheck.frame = NSRect(x: 95, y: 44, width: 240, height: 24)
        snoozeCheck.state = .on
        container.addSubview(snoozeCheck)

        alert.accessoryView = container
        if alert.runModal() == .alertFirstButtonReturn {
            let name = nameField.stringValue
            guard !name.isEmpty else { return }
            let hour = max(0, min(23, Int(hourField.stringValue) ?? 9))
            let minute = max(0, min(59, Int(minField.stringValue) ?? 0))
            let strengthOverride: ReminderStrength?
            switch strengthPopup.indexOfSelectedItem {
            case 1: strengthOverride = .soft
            case 2: strengthOverride = .hard
            default: strengthOverride = nil
            }
            let selectedDays = dayChecks.filter { $0.state == .on }.map { $0.tag }.sorted()
            let alarm = AlarmItem(
                id: UUID(),
                name: name,
                message: msgField.stringValue.isEmpty ? "\(name)!" : msgField.stringValue,
                hour: hour,
                minute: minute,
                strengthOverride: strengthOverride,
                repeatDaily: selectedDays.count == 7,
                weekdays: selectedDays,
                snoozeEnabled: snoozeCheck.state == .on,
                enabled: true
            )
            settings.addAlarm(alarm)
            alarmManager.rebuildAlarms()
            refreshMenu()
        }
    }

    @objc private func openEditAlarms() {
        let en = L == .english
        let items = settings.alarms
        guard !items.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = en ? "Edit Alarms" : "编辑闹钟"
        alert.informativeText = en ? "Choose an alarm to edit:" : "选择要编辑的闹钟："
        for alarm in items {
            alert.addButton(withTitle: "\(alarm.name) \(alarm.timeString)")
        }
        alert.addButton(withTitle: en ? "Delete Alarm..." : "删除闹钟...")
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let response = alert.runModal()
        let idx = response.rawValue - 1000
        if idx < items.count {
            editAlarmDialog(items[idx])
        } else if idx == items.count {
            deleteAlarmDialog()
        }
    }

    private func editAlarmDialog(_ alarm: AlarmItem) {
        let en = L == .english
        let alert = NSAlert()
        alert.messageText = (en ? "Edit: " : "编辑: ") + alarm.name
        alert.addButton(withTitle: en ? "Save" : "保存")
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 230))

        let nameLabel = NSTextField(labelWithString: en ? "Name:" : "名称:")
        nameLabel.frame = NSRect(x: 0, y: 200, width: 90, height: 24)
        container.addSubview(nameLabel)
        let nameField = NSTextField(string: alarm.name)
        nameField.frame = NSRect(x: 95, y: 200, width: 240, height: 24)
        container.addSubview(nameField)

        let msgLabel = NSTextField(labelWithString: en ? "Message:" : "提示文字:")
        msgLabel.frame = NSRect(x: 0, y: 168, width: 90, height: 24)
        container.addSubview(msgLabel)
        let msgField = NSTextField(string: alarm.message)
        msgField.frame = NSRect(x: 95, y: 168, width: 240, height: 24)
        container.addSubview(msgField)

        let timeLabel = NSTextField(labelWithString: en ? "Time:" : "时间:")
        timeLabel.frame = NSRect(x: 0, y: 136, width: 90, height: 24)
        container.addSubview(timeLabel)
        let hourField = NSTextField(string: String(format: "%02d", alarm.hour))
        hourField.frame = NSRect(x: 95, y: 136, width: 40, height: 24)
        container.addSubview(hourField)
        let colonLabel = NSTextField(labelWithString: ":")
        colonLabel.frame = NSRect(x: 138, y: 136, width: 10, height: 24)
        container.addSubview(colonLabel)
        let minField = NSTextField(string: String(format: "%02d", alarm.minute))
        minField.frame = NSRect(x: 152, y: 136, width: 40, height: 24)
        container.addSubview(minField)

        let strengthLabel = NSTextField(labelWithString: en ? "Strength:" : "提醒强度:")
        strengthLabel.frame = NSRect(x: 0, y: 104, width: 90, height: 24)
        container.addSubview(strengthLabel)
        let strengthPopup = NSPopUpButton(frame: NSRect(x: 95, y: 102, width: 160, height: 28))
        strengthPopup.addItems(withTitles: en ? ["Follow system", "Soft", "Strong"] : ["跟随系统", "软提醒", "强提醒"])
        if let s = alarm.strengthOverride {
            strengthPopup.selectItem(at: s == .soft ? 1 : 2)
        }
        container.addSubview(strengthPopup)

        let daysLabel = NSTextField(labelWithString: en ? "Days:" : "重复:")
        daysLabel.frame = NSRect(x: 0, y: 72, width: 90, height: 24)
        container.addSubview(daysLabel)
        let dayOrder = [2, 3, 4, 5, 6, 7, 1]
        let dayTitles = en ? ["M", "T", "W", "T", "F", "S", "S"] : ["一", "二", "三", "四", "五", "六", "日"]
        var dayChecks: [NSButton] = []
        for (i, wd) in dayOrder.enumerated() {
            let cb = NSButton(checkboxWithTitle: dayTitles[i], target: nil, action: nil)
            cb.frame = NSRect(x: 95 + i * 34, y: 72, width: 34, height: 24)
            cb.state = alarm.effectiveWeekdays.contains(wd) ? .on : .off
            cb.tag = wd
            container.addSubview(cb)
            dayChecks.append(cb)
        }

        let snoozeCheck = NSButton(checkboxWithTitle: en ? "Allow snooze (5 min)" : "允许贪睡（5分钟）", target: nil, action: nil)
        snoozeCheck.frame = NSRect(x: 95, y: 44, width: 240, height: 24)
        snoozeCheck.state = alarm.snoozeEnabled ? .on : .off
        container.addSubview(snoozeCheck)

        alert.accessoryView = container
        if alert.runModal() == .alertFirstButtonReturn {
            var updated = alarm
            updated.name = nameField.stringValue
            updated.message = msgField.stringValue
            updated.hour = max(0, min(23, Int(hourField.stringValue) ?? alarm.hour))
            updated.minute = max(0, min(59, Int(minField.stringValue) ?? alarm.minute))
            switch strengthPopup.indexOfSelectedItem {
            case 1: updated.strengthOverride = .soft
            case 2: updated.strengthOverride = .hard
            default: updated.strengthOverride = nil
            }
            let selectedDays = dayChecks.filter { $0.state == .on }.map { $0.tag }.sorted()
            updated.repeatDaily = selectedDays.count == 7
            updated.weekdays = selectedDays
            updated.snoozeEnabled = snoozeCheck.state == .on
            settings.updateAlarm(updated)
            alarmManager.rebuildAlarms()
            refreshMenu()
        }
    }

    private func deleteAlarmDialog() {
        let en = L == .english
        let items = settings.alarms
        let alert = NSAlert()
        alert.messageText = en ? "Delete Alarm" : "删除闹钟"
        alert.informativeText = en ? "Choose an alarm to delete:" : "选择要删除的闹钟："
        for alarm in items {
            alert.addButton(withTitle: (en ? "Delete " : "删除 ") + alarm.name)
        }
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let response = alert.runModal()
        let idx = response.rawValue - 1000
        if idx < items.count {
            settings.removeAlarm(id: items[idx].id)
            alarmManager.rebuildAlarms()
            refreshMenu()
        }
    }

    // MARK: - Deep Focus (可选专注冲刺 — 不再承担"算不算工作"的判断)

    private func updateFocusMenuBar() {
        guard let button = statusItem?.button else { return }
        let duty = DutyManager.shared
        if let session = focusManager.currentSession {
            let sec = max(0, Int(Date().timeIntervalSince(session.start)))
            let clock = String(format: "%02d:%02d", sec / 60, sec % 60)
            button.title = " 🎯\(clock)"
        } else if duty.isOnBreak {
            button.title = " ☕️"
        } else if duty.isOnDuty {
            button.title = " ⏱" + compactCoarseHours(todayActiveMinutes())
        } else {
            button.title = ""
        }
    }

    private func compactCoarseHours(_ minutes: Int) -> String {
        if minutes < 30 { return "<0.5h" }
        let hours = Double(Int((Double(minutes) / 30.0).rounded())) / 2.0
        return hours == hours.rounded() ? "~\(Int(hours))h" : "~\(hours)h"
    }

    @objc private func openDeepFocus() {
        let en = L == .english
        let alert = NSAlert()
        alert.messageText = "🎯 Deep Focus"
        alert.informativeText = en
            ? "An optional sprint for rhythm — work counts either way."
            : "可选的专注冲刺，只帮你控制节奏——不开它工作也照样在计。"
        alert.addButton(withTitle: en ? "Start" : "开始")
        alert.addButton(withTitle: en ? "Cancel" : "取消")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 66))
        let durLabel = NSTextField(labelWithString: en ? "Duration:" : "时长:")
        durLabel.frame = NSRect(x: 0, y: 36, width: 90, height: 24)
        container.addSubview(durLabel)
        let durations = [25, 40, 50, 90, 0]
        let durPopup = NSPopUpButton(frame: NSRect(x: 95, y: 34, width: 150, height: 28))
        for d in durations {
            durPopup.addItem(withTitle: d == 0 ? (en ? "Open (end manually)" : "不限（手动结束）") : (en ? "\(d) min" : "\(d) 分钟"))
        }
        durPopup.selectItem(at: 1)
        container.addSubview(durPopup)
        let customField = NSTextField(string: "")
        customField.placeholderString = en ? "custom (min)" : "自定义(分钟)"
        customField.frame = NSRect(x: 250, y: 36, width: 85, height: 24)
        container.addSubview(customField)
        let noteLabel = NSTextField(labelWithString: en ? "Note:" : "备注:")
        noteLabel.frame = NSRect(x: 0, y: 4, width: 90, height: 24)
        container.addSubview(noteLabel)
        let noteField = NSTextField(string: "")
        noteField.placeholderString = en ? "optional, e.g. revise intro" : "可选，例如：改 intro"
        noteField.frame = NSRect(x: 95, y: 4, width: 240, height: 24)
        container.addSubview(noteField)

        alert.accessoryView = container
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var planned: Int?
        if let custom = Int(customField.stringValue), custom > 0 {
            planned = min(custom, 24 * 60)
        } else {
            let d = durations[max(0, durPopup.indexOfSelectedItem)]
            planned = d == 0 ? nil : d
        }
        guard ensureOnDutyForWork() else { return }
        let duty = DutyManager.shared
        if duty.isOnBreak {
            duty.endBreak()
            duty.stretchStart = Date()
        }
        focusManager.start(category: .deepWork, plannedMinutes: planned, note: noteField.stringValue)
        showFocusHUD()
        refreshMenu()
        updateFocusMenuBar()
        showFocusStartNotification()
    }

    @objc private func endFocusFromMenu() {
        guard let finished = focusManager.stop() else { return }
        hideFocusHUD()
        closeStretchWithPrompt(restart: true)
        refreshMenu()
        updateFocusMenuBar()
        showFocusEndNotification(finished)
    }

    // Close the running stretch with the labeling prompt; optionally start a new one
    private func closeStretchWithPrompt(restart: Bool) {
        let duty = DutyManager.shared
        guard let start = duty.stretchStart else { return }
        let minutes = Int(Date().timeIntervalSince(start) / 60)
        let (kind, note) = askSegmentKind(minutes: minutes)
        duty.closeStretch(kind: kind, note: note)
        if restart, duty.isOnDuty, !duty.isOnBreak {
            duty.stretchStart = Date()
        }
    }

    // Sprint start is self-initiated → always light (meow + bubble), never the big overlay
    private func showFocusStartNotification() {
        guard let session = focusManager.currentSession else { return }
        guard settings.globalMode != .superDND else { return }
        let en = L == .english
        let text: String
        if let planned = session.plannedMinutes {
            text = en ? "🎯 Deep Focus: \(planned) min" : "🎯 Deep Focus \(planned) 分钟，开始！"
        } else {
            text = en ? "🎯 Deep Focus started" : "🎯 Deep Focus 开始！"
        }
        playRandomSound()
        let pseudo = ReminderItem(id: UUID(), name: "focus", shortMessage: text, urgentMessage: text, intervalMinutes: 0, enabled: true)
        showSoftReminder(pseudo)
    }

    // Time-up must be noticeable → follows the global mode (strong in normal)
    private func showFocusEndNotification(_ session: FocusSession) {
        if isReminding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.showFocusEndNotification(session)
            }
            return
        }
        let en = L == .english
        let text = en ? "✅ Deep Focus done: \(formatMinutes(session.durationMinutes))" : "✅ Deep Focus 完成：\(formatMinutes(session.durationMinutes))"
        notifyFocus(text: text, buttonTitle: en ? "Nice!" : "收到！")
    }

    // Session start/end notifications follow the global mode:
    // normal = strong overlay, quiet = soft bubble + meow, super DND = fully silent
    private func notifyFocus(text: String, buttonTitle: String) {
        switch settings.globalMode {
        case .normal:
            showFocusOverlay(text: text, buttonTitle: buttonTitle)
        case .quiet:
            playRandomSound()
            let pseudo = ReminderItem(id: UUID(), name: "focus", shortMessage: text, urgentMessage: text, intervalMinutes: 0, enabled: true)
            showSoftReminder(pseudo)
        case .superDND:
            break
        }
    }

    private func showFocusOverlay(text: String, buttonTitle: String) {
        guard !isReminding else { return }
        hardReminderShowsSnooze = false
        hardReminderButtonTitle = buttonTitle
        isFocusOverlay = true
        let pseudo = ReminderItem(id: UUID(), name: "focus", shortMessage: text, urgentMessage: text, intervalMinutes: 0, enabled: true)
        showHardReminder(pseudo)
    }

    private func highlightedTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.systemBlue,
        ])
    }

    private func todayActiveMinutes() -> Int {
        DutyManager.shared.activeWorkMinutes(on: Date())
    }

    private func todayWorkLine() -> String {
        let en = L == .english
        let duty = DutyManager.shared
        var line = (en ? "Today: " : "今日工作 ") + formatMinutes(todayActiveMinutes())
        if duty.isOnDuty {
            let periods = duty.periodsOn(day: Date())
            if let first = periods.first {
                let span = max(0, Int(Date().timeIntervalSince(first.onDuty) / 60))
                line += " · " + (en ? "on duty " : "在岗 ") + coarseHours(span)
            }
            if !duty.isOnBreak, let next = reminderManager.nextFireDate {
                let mins = max(0, Int(next.timeIntervalSinceNow / 60))
                line += en ? " · next break ~\(mins)m" : " · 下次提醒 ~\(mins)分"
            }
        }
        return line
    }

    // Status line: WORKING + today's active total, or break/off-duty state
    private func dutyStatusLine() -> String {
        let en = L == .english
        let duty = DutyManager.shared
        if duty.isOnDuty {
            if duty.isOnBreak {
                let mins = duty.openBreak.map { max(0, Int(Date().timeIntervalSince($0.start) / 60)) } ?? 0
                return en ? "🟡 On break · \(formatMinutes(mins))" : "🟡 休息中 · 已 \(formatMinutes(mins))"
            }
            return "🟢 WORKING · " + formatMinutes(todayActiveMinutes())
        }
        let periods = duty.periodsOn(day: Date())
        guard let first = periods.first else {
            return en ? "⚪️ OFF DUTY" : "⚪️ 今天还没上班"
        }
        let spanEnd = periods.compactMap { $0.offDuty }.max() ?? Date()
        let span = max(0, Int(spanEnd.timeIntervalSince(first.onDuty) / 60))
        let spanStr = (en ? "on duty " : "在岗 ") + coarseHours(span)
        if duty.finalClockOut(on: Date()) != nil {
            return en ? "⚪️ OFF DUTY (done for today) · \(spanStr)" : "⚪️ 已下班（今天结束）· \(spanStr)"
        }
        return en ? "⚪️ OFF DUTY (may return) · \(spanStr)" : "⚪️ 暂时下班 · \(spanStr)"
    }

    // Low-pressure display: round to half hours, exact minutes live in Work Stats
    private func coarseHours(_ minutes: Int) -> String {
        let en = L == .english
        if minutes < 30 { return en ? "<0.5h" : "不到半小时" }
        let hours = Double(Int((Double(minutes) / 30.0).rounded())) / 2.0
        if hours == hours.rounded() { return en ? "~\(Int(hours))h" : "约 \(Int(hours)) 小时" }
        return en ? "~\(hours)h" : "约 \(hours) 小时"
    }

    private func formatMinutes(_ m: Int) -> String {
        let en = L == .english
        let h = m / 60
        let mm = m % 60
        if h > 0 {
            if en { return mm > 0 ? "\(h)h \(mm)m" : "\(h)h" }
            return mm > 0 ? "\(h)小时\(mm)分" : "\(h)小时"
        }
        return en ? "\(mm)m" : "\(mm)分钟"
    }

    private func statsText(forTag tag: Int) -> (title: String, body: String) {
        let en = L == .english
        let cal = Calendar.current
        let now = Date()
        let fallbackInterval = DateInterval(start: cal.startOfDay(for: now), duration: 86400)
        let interval: DateInterval
        let title: String
        switch tag {
        case 1:
            interval = cal.dateInterval(of: .weekOfYear, for: now) ?? fallbackInterval
            title = en ? "This Week" : "本周工作统计"
        case 2:
            interval = cal.dateInterval(of: .month, for: now) ?? fallbackInterval
            title = en ? "This Month" : "本月工作统计"
        case 3:
            interval = cal.dateInterval(of: .year, for: now) ?? fallbackInterval
            title = en ? "This Year" : "今年工作统计"
        default:
            interval = fallbackInterval
            title = en ? "Today" : "今日工作统计"
        }

        let duty = DutyManager.shared

        // Primary record: auto-tracked work segments (+ the running stretch)
        var segments = duty.segments.filter { interval.contains($0.start) }
        if let stretch = duty.stretchStart, interval.contains(stretch) {
            segments.append(WorkSegment(id: UUID(), start: stretch, end: now, kind: .mixed, note: en ? "(ongoing)" : "（进行中）"))
        }
        segments.sort { $0.start < $1.start }
        let workMin = segments.reduce(0) { $0 + $1.durationMinutes }

        // Optional overlay tool: deep focus sessions
        var focus = settings.focusSessions.filter { $0.end != nil && interval.contains($0.start) }
        if let current = focusManager.currentSession, interval.contains(current.start) {
            focus.append(current)
        }
        focus.sort { $0.start < $1.start }
        let deepMin = focus.reduce(0) { $0 + $1.durationMinutes }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        var lines: [String] = []

        if tag == 0 {
            // ── Layer 1: boundary (今天的工作边界) ──
            let periods = duty.periodsOn(day: now)
            if let first = periods.first {
                let stillOn = periods.contains { $0.offDuty == nil }
                let lastClosed = periods.compactMap { p in p.offDuty.map { (time: $0, inferred: p.offDutyInferred) } }.max { $0.time < $1.time }
                let offStr: String
                let spanEnd: Date
                if stillOn {
                    offStr = en ? "still on duty" : "仍在上班"
                    spanEnd = now
                } else if let last = lastClosed {
                    offStr = timeFmt.string(from: last.time) + (last.inferred ? "~" : "")
                    spanEnd = last.time
                } else {
                    offStr = "—"
                    spanEnd = now
                }
                lines.append((en ? "On duty " : "上班 ") + timeFmt.string(from: first.onDuty) + " → " + (en ? "off duty " : "下班 ") + offStr)
                let span = max(0, Int(spanEnd.timeIntervalSince(first.onDuty) / 60))
                lines.append("Duty span: " + formatMinutes(span))
                lines.append((en ? "Active work: " : "实际工作：") + formatMinutes(workMin))
                if deepMin > 0 {
                    lines.append("🎯 Deep Focus: " + formatMinutes(deepMin) + (en ? " (\(focus.count)x)" : "（\(focus.count) 次）"))
                }
                let breakMin = duty.breaksOn(day: now).reduce(0) { $0 + max(0, Int((($1.end ?? now).timeIntervalSince($1.start)) / 60)) }
                lines.append((en ? "Break / personal: " : "休息/私人：") + formatMinutes(breakMin))
                if let longest = segments.map({ $0.durationMinutes }).max() {
                    lines.append((en ? "Longest continuous stretch: " : "最长连续在线：") + formatMinutes(longest))
                }
                if !segments.isEmpty {
                    let avg = workMin / segments.count
                    lines.append(en ? "Stretches: \(segments.count) · avg \(formatMinutes(avg))" : "工作段数：\(segments.count) · 平均 \(formatMinutes(avg))")
                }
                lines.append((en ? "Duty blocks: \(periods.count)" : "上班段数：\(periods.count) 段"))
                let reopensFinal = duty.reopensAfterFinal(on: now)
                if duty.finalClockOut(on: now) != nil || reopensFinal > 0 {
                    lines.append((en ? "Reopens after final clock-out: \(reopensFinal)" : "宣布下班后又开工：\(reopensFinal) 次"))
                }

                // ── Day shape bar ──
                let spanSec = spanEnd.timeIntervalSince(first.onDuty)
                if spanSec > 600 {
                    let buckets = 48
                    let step = spanSec / Double(buckets)
                    let breaksToday = duty.breaksOn(day: now)
                    var bar = ""
                    for k in 0..<buckets {
                        let t0 = first.onDuty.addingTimeInterval(Double(k) * step)
                        let t1 = t0.addingTimeInterval(step)
                        func overlaps(_ a: Date, _ b: Date?) -> Bool {
                            a < t1 && (b ?? now) > t0
                        }
                        if segments.contains(where: { overlaps($0.start, $0.end) }) {
                            bar += "█"
                        } else if breaksToday.contains(where: { overlaps($0.start, $0.end) }) {
                            bar += "▓"
                        } else if periods.contains(where: { overlaps($0.onDuty, $0.offDuty) }) {
                            bar += "░"
                        } else {
                            bar += "·"
                        }
                    }
                    lines.append("")
                    lines.append(timeFmt.string(from: first.onDuty) + " " + bar + " " + offStr)
                    lines.append(en ? "█ work  ▓ break  ░ other on-duty  · off duty" : "█ 工作  ▓ 休息  ░ 其他在岗  · 下班")
                }
                lines.append("")
            }
        } else {
            // ── Aggregated boundary stats (趋势) ──
            var days: [Date] = []
            var seen = Set<Date>()
            for p in duty.periods where interval.contains(p.onDuty) {
                let day = cal.startOfDay(for: p.onDuty)
                if seen.insert(day).inserted { days.append(day) }
            }
            var spanSum = 0, spanDays = 0
            var offMinutesSum = 0, offDays = 0
            var reopenSum = 0
            var blocksSum = 0
            for day in days {
                let periods = duty.periodsOn(day: day)
                guard let first = periods.first else { continue }
                let stillOn = periods.contains { $0.offDuty == nil }
                let closedOffs = periods.compactMap { $0.offDuty }
                let spanEnd: Date? = stillOn ? (cal.isDateInToday(day) ? now : nil) : closedOffs.max()
                if let e = spanEnd {
                    spanSum += max(0, Int(e.timeIntervalSince(first.onDuty) / 60))
                    spanDays += 1
                }
                if !stillOn, let lastOff = closedOffs.max() {
                    let c = cal.dateComponents([.hour, .minute], from: lastOff)
                    offMinutesSum += (c.hour ?? 0) * 60 + (c.minute ?? 0)
                    offDays += 1
                }
                blocksSum += periods.count
                reopenSum += duty.reopensAfterFinal(on: day)
            }
            if !days.isEmpty {
                lines.append((en ? "Duty days: \(days.count)" : "上班天数：\(days.count) 天"))
                lines.append((en ? "Avg active work: " : "平均实际工作：") + formatMinutes(workMin / days.count))
                if deepMin > 0 {
                    lines.append((en ? "Deep Focus total: " : "Deep Focus 总计：") + formatMinutes(deepMin))
                }
                if spanDays > 0 {
                    lines.append((en ? "Avg duty span: " : "平均 duty span：") + formatMinutes(spanSum / spanDays))
                }
                if offDays > 0 {
                    let avg = offMinutesSum / offDays
                    lines.append(String(format: en ? "Avg clock-out: %02d:%02d" : "平均下班时间：%02d:%02d", avg / 60, avg % 60))
                }
                lines.append((en ? "Duty blocks: \(blocksSum) total" : "上班段数：共 \(blocksSum) 段"))
                lines.append((en ? "Reopens after final clock-out: \(reopenSum) total" : "宣布下班后又开工：共 \(reopenSum) 次"))
                if !segments.isEmpty {
                    let longest = segments.map { $0.durationMinutes }.max() ?? 0
                    lines.append((en ? "Longest continuous stretch: " : "最长连续在线：") + formatMinutes(longest))
                }
                lines.append("")
            }
        }

        // ── Layer 2: what the work was (工作结构, 粗分类) ──
        if segments.isEmpty && focus.isEmpty {
            lines.append(en ? "Nothing tracked yet." : "还没有记录。")
        } else {
            if tag != 0 && lines.isEmpty {
                lines.append((en ? "Active work: " : "实际工作：") + formatMinutes(workMin))
            }
            var kindMinutes: [Int: Int] = [:]
            var kindCounts: [Int: Int] = [:]
            for segment in segments {
                kindMinutes[segment.kind.rawValue, default: 0] += segment.durationMinutes
                kindCounts[segment.kind.rawValue, default: 0] += 1
            }
            for kind in WorkKind.allCases {
                guard let mins = kindMinutes[kind.rawValue], mins > 0 else { continue }
                let count = kindCounts[kind.rawValue] ?? 0
                if en {
                    lines.append("\(kind.emoji) \(kind.displayName(lang: L)): \(formatMinutes(mins)) (\(count)x)")
                } else {
                    lines.append("\(kind.emoji) \(kind.displayName(lang: L))：\(formatMinutes(mins))（\(count) 段）")
                }
            }
            lines.append("")
            lines.append(en ? "Log:" : "记录：")

            let dayTimeFmt = DateFormatter()
            dayTimeFmt.dateFormat = "MM-dd HH:mm"

            func segmentLine(_ segment: WorkSegment, withDate: Bool) -> String {
                let startStr = withDate ? dayTimeFmt.string(from: segment.start) : timeFmt.string(from: segment.start)
                let endStr = timeFmt.string(from: segment.end)
                var line = "\(startStr)–\(endStr)  \(segment.kind.emoji) \(segment.kind.displayName(lang: L))  \(formatMinutes(segment.durationMinutes))"
                if !segment.note.isEmpty { line += "  「\(segment.note)」" }
                return line
            }

            if tag == 0 {
                for segment in segments {
                    lines.append(segmentLine(segment, withDate: false))
                }
                if !focus.isEmpty {
                    lines.append("")
                    lines.append("🎯 Deep Focus:")
                    for session in focus {
                        let endStr = session.end.map { timeFmt.string(from: $0) } ?? (en ? "now" : "现在")
                        var line = "\(timeFmt.string(from: session.start))–\(endStr)  \(formatMinutes(session.durationMinutes))"
                        if !session.note.isEmpty { line += "  「\(session.note)」" }
                        if session.end == nil { line += en ? "  (ongoing)" : "（进行中）" }
                        lines.append(line)
                    }
                }
            } else {
                let unit: Calendar.Component = (tag == 3) ? .month : .day
                var totals: [Date: Int] = [:]
                for segment in segments {
                    guard let bucket = cal.dateInterval(of: unit, for: segment.start)?.start else { continue }
                    totals[bucket, default: 0] += segment.durationMinutes
                }
                let bucketFmt = DateFormatter()
                bucketFmt.locale = Locale(identifier: en ? "en_US" : "zh_CN")
                bucketFmt.dateFormat = tag == 3 ? (en ? "MMM" : "M月") : "MM-dd EEE"
                for key in totals.keys.sorted() {
                    lines.append("\(bucketFmt.string(from: key))  \(en ? "work" : "工作") \(formatMinutes(totals[key] ?? 0))")
                }
                if tag == 1 {
                    lines.append("")
                    for segment in segments {
                        lines.append(segmentLine(segment, withDate: true))
                    }
                }
            }
        }

        return (title, lines.joined(separator: "\n"))
    }

    @objc private func openWorkStats() {
        let en = L == .english
        if statsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.isReleasedWhenClosed = false
            win.level = .floating
            win.center()
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 440))
            let seg = NSSegmentedControl(
                labels: en ? ["Today", "Week", "Month", "Year"] : ["今日", "本周", "本月", "今年"],
                trackingMode: .selectOne,
                target: self,
                action: #selector(statsPeriodChanged(_:))
            )
            seg.selectedSegment = 0
            seg.frame = NSRect(x: 20, y: 402, width: 320, height: 26)
            content.addSubview(seg)
            statsSegment = seg
            let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 480, height: 372))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.autoresizingMask = [.width, .height]
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 465, height: 372))
            tv.isEditable = false
            tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.minSize = NSSize(width: 0, height: 372)
            tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.isVerticallyResizable = true
            tv.autoresizingMask = [.width]
            tv.textContainer?.widthTracksTextView = true
            scroll.documentView = tv
            content.addSubview(scroll)
            statsTextView = tv
            win.contentView = content
            statsWindow = win
        }
        refreshStatsWindow()
        NSApp.activate(ignoringOtherApps: true)
        statsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func statsPeriodChanged(_ sender: NSSegmentedControl) {
        refreshStatsWindow()
    }

    private func refreshStatsWindow() {
        guard let win = statsWindow, let tv = statsTextView, let seg = statsSegment else { return }
        let result = statsText(forTag: max(0, seg.selectedSegment))
        win.title = result.title
        tv.string = result.body
    }

    // MARK: - Focus HUD (猫头上的专注状态)

    private func showFocusHUD() {
        hideFocusHUD()
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 46),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces]
        let card = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 46))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        card.layer?.cornerRadius = 10
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .black
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.isBezeled = false
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 6, y: 4, width: 218, height: 38)
        card.addSubview(label)
        win.contentView = card
        catWindow.addChildWindow(win, ordered: .above)
        focusHUDWindow = win
        focusHUDLabel = label
        focusHUDTimer = commonTimer(1, repeats: true) { [weak self] _ in
            self?.updateFocusHUD()
        }
        updateFocusHUD()
    }

    private func hideFocusHUD() {
        focusHUDTimer?.invalidate()
        focusHUDTimer = nil
        if let win = focusHUDWindow {
            catWindow?.removeChildWindow(win)
            win.orderOut(nil)
        }
        focusHUDWindow = nil
        focusHUDLabel = nil
    }

    private func repositionFocusHUD() {
        guard let win = focusHUDWindow else { return }
        let catFrame = catWindow.frame
        let size = win.frame.size
        win.setFrame(NSRect(x: catFrame.midX - size.width / 2, y: catFrame.maxY + 6, width: size.width, height: size.height), display: false)
    }

    private func updateFocusHUD() {
        guard let session = focusManager.currentSession else {
            hideFocusHUD()
            return
        }
        guard focusHUDWindow != nil, let label = focusHUDLabel else { return }
        let en = L == .english
        let elapsedSec = max(0, Int(Date().timeIntervalSince(session.start)))
        let timeStr: String
        if let planned = session.plannedMinutes {
            let remain = max(0, planned * 60 - elapsedSec)
            timeStr = (en ? "left " : "剩 ") + String(format: "%02d:%02d", remain / 60, remain % 60)
        } else {
            timeStr = (en ? "elapsed " : "已 ") + String(format: "%02d:%02d", elapsedSec / 60, elapsedSec % 60)
        }
        var text = "🎯 Deep Focus · \(timeStr)"
        if !session.note.isEmpty { text += "\n「\(session.note)」" }
        label.stringValue = text
        repositionFocusHUD()
    }

    // MARK: - Duty (上/下班 envelope)

    private func ensureOnDutyForWork() -> Bool {
        let duty = DutyManager.shared
        if duty.isOnDuty { return true }
        if duty.hasClockedOutToday && !duty.hasFinalClockOutToday {
            // stepped out earlier, coming back is a normal new duty block
            duty.clockIn()
            return true
        }
        let en = L == .english
        let alert = NSAlert()
        if duty.hasFinalClockOutToday {
            alert.messageText = en ? "You said you were done for today." : "你已经宣布今天结束了。"
            alert.informativeText = en ? "Work anyway? This counts as reopening after your final clock-out." : "还是要工作吗？这会记为「宣布下班后又开工」。"
            alert.addButton(withTitle: en ? "Start anyway" : "重新开工")
        } else {
            alert.messageText = en ? "Start workday?" : "开始今天的上班？"
            alert.informativeText = en ? "This records today's on-duty time." : "确认后记录今天的上班时间。"
            alert.addButton(withTitle: en ? "Clock in" : "上班打卡")
        }
        alert.addButton(withTitle: en ? "Cancel" : "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        duty.clockIn()
        return true
    }

    @objc private func clockInFromMenu() {
        let duty = DutyManager.shared
        guard !duty.isOnDuty else { return }
        let en = L == .english
        if duty.hasFinalClockOutToday {
            let alert = NSAlert()
            alert.messageText = en ? "You said you were done for today." : "你已经宣布今天结束了。"
            alert.informativeText = en ? "Clock in again? This counts as reopening after your final clock-out." : "重新上班吗？这会记为「宣布下班后又开工」。"
            alert.addButton(withTitle: en ? "Clock in" : "重新上班")
            alert.addButton(withTitle: en ? "Cancel" : "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        duty.clockIn()
        playRandomSound()
        if catState == .sleeping { setCatState(.idle) }
        refreshMenu()
        updateFocusMenuBar()
    }

    // Light post-hoc labeling — Mixed preselected, Enter confirms
    private func askSegmentKind(minutes: Int) -> (WorkKind, String) {
        let en = L == .english
        let alert = NSAlert()
        alert.messageText = en ? "What was this mostly? (\(formatMinutes(minutes)))" : "这一段主要在干什么？（\(formatMinutes(minutes))）"
        alert.informativeText = en ? "Rough is fine — Enter for Mixed, or pick TBD and fill later." : "粗略就行——直接回车默认 Mixed，懒得想就选待定。"
        alert.addButton(withTitle: en ? "Log" : "记录")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 62))
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 34, width: 300, height: 26))
        for kind in WorkKind.allCases {
            popup.addItem(withTitle: "\(kind.emoji) \(kind.displayName(lang: L))")
        }
        container.addSubview(popup)
        let noteField = NSTextField(string: "")
        noteField.placeholderString = en ? "note (optional)" : "备注（可选）"
        noteField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        container.addSubview(noteField)
        alert.accessoryView = container
        _ = alert.runModal()
        let idx = max(0, min(popup.indexOfSelectedItem, WorkKind.allCases.count - 1))
        return (WorkKind.allCases[idx], noteField.stringValue)
    }

    @objc private func startBreakFromMenu() {
        let duty = DutyManager.shared
        guard duty.isOnDuty, !duty.isOnBreak else { return }
        if focusManager.currentSession != nil {
            _ = focusManager.stop()
            hideFocusHUD()
        }
        closeStretchWithPrompt(restart: false)
        duty.startBreak()
        refreshMenu()
        updateFocusMenuBar()
    }

    @objc private func endBreakFromMenu() {
        let duty = DutyManager.shared
        duty.endBreak()
        duty.stretchStart = Date()
        refreshMenu()
        updateFocusMenuBar()
    }

    @objc private func clockOutFromMenu() {
        let en = L == .english
        let duty = DutyManager.shared
        guard duty.isOnDuty else { return }
        let active = todayActiveMinutes()
        let segCount = duty.segmentsOn(day: Date()).count + (duty.stretchStart != nil ? 1 : 0)
        let alert = NSAlert()
        alert.messageText = en ? "Clock out?" : "下班打卡？"
        var infoText = en
            ? "Today: \(formatMinutes(active)) across \(segCount) stretches."
            : "今天：\(formatMinutes(active)) · \(segCount) 段。"
        infoText += en ? "\nIs this your final clock-out today?" : "\n这是今天最后一次下班吗？"
        alert.informativeText = infoText
        alert.addButton(withTitle: en ? "Done for today" : "今天到此结束")
        alert.addButton(withTitle: en ? "Stepping out (may return)" : "暂时下班（可能还回来）")
        alert.addButton(withTitle: en ? "Cancel" : "取消")
        let isFinal: Bool
        switch alert.runModal() {
        case .alertFirstButtonReturn: isFinal = true
        case .alertSecondButtonReturn: isFinal = false
        default: return
        }
        _ = focusManager.stop()
        hideFocusHUD()
        closeStretchWithPrompt(restart: false)
        duty.clockOut(final: isFinal)
        refreshMenu()
        updateFocusMenuBar()
        if isFinal {
            // 收工仪式: the one moment that keeps the big animation
            sleepAfterOverlay = true
            let text = en ? "🌙 Done for today: \(formatMinutes(active))" : "🌙 收工！今天工作 \(formatMinutes(active))"
            showFocusOverlay(text: text, buttonTitle: en ? "Off duty!" : "下班！")
            if isReminding == false { sleepAfterOverlay = false; setCatState(.sleeping) }
        } else {
            playRandomSound()
            if !isReminding { setCatState(.sleeping) }
        }
    }

    // MARK: - Idle detection & overwork nudges

    private func systemIdleSeconds() -> TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private func checkIdleAndOverwork() {
        let duty = DutyManager.shared
        guard duty.isOnDuty else {
            idleCandidateStart = nil
            idleLongPromptShown = false
            return
        }
        settings.workHeartbeat = Date()
        guard !idlePromptActive, !isReminding else { return }

        let idle = systemIdleSeconds()
        if !duty.isOnBreak {
            if idle >= 30 * 60 {
                if idleCandidateStart == nil {
                    idleCandidateStart = Date().addingTimeInterval(-idle)
                }
                if idle >= 2 * 3600 && !idleLongPromptShown, let start = idleCandidateStart {
                    idleLongPromptShown = true
                    promptLongIdle(since: start)
                }
            } else if let start = idleCandidateStart {
                idleCandidateStart = nil
                idleLongPromptShown = false
                let minutes = Int(Date().timeIntervalSince(start) / 60)
                if minutes >= 30 {
                    promptIdleClassification(since: start, minutes: minutes)
                }
            }
        }

        // continuous-online nudge every 2h of unbroken stretch
        if !duty.isOnBreak, let stretch = duty.stretchStart {
            if lastOverworkStretchStart != stretch {
                lastOverworkStretchStart = stretch
                overworkNotifiedMark = 0
            }
            let stretchMin = Int(Date().timeIntervalSince(stretch) / 60)
            let mark = stretchMin / 120
            if mark > overworkNotifiedMark && stretchMin >= 120 {
                overworkNotifiedMark = mark
                notifyOverwork(hours: mark * 2)
            }
        }
    }

    // Came back after 30+ min away: was that a break, or slow work (waiting on a model)?
    private func promptIdleClassification(since start: Date, minutes: Int) {
        idlePromptActive = true
        defer { idlePromptActive = false }
        let en = L == .english
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = en ? "Away for \(formatMinutes(minutes))" : "刚才离开了 \(formatMinutes(minutes))"
        alert.informativeText = en ? "Count it as a break, or were you still working (waiting, reading)?" : "这段算休息，还是其实在工作（等模型、看材料）？"
        alert.addButton(withTitle: en ? "It was a break" : "算休息")
        alert.addButton(withTitle: en ? "I was working" : "在工作")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let duty = DutyManager.shared
        if focusManager.currentSession != nil {
            _ = focusManager.stop(at: start)
            hideFocusHUD()
        }
        if let stretch = duty.stretchStart, stretch < start {
            duty.closeStretch(at: start, kind: .mixed)
        } else {
            duty.stretchStart = nil
        }
        duty.insertBreak(from: start, to: Date())
        duty.stretchStart = Date()
        refreshMenu()
        updateFocusMenuBar()
    }

    // Gone 2h+: offer to end the day, but never auto clock-out
    private func promptLongIdle(since start: Date) {
        idlePromptActive = true
        defer { idlePromptActive = false }
        let en = L == .english
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = en ? "Looks like you've been gone a while." : "你似乎离开很久了。"
        alert.informativeText = en
            ? "No activity for 2h+. End the workday? Clock-out would be recorded as \(timeFmt.string(from: start))."
            : "已经 2 小时以上没有活动。结束今天吗？下班时间会记为 \(timeFmt.string(from: start))。"
        alert.addButton(withTitle: en ? "Clock out (done for today)" : "下班（今天结束）")
        alert.addButton(withTitle: en ? "It was a break, I'm back" : "算休息，我回来了")
        alert.addButton(withTitle: en ? "Still working" : "还在工作")
        let duty = DutyManager.shared
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if focusManager.currentSession != nil {
                _ = focusManager.stop(at: start)
                hideFocusHUD()
            }
            if let stretch = duty.stretchStart, stretch < start {
                duty.closeStretch(at: start, kind: .mixed)
            } else {
                duty.stretchStart = nil
            }
            duty.clockOut(at: start, final: true)
            if !isReminding { setCatState(.sleeping) }
        case .alertSecondButtonReturn:
            if focusManager.currentSession != nil {
                _ = focusManager.stop(at: start)
                hideFocusHUD()
            }
            if let stretch = duty.stretchStart, stretch < start {
                duty.closeStretch(at: start, kind: .mixed)
            } else {
                duty.stretchStart = nil
            }
            duty.insertBreak(from: start, to: Date())
            duty.stretchStart = Date()
        default:
            break
        }
        idleCandidateStart = nil
        idleLongPromptShown = false
        refreshMenu()
        updateFocusMenuBar()
    }

    private func notifyOverwork(hours: Int) {
        let en = L == .english
        let suggestions = en
            ? ["drink some water", "stand up and stretch", "look out the window", "pet the cat", "walk for 2 minutes"]
            : ["喝口水", "站起来伸个懒腰", "看看窗外", "摸摸猫", "走两分钟"]
        let pick = suggestions.randomElement() ?? ""
        let text = en
            ? "🔥 \(hours)h continuously online — step away for 2 min: \(pick)?"
            : "🔥 已经连续在线 \(hours) 小时了——离开 2 分钟：\(pick)？"
        let pseudo = ReminderItem(id: UUID(), name: "overwork", shortMessage: text, urgentMessage: text, intervalMinutes: 0, enabled: true)
        guard let strength = settings.globalMode.strength else { return }
        showReminder(pseudo, strength: strength)
    }

    private func checkStaleDutyOnLaunch() {
        let duty = DutyManager.shared
        guard let stale = duty.staleOpenPeriod() else { return }
        let en = L == .english
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: stale.onDuty)
        let dayEnd = dayStart.addingTimeInterval(86400)
        let segmentEnds = settings.workSegments
            .filter { $0.start >= dayStart && $0.start < dayEnd }
            .map { $0.end }
        let sessionEnds = settings.focusSessions
            .filter { $0.start >= dayStart && $0.start < dayEnd }
            .compactMap { $0.end }
        let fallback = (segmentEnds + sessionEnds).max() ?? stale.onDuty
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: en ? "en_US" : "zh_CN")
        dayFmt.dateFormat = "MM-dd"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = en ? "You didn't clock out on \(dayFmt.string(from: stale.onDuty))." : "\(dayFmt.string(from: stale.onDuty)) 忘记下班打卡了。"
        alert.informativeText = en
            ? "On duty since \(timeFmt.string(from: stale.onDuty)), no clock-out recorded."
            : "当天 \(timeFmt.string(from: stale.onDuty)) 上班，没有记录下班时间。"
        alert.addButton(withTitle: en ? "Use last session end (\(timeFmt.string(from: fallback)))" : "用最后一段工作结束时间（\(timeFmt.string(from: fallback))）")
        alert.addButton(withTitle: en ? "Set time manually..." : "手动输入...")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            duty.close(id: stale.id, at: fallback, inferred: true)
        } else {
            let manual = NSAlert()
            manual.messageText = en ? "Clock-out time (HH:mm)" : "下班时间（HH:mm）"
            manual.addButton(withTitle: en ? "Save" : "保存")
            manual.addButton(withTitle: en ? "Cancel" : "取消")
            let field = NSTextField(string: timeFmt.string(from: fallback))
            field.frame = NSRect(x: 0, y: 0, width: 100, height: 24)
            manual.accessoryView = field
            if manual.runModal() == .alertFirstButtonReturn,
               let parsed = parseHHMM(field.stringValue) {
                let date = dayStart.addingTimeInterval(TimeInterval(parsed * 60))
                duty.close(id: stale.id, at: date, inferred: false)
            } else {
                duty.close(id: stale.id, at: fallback, inferred: true)
            }
        }
        refreshMenu()
        updateFocusMenuBar()
    }

    private func parseHHMM(_ str: String) -> Int? {
        let parts = str.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    @objc private func openWorkWindowSettings() {
        let en = L == .english
        let alert = NSAlert()
        alert.messageText = en ? "Preferred Work Window" : "工作时间窗"
        alert.informativeText = en
            ? "A reference window, never automatic: at the start the cat asks \"Start workday?\"; at the end it asks whether to clock out. Nothing is recorded without your confirmation."
            : "只是参考窗口，不会自动打卡：到点提醒「开始上班？」，超时提醒「还没下班哦」，都需要你确认。"
        alert.addButton(withTitle: en ? "Save" : "保存")
        alert.addButton(withTitle: en ? "Cancel" : "取消")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 92))
        let enableCheck = NSButton(checkboxWithTitle: en ? "Enable window reminders" : "启用时间窗提醒", target: nil, action: nil)
        enableCheck.frame = NSRect(x: 0, y: 64, width: 280, height: 24)
        enableCheck.state = settings.workWindowEnabled ? .on : .off
        container.addSubview(enableCheck)
        func mm(_ v: Int) -> String { String(format: "%02d:%02d", v / 60, v % 60) }
        let startLabel = NSTextField(labelWithString: en ? "Start:" : "开始:")
        startLabel.frame = NSRect(x: 0, y: 34, width: 60, height: 24)
        container.addSubview(startLabel)
        let startField = NSTextField(string: mm(settings.workWindowStart))
        startField.frame = NSRect(x: 65, y: 34, width: 70, height: 24)
        container.addSubview(startField)
        let endLabel = NSTextField(labelWithString: en ? "End:" : "结束:")
        endLabel.frame = NSRect(x: 145, y: 34, width: 60, height: 24)
        container.addSubview(endLabel)
        let endField = NSTextField(string: mm(settings.workWindowEnd))
        endField.frame = NSRect(x: 210, y: 34, width: 70, height: 24)
        container.addSubview(endField)
        alert.accessoryView = container
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settings.workWindowEnabled = enableCheck.state == .on
        if let v = parseHHMM(startField.stringValue) { settings.workWindowStart = v }
        if let v = parseHHMM(endField.stringValue) { settings.workWindowEnd = v }
        refreshMenu()
    }

    private func checkWorkWindow() {
        guard settings.workWindowEnabled, !isReminding else { return }
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let today = cal.startOfDay(for: now)
        let duty = DutyManager.shared
        let en = L == .english
        if nowMin >= settings.workWindowStart && nowMin < settings.workWindowStart + 5
            && promptedWindowStartDay != today && !duty.isOnDuty && !duty.hasClockedOutToday {
            promptedWindowStartDay = today
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = en ? "Start workday?" : "开始今天的上班？"
            alert.informativeText = en ? "Your work window has started. Clock in only if you confirm." : "到了你设定的工作时间窗。确认才会记录上班。"
            alert.addButton(withTitle: en ? "Clock in" : "上班打卡")
            alert.addButton(withTitle: en ? "Not yet" : "先不")
            if alert.runModal() == .alertFirstButtonReturn {
                duty.clockIn()
                refreshMenu()
                updateFocusMenuBar()
            }
        }
        if nowMin >= settings.workWindowEnd && nowMin < settings.workWindowEnd + 5
            && promptedWindowEndDay != today && duty.isOnDuty {
            promptedWindowEndDay = today
            NSApp.activate(ignoringOtherApps: true)
            clockOutFromMenu()
        }
    }

    // MARK: - Actions

    @objc private func toggleCat() {
        if catWindow.isVisible { catWindow.orderOut(nil) }
        else { catWindow.orderFrontRegardless() }
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let mode = GlobalMode(rawValue: sender.tag) else { return }
        settings.globalMode = mode
        if mode == .superDND {
            setCatState(.sleeping)
        } else {
            idleCounter = 0
            setCatState(.idle)
        }
        refreshMenu()
    }

    @objc private func toggleReminderItem(_ sender: NSMenuItem) {
        let items = settings.reminders
        guard sender.tag < items.count else { return }
        settings.toggleReminder(id: items[sender.tag].id)
        reminderManager.rebuildTimers()
        refreshMenu()
    }

    @objc private func toggleAlwaysOnTop() {
        settings.alwaysOnTop.toggle()
        catWindow.level = settings.alwaysOnTop ? .floating : .normal
        refreshMenu()
    }

    @objc private func toggleWalking() {
        settings.walkingEnabled.toggle()
        refreshMenu()
    }

    @objc private func toggleSound() {
        settings.soundEnabled.toggle()
        refreshMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        settings.launchAtLogin.toggle()
        refreshMenu()
    }

    @objc private func catScaleChanged(_ sender: NSSlider) {
        settings.catScale = sender.doubleValue
        if usingPNG, let pf = CatFrames.pngFrames(for: catState, group: currentSpriteGroup), !pf.isEmpty {
            resizeCatWindow(for: pf[0])
        }
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let lang = AppLanguage(rawValue: sender.tag) else { return }
        settings.language = lang
        statsWindow?.orderOut(nil)
        statsWindow = nil
        statsTextView = nil
        statsSegment = nil
        refreshMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: ReminderManagerDelegate {
    func reminderTriggered(_ item: ReminderItem, strength: ReminderStrength) {
        showReminder(item, strength: strength)
    }
}

extension AppDelegate: AlarmManagerDelegate {
    func alarmTriggered(_ alarm: AlarmItem, strength: ReminderStrength) {
        guard !isReminding else { return }
        let pseudo = ReminderItem(
            id: alarm.id,
            name: alarm.name,
            shortMessage: alarm.message,
            urgentMessage: "⏰ \(alarm.message)",
            intervalMinutes: 0,
            enabled: true
        )
        if strength == .hard {
            activeHardAlarmItem = alarm
            showHardReminder(pseudo)
        } else {
            showSoftReminder(pseudo)
        }
    }
}


extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        dutyStatusMenuItem?.title = dutyStatusLine()
        dutyTodayMenuItem?.title = todayWorkLine()
        updateFocusMenuBar()
    }
}

extension AppDelegate: FocusManagerDelegate {
    func focusSessionTimeUp(_ session: FocusSession) {
        hideFocusHUD()
        closeStretchWithPrompt(restart: true)
        refreshMenu()
        updateFocusMenuBar()
        showFocusEndNotification(session)
    }
}
