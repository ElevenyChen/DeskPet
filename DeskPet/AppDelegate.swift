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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupCatWindow()
        reminderManager.delegate = self
        reminderManager.start()
        alarmManager.delegate = self
        alarmManager.start()
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
        statusItem.menu = buildMenu()
    }

    private var L: AppLanguage { settings.language }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let en = L == .english

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
            let repeatLabel = alarm.repeatDaily ? (en ? ", daily" : ", 每天") : ""
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

        let pauseMenu = NSMenu()
        let pauseItem = NSMenuItem(title: en ? "Pause" : "暂停", action: nil, keyEquivalent: "")
        pauseItem.submenu = pauseMenu
        let pauseOptions: [(String, String, Int)] = [
            ("暂停 30 分钟", "Pause 30 min", 30),
            ("暂停 1 小时", "Pause 1 hour", 60),
            ("暂停到明天", "Pause until tomorrow", 1440),
        ]
        for (zh, enTitle, mins) in pauseOptions {
            let item = NSMenuItem(title: en ? enTitle : zh, action: #selector(pause(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mins
            pauseMenu.addItem(item)
        }
        pauseMenu.addItem(.separator())
        let resume = NSMenuItem(title: en ? "Resume Now" : "立即恢复", action: #selector(resumeAll), keyEquivalent: "")
        resume.target = self
        pauseMenu.addItem(resume)
        menu.addItem(pauseItem)
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
        case .walkingLeft, .walkingRight: interval = 0.25
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

        animTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
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
        zzzTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
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
        walkTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self, !self.isReminding else { return }
            if self.catState == .dragged || self.catState == .clicked || self.catState == .attacking { return }
            if self.settings.globalMode == .superDND {
                if self.catState != .sleeping { self.setCatState(.sleeping) }
                return
            }

            self.idleCounter += 1

            // Playing/chasingTail auto-end after ~10-15s
            if self.catState == .playing && self.idleCounter >= 3 {
                self.idleCounter = 0
                self.setCatState(.idle)
                return
            }
            if self.catState == .chasingTail && self.idleCounter >= 2 {
                self.idleCounter = 0
                self.setCatState(.idle)
                return
            }
            if self.catState == .bellyUp && self.idleCounter >= 3 {
                self.idleCounter = 0
                self.setCatState(.idle)
                return
            }
            if self.catState == .grooming && self.idleCounter >= 4 {
                self.idleCounter = 0
                self.setCatState(.idle)
                return
            }

            // From idle: random activity
            if self.catState == .idle {
                var actions: [(weight: Int, action: () -> Void)] = []
                if self.settings.walkingEnabled {
                    actions.append((6, { self.walkToRandomSpot() }))
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

            // After ~25s idle → lie down
            if self.catState == .idle && self.idleCounter >= 5 {
                self.setCatState(.lyingDown)
                return
            }

            // After ~25s lying → fall asleep
            if self.catState == .lyingDown && self.idleCounter >= 10 {
                self.setCatState(.sleeping)
                return
            }

            // After ~60s sleeping → wake up
            if self.catState == .sleeping && self.idleCounter >= 22 {
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

    private func animateWalkTo(_ target: NSPoint, leavePawPrints: Bool, completion: @escaping () -> Void) {
        let current = catWindow.frame.origin
        let dx = target.x - current.x
        let dy = target.y - current.y
        let distance = sqrt(dx * dx + dy * dy)
        let speed = CGFloat.random(in: 2.5...8.0)
        let steps = max(Int(distance / speed), 1)
        let dirX = dx / distance
        let dirY = dy / distance
        var step = 0
        var pawCounter = 0

        walkAnimTimer?.invalidate()
        walkAnimTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] timer in
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
            let eased = t < 0.5
                ? 2 * t * t
                : 1 - pow(-2 * t + 2, 2) / 2
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
        guard settings.soundEnabled else { return }
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
        guard catState != .attacking else { return }
        walkAnimTimer?.invalidate()
        walkAnimTimer = nil

        clickCount += 1

        if clickCount >= attackThreshold {
            clickCount = 0
            attackThreshold = Int.random(in: 5...15)
            playRandomSound()
            setCatState(.attacking)
            return
        }
    }

    func onDragStart() {
        stateBeforeDrag = catState
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
        let by = catFrame.maxY + 6

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

        scaleTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] timer in
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
    }

    private func restoreCatWindowSize() {
        guard let original = originalCatWindowFrame else {
            setCatState(.idle)
            return
        }
        scaleTimer?.invalidate()
        scaleTimer = nil

        let steps = 6
        let currentFrame = catWindow.frame
        var step = 0

        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            step += 1
            if step >= steps {
                timer.invalidate()
                self.catWindow.setFrame(original, display: true)
                self.originalCatWindowFrame = nil
                self.setCatState(.idle)
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
        msg.font = .systemFont(ofSize: 24, weight: .bold)
        msg.textColor = .black
        msg.backgroundColor = .clear
        msg.drawsBackground = false
        msg.isBezeled = false
        msg.alignment = .center
        msg.frame = NSRect(x: 20, y: cardH - 60, width: cardW - 40, height: 40)
        card.addSubview(msg)

        let btn = NSButton(title: L == .english ? "Got it!" : "知道了！", target: self, action: #selector(dismissHardReminder))
        btn.font = .systemFont(ofSize: 16, weight: .medium)
        btn.bezelStyle = .rounded
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0).cgColor
        btn.layer?.cornerRadius = 10
        btn.contentTintColor = .white
        btn.frame = NSRect(x: (cardW - 200) / 2, y: 55, width: 200, height: 40)
        card.addSubview(btn)

        let showSnooze = activeHardAlarmItem?.snoozeEnabled ?? true
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

        catWindow.level = .floating
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

        let repeatCheck = NSButton(checkboxWithTitle: en ? "Repeat daily" : "每天重复", target: nil, action: nil)
        repeatCheck.frame = NSRect(x: 95, y: 72, width: 200, height: 24)
        repeatCheck.state = .on
        container.addSubview(repeatCheck)

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
            let alarm = AlarmItem(
                id: UUID(),
                name: name,
                message: msgField.stringValue.isEmpty ? "\(name)!" : msgField.stringValue,
                hour: hour,
                minute: minute,
                strengthOverride: strengthOverride,
                repeatDaily: repeatCheck.state == .on,
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

        let repeatCheck = NSButton(checkboxWithTitle: en ? "Repeat daily" : "每天重复", target: nil, action: nil)
        repeatCheck.frame = NSRect(x: 95, y: 72, width: 200, height: 24)
        repeatCheck.state = alarm.repeatDaily ? .on : .off
        container.addSubview(repeatCheck)

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
            updated.repeatDaily = repeatCheck.state == .on
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
        refreshMenu()
    }

    @objc private func pause(_ sender: NSMenuItem) {
        reminderManager.pause(minutes: sender.tag)
    }

    @objc private func resumeAll() {
        reminderManager.resume()
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
