# DeskPet — macOS 桌宠猫咪提醒器

macOS 菜单栏常驻桌宠应用。一只像素猫住在你的桌面上，会走路、趴下、睡觉、被你拎起来，到时间了提醒你喝水、休息。

## 技术栈

- Swift 5 + AppKit，macOS 13+
- 纯代码构建，无 Storyboard/XIB
- 入口：`main.swift` → `AppDelegate`
- 菜单栏 App，透明无边框悬浮窗口
- ServiceManagement 框架实现开机自启动

## 项目结构

```
DeskPet/
├── main.swift              # App 入口
├── AppDelegate.swift       # 菜单栏、猫窗口、提醒逻辑、拖拽、行为循环、窗口缩放
├── Models.swift            # CatState, ReminderItem, AlarmItem, GlobalMode, AppLanguage 数据模型
├── CatFrames.swift         # Unicode 动画帧 + PNG sprite 加载（含动作组）+ 自定义图标
├── CatView.swift           # DraggableCatView — 鼠标拖拽处理 + CatWindow/OverlayWindow
├── CatRenderer.swift       # Core Graphics 猫绘制（当前未使用，保留备用）
├── CatWindowController.swift # 旧窗口控制器（当前未使用）
├── SettingsManager.swift   # UserDefaults 存储：模式、声音、语言、开机启动、提醒列表、闹钟列表、猫大小
├── ReminderManager.swift   # 定时器管理，按 GlobalMode 决定提醒强度
├── AlarmManager.swift      # 闹钟管理，定时检查、按时触发、贪睡
├── Info.plist
├── DeskPet.entitlements
├── Assets.xcassets/        # AppIcon（像素猫图标，全套 10 尺寸）
└── Sprites/                # 自定义 PNG 帧（按文件夹分状态，支持动作组）
    ├── icon/               # App 图标（同步到 Assets.xcassets）
    ├── idle/               # 待机（支持动作组子文件夹，如 blink/, tail/）
    ├── lying_down/         # 趴下 + 睡觉共用（sleeping 复用此文件夹，代码叠加 zzZ）
    ├── walk_right/         # 右走侧面视角
    ├── walk_left/          # 左走侧面视角
    ├── reminder/           # 提醒动画
    ├── dragged/            # 被拎起（支持动作组，如 front/, side/）
    ├── attacking/          # 攻击/挥爪（点击多次触发）
    ├── playing/            # 玩耍
    ├── chasing_tail/       # 追尾巴
    └── paw_print/          # 爪印
```

## 当前功能

### 猫咪行为
- **待机** → 像素猫坐姿，支持多动作组随机切换（如眨眼组、尾巴组）
- **趴下** → 闲置 ~25s 后趴下，支持正面/侧面动作组
- **睡觉** → 趴着 ~25s 后入睡，复用 lying_down sprite + 代码叠加浮动 zzZ 动画
- **走路** → 侧面视角像素猫，留爪印，每次随机速度 + 加速/减速曲线
- **玩耍** → 随机从 idle 触发，玩球动画，~15s 后恢复（仅当 Sprites/playing/ 有素材时触发）
- **追尾巴** → 随机从 idle 触发，原地转圈追尾巴，~10s 后恢复（仅当 Sprites/chasing_tail/ 有素材时触发）
- **提醒** → 像素猫提醒动画
- **被拎** → 拖拽时窗口拉高 1.3x，支持多动作组（正面/侧面）
- **攻击** → 点击猫咪 5-15 次（随机阈值）后挥爪攻击动画，~2.5s 后恢复（无素材时回退显示 "!"）

### 窗口自适应
- 猫窗口根据 sprite 实际宽高比自动调整大小
- 不同状态的 sprite 尺寸不同时（如坐姿 vs 趴下），窗口跟着变
- 菜单栏滑条可调节猫咪大小（0.5x ~ 3.0x），设置持久保存

### 动作组系统
- 每个状态文件夹支持子文件夹作为"动作组"
- 切换状态时随机选择一个动作组，组内帧按 0.png, 1.png 顺序播放
- 兼容旧的扁平布局（无子文件夹时直接读 0.png, 1.png）
- 动作组在状态切换时选定，动画期间保持不变

### 强提醒 — 窗口缩放动画
1. 猫走到屏幕中央（侧面行走）
2. 窗口等比放大 3x（8 步 smoothstep 缓动）
3. 全屏半透明遮罩 + 白底圆角卡片（猫正下方）
4. 提醒期间猫不可拖拽，必须通过对话框按钮结束
5. 点击关闭后窗口缩回原始大小（6 步缓动）

### 提醒系统
- 默认两个提醒：喝水(30min)、休息眼睛(25min)
- 可添加/编辑/删除/开关任意提醒（文本和间隔均可自定义）
- 提醒强度由「当前模式」全局控制：
  - **正常模式** → 强提醒：窗口放大 + 遮罩 + 必须操作
  - **安静模式** → 软提醒：猫头上方气泡窗口，8秒后消失
  - **超级免打扰** → 不提醒，猫一直睡觉

### 闹钟系统
- 按具体时间（时:分）触发提醒，区别于按间隔的提醒系统
- 每个闹钟可独立设置提醒强度（强/软/跟随系统），但超级免打扰模式下始终静音
- 支持每天重复
- 支持贪睡（5分钟后再提醒），可按闹钟单独开关
- 非重复闹钟触发后自动禁用
- 菜单栏可添加/编辑/删除/开关闹钟

### 菜单栏
- 菜单栏图标：像素猫图标
- 显示/隐藏猫咪
- 当前模式切换（正常/安静/超级免打扰）
- 提醒列表（开关/编辑/添加/删除），显示每项间隔
- 闹钟列表（开关/编辑/添加/删除），显示时间和强度
- **猫咪大小滑条**（0.5x ~ 3.0x）
- 始终置顶开关（控制猫窗口是否浮动在所有窗口之上，默认开启）
- 猫叫声音开关
- 开机自启动开关（SMAppService）
- 语言切换（中文 / English）
- 暂停（30分钟/1小时/到明天/立即恢复）
- 测试软提醒/强提醒
- 所有菜单和对话框支持中英双语

### 自定义素材
- 放 PNG 到 `Sprites/` 对应文件夹，命名 `0.png, 1.png, 2.png...`，app 自动切换为图片动画
- `Sprites/icon/0.png` 替换图标，需用 sips 生成全套尺寸到 Assets.xcassets
- **动作组**：在状态文件夹内创建子文件夹，每个子文件夹为一个动作组。切换状态时随机选择一个动作组播放。兼容旧的扁平布局
- **注意**：添加新素材后必须 clean build（Cmd+Shift+K），增量 build 不会同步新资源文件

## 关键实现细节

### 窗口架构
- **猫窗口** (CatWindow)：动态大小，根据 sprite 比例 + catScale 滑条自适应
- **气泡窗口** (bubbleWindow)：软提醒时独立悬浮在猫窗口正上方，ignoresMouseEvents
- **遮罩窗口** (OverlayWindow)：强提醒时全屏半透明遮罩 + 白底卡片在猫下方
- 三个窗口完全分离，互不干扰

### 窗口自适应机制
- `resizeCatWindow(for:)` 根据首帧图片宽高比 + `catScale` 计算窗口大小
- `setCatState()` 切换状态时自动 resize（dragged 除外）
- `draggedWindowHeight` = 窗口高度 × 1.3
- `onDragEnd()` 调用 `layoutCatContent()` 恢复（不再硬编码 150x100）

### zzZ 睡觉动画
- sleeping 状态复用 lying_down 的 sprite
- `zzzLabel` 叠加在猫窗口内，sleeping 时显示 z → zZ → zZz 循环浮动
- `startZzzAnimation()` / `stopZzzAnimation()` 在 setCatState 时自动管理

### 拖拽实现
- `CatWindow` 继承 NSWindow，override `canBecomeKey`/`canBecomeMain` 返回 `true`
- `DraggableCatView` 作为 contentView，override `hitTest` 让整个 bounds 响应点击
- 窗口 `backgroundColor` 设为 `NSColor.white.withAlphaComponent(0.005)`（解决透明区域无法点击）
- `MouseTransparentTextField`/`MouseTransparentImageView` 的 `hitTest` 返回 `nil`，鼠标事件穿透
- **提醒期间禁止拖拽**：`isReminding` 为 true 时 mouseDown 直接 return

### 提醒遮罩
- `OverlayWindow` override `canBecomeKey`/`canBecomeMain` 返回 `true`
- `.floating` level（不用 `.screenSaver`，否则按钮无法点击）
- 白底圆角卡片定位在猫窗口正下方，猫在卡片上层
- ESC 键兜底关闭（keyCode 53）

### 行为循环
- 5 秒 tick，idle → lyingDown → sleeping（+zzZ）→ idle 循环
- 从 idle 状态随机触发：走路(~10%)、玩耍(~5%)、追尾巴(~3%)
- 走路每次随机速度（2.5~8 pts/step）+ ease-in-out 加减速曲线
- 玩耍 ~15s 后自动恢复 idle，追尾巴 ~10s 后自动恢复
- 超级免打扰模式下猫直接进入 sleeping
- 拖拽、提醒和攻击状态下行为循环暂停

### 点击攻击
- 每轮设定随机阈值 5-15 次点击
- 达到阈值后触发 attacking 状态，挥爪攻击动画 2.5s
- 攻击结束后重置计数器并生成新的随机阈值

### 多语言
- `AppLanguage` 枚举（chinese/english），存 UserDefaults
- `buildMenu()` 内所有文本根据 `L` 属性切换
- 编辑/添加/删除提醒对话框同步切换
- 强提醒按钮文字同步切换

### 提醒定时器
- ReminderManager 为每个 enabled 的 ReminderItem 创建独立 Timer
- 强度不在 ReminderItem 上设，由 GlobalMode.strength 统一决定
- schema 变更时需 `defaults delete com.deskpet.cat` 清除旧数据

### 闹钟管理器
- AlarmManager 每 15 秒 tick 检查当前时间是否匹配闹钟
- 每个闹钟每天只触发一次（firedToday 集合跟踪）
- 午夜自动清空 firedToday
- 贪睡通过独立 Timer 实现，5 分钟后重新触发
- 非重复闹钟触发后自动 disable

## 构建与运行

```bash
# 确保 Xcode 命令行工具指向 Xcode.app
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# 构建（若 xcode-select 不可用，直接用完整路径）
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project DeskPet.xcodeproj -scheme DeskPet -configuration Release build

# 运行
open ~/Library/Developer/Xcode/DerivedData/DeskPet-*/Build/Products/Release/DeskPet.app
```

或在 Xcode 中打开 `DeskPet.xcodeproj`，Cmd+R 运行。

### 打包分发

```bash
# Release 构建
xcodebuild -project DeskPet.xcodeproj -scheme DeskPet -configuration Release clean build

# 创建 DMG
hdiutil create -volname DeskPet -srcfolder Build/Products/Release/DeskPet.app \
  -ov -format UDZO DeskPet.dmg
```

## 已踩过的坑

1. **borderless NSWindow 不接收鼠标** — 必须 override `canBecomeKey`/`canBecomeMain` 返回 `true`
2. **透明窗口点击穿透** — `backgroundColor = .clear` 会让整个窗口对 macOS hitTest 不可见，用 0.5% alpha 白色背景解决
3. **NSTextField 拦截鼠标** — 即使 label 模式也会吃掉 hitTest，需要子类化返回 `nil`
4. **`acceptsFirstMouse` 必须 override** — 否则第一次点击只激活窗口不传递事件
5. **强提醒 `.screenSaver` level 锁死** — 按钮无法获取焦点，改用 `.floating` + OverlayWindow
6. **气泡放在猫窗口内会重叠** — 改为独立窗口悬浮在猫正上方
7. **强提醒重复猫** — overlay 内画大猫 + 猫窗口放大 = 两只猫叠加，去掉 overlay 内的猫只保留窗口缩放
8. **强提醒按钮不可见** — 半透明遮罩上的按钮看不清，改为白底卡片内放按钮
9. **Xcode 增量 build 不同步新资源** — Sprites 文件夹内新增文件需 clean build 才会拷贝到 app bundle
10. **onDragEnd 硬编码 150x100** — 拖拽后 imageView 缩小，改用 `layoutCatContent()` 动态计算
11. **动作组初始化未设 currentSpriteGroup** — 首次 idle 不走 setCatState，需在 checkForPNGSprites 中手动设置

## TBD

### 高优先
- [ ] 提醒升级机制：连续忽略软提醒 N 次后自动升级为强提醒

### 视觉与动画
- [ ] AI 辅助补帧 — 用少量关键帧生成中间帧
- [ ] 尾巴独立摆动
- [ ] 眨眼独立于其他动画
- [ ] 节日主题皮肤

### 行为系统
- [ ] 随机行为状态机 — 权重化状态切换而非固定时间
- [ ] 鼠标跟随 — 猫的眼睛/头跟着鼠标转
- [ ] 看窗外场景 — 猫走到屏幕边缘趴着往外看
- [ ] 踩键盘 — 用户长时间不操作时猫走到当前窗口上

### 提醒系统增强
- [ ] 每个提醒独立设置强度覆盖（可选，默认跟随全局模式）
- [ ] 提醒历史记录 — 今天喝了几次水、休息了几次
- [ ] 智能提醒间隔 — 根据用户活跃度调整

### 系统集成
- [ ] 多显示器支持 — 猫可以在不同屏幕间走动
- [ ] 低电量模式 — 降低动画帧率
- [ ] 系统通知集成（可选通道）
- [ ] Shortcuts/快捷指令 支持

### 个性化
- [ ] 多只猫 / 不同猫咪角色
- [ ] 猫咪皮肤商店 / 导入
- [ ] 自定义猫叫声音
- [ ] 猫咪名字
