import Cocoa

struct CatFrames {

    // MARK: - PNG Loading

    private static let spritesDir: String? = {
        Bundle.main.resourcePath.map { $0 + "/Sprites" }
    }()

    static func folderName(for state: CatState) -> String {
        switch state {
        case .idle, .watchingUser, .lookingOut: return "idle"
        case .sleeping, .lyingDown: return "lying_down"
        case .walkingRight: return "walk_right"
        case .walkingLeft: return "walk_left"
        case .reminder: return "reminder"
        case .dragged: return "dragged"
        case .clicked: return "clicked"
        case .attacking: return "attacking"
        case .playing: return "playing"
        case .chasingTail: return "chasing_tail"
        }
    }

    private static func loadFrames(from dir: String) -> [NSImage]? {
        var images: [NSImage] = []
        for i in 0..<20 {
            if let img = NSImage(contentsOfFile: "\(dir)/\(i).png") {
                images.append(img)
            } else {
                break
            }
        }
        return images.isEmpty ? nil : images
    }

    static func actionGroups(for state: CatState) -> [String] {
        guard let base = spritesDir else { return [] }
        let dir = "\(base)/\(folderName(for: state))"
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var groups: [String] = []
        for name in contents {
            var isDir: ObjCBool = false
            let path = "\(dir)/\(name)"
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
               !name.hasPrefix(".") {
                if loadFrames(from: path) != nil {
                    groups.append(name)
                }
            }
        }
        return groups.sorted()
    }

    static func pngFrames(for state: CatState, group: String? = nil) -> [NSImage]? {
        guard let base = spritesDir else { return nil }
        let dir = "\(base)/\(folderName(for: state))"

        if let group = group {
            if let frames = loadFrames(from: "\(dir)/\(group)") { return frames }
        }

        let groups = actionGroups(for: state)
        if !groups.isEmpty {
            let picked = groups[Int.random(in: 0..<groups.count)]
            if let frames = loadFrames(from: "\(dir)/\(picked)") { return frames }
        }

        if let frames = loadFrames(from: dir) { return frames }

        if state == .clicked || state == .attacking || state == .playing || state == .chasingTail {
            return pngFrames(for: .idle)
        }
        return nil
    }

    static func randomGroup(for state: CatState) -> String? {
        let groups = actionGroups(for: state)
        guard !groups.isEmpty else { return nil }
        return groups[Int.random(in: 0..<groups.count)]
    }

    static func hasDedicatedSprites(for state: CatState) -> Bool {
        guard let base = spritesDir else { return false }
        let dir = "\(base)/\(folderName(for: state))"
        if loadFrames(from: dir) != nil { return true }
        let groups = actionGroups(for: state)
        return !groups.isEmpty
    }

    static func pawPrintImage() -> NSImage? {
        guard let base = spritesDir else { return nil }
        return NSImage(contentsOfFile: "\(base)/paw_print/0.png")
    }

    static func customIcon() -> NSImage? {
        guard let base = spritesDir else { return nil }
        return NSImage(contentsOfFile: "\(base)/icon/0.png")
    }

    // MARK: - Unicode Frames

    static func frames(for state: CatState) -> [String] {
        switch state {
        case .idle, .watchingUser, .lookingOut: return idle
        case .sleeping: return sleeping
        case .lyingDown: return lyingDown
        case .walkingRight: return walkRight
        case .walkingLeft: return walkLeft
        case .reminder: return reminder
        case .dragged: return dragged
        case .clicked: return clicked
        case .attacking: return attacking
        case .playing: return playing
        case .chasingTail: return chasingTail
        }
    }

    static let idle: [String] = [
"""
  /\\_/\\
 ( o.o )
  > ^ <
 /|   |\\
(_|   |_)
""",
"""
  /\\_/\\
 ( o.o )
  > ^ <
 /|   |\\
(_|   |_)~
""",
"""
  /\\_/\\
 ( -.- )
  > ^ <
 /|   |\\
(_|   |_)
""",
"""
  /\\_/\\
 ( o.o )
  > ^ <
 /|   |\\
~(_|  |_)
""",
    ]

    static let sleeping: [String] = [
"""
       /\\_/\\
  ____( -.- ) z
 |          |
 |__________|
""",
"""
       /\\_/\\
  ____( -.- ) zZ
 |          |
 |__________|
""",
"""
       /\\_/\\
  _--_( -.- ) zZz
 (          )
 |__________|
""",
"""
       /\\_/\\
  _--_( -.- ) zZ
 (          )
 |__________|
""",
"""
       /\\_/\\
  ____( -.- ) z
 |          |
 |__________|
""",
"""
       /\\_/\\
  ____( -.- )  z
 |          |
 |__________|
""",
    ]

    static let lyingDown: [String] = [
"""
       /\\_/\\
  ____( -.- )
 |          |~
 |__________|
""",
"""
       /\\_/\\
  ____( -.- )
~|          |
 |__________|
""",
"""
       /\\_/\\
  ____( u.u )
 |          |~
 |__________|
""",
"""
       /\\_/\\
  ____( -.- )
 |          |
~|__________|
""",
    ]

    static let walkRight: [String] = [
"""
   /\\_/\\
  ( o.o )\\_~~
  /   |   \\
 d    b   d b
""",
"""
   /\\_/\\
  ( o.o )\\_~
   |  |  |
   db    db
""",
"""
   /\\_/\\
  ( o.o )\\_~~
   \\   |   /
  d b  d    b
""",
"""
   /\\_/\\
  ( o.o )\\_~
   |  |  |
   db    db
""",
    ]

    static let walkLeft: [String] = [
"""
         /\\_/\\
    ~~_/( o.o )
      /   |   \\
    d b   d    b
""",
"""
        /\\_/\\
     ~_/( o.o )
       |  |  |
       db    db
""",
"""
         /\\_/\\
    ~~_/( o.o )
     \\   |   /
   d    b  d b
""",
"""
        /\\_/\\
     ~_/( o.o )
       |  |  |
       db    db
""",
    ]

    static let reminder: [String] = [
"""
  /\\_/\\  !
 ( °o° )
  > ^ <
 /|   |\\
(_|   |_)
""",
"""
  /\\_/\\ !!
 ( °□° )
  > ^ <
  |   |/
(_|   |_)
""",
"""
  /\\_/\\  !
 ( °o° )
  > ^ <
 \\|   |
(_|   |_)
""",
"""
  /\\_/\\ !!
 ( °□° )
  > ^ <
 /|   |\\
(_|   |_)
""",
    ]

    static let dragged: [String] = [
"""
   /\\_/\\
  ( >_< )
   |   |
   |   |
   |   |
   |   |
   |   |
   |   |
   d   b
""",
"""
   /\\_/\\
  ( >o< )
   |   |
   |   |
   |   |
   |   |
   |   |
   |   |
   d   b
""",
    ]

    static let clicked: [String] = [
"""
  /\\_/\\  !
 ( °o° )
  > ^ <
 /|   |\\
(_|   |_)
""",
"""
  /\\_/\\  !
 ( °□° )
  > ^ <
 /|   |\\
(_|   |_)
""",
    ]

    static let attacking: [String] = [
"""
  /\\_/\\  ☆
 ( >o< )つ
  > ^ <  /
 /|   |\\|
(_|   |_)
""",
"""
  /\\_/\\ ★
 ( >□< )つ≡≡
  > ^ <
 /|   |\\
(_|   |_)
""",
"""
  /\\_/\\   ☆
 ( >o< )つ/
  > ^ < |
 /|   |\\
(_|   |_)
""",
"""
  /\\_/\\  ★★
 ( >`< )つ≡
  > ^ <
  |   |/
(_|   |_)
""",
    ]

    static let playing: [String] = [
"""
  /\\_/\\   o
 ( ^.^ ) /
  > ^ </
 /|   |\\
(_|   |_)
""",
"""
  /\\_/\\
 ( ^o^ )  o
  > ^ <  /
 /|   |\\
(_|   |_)
""",
"""
  /\\_/\\ o
 ( ^.^ )/
  > ^ <
 /|   |\\
(_|   |_)
""",
"""
  /\\_/\\
 ( >w< )
  > ^ <  o
 /|   |\\ |
(_|   |_)
""",
    ]

    static let chasingTail: [String] = [
"""
  /\\_/\\
 ( @.@ )~
  > ^ <
 /|   |\\
(_|   |_)
""",
"""
     /\\_/\\
  ~-( @.@ )
     > ^ <
    /|   |\\
   (_|   |_)
""",
"""
  /\\_/\\
 ( @o@ )-~
  > ^ <
 /|   |\\
(_|   |_)
""",
"""
       /\\_/\\
  ~~( @.@ )
      > ^ <
     /|   |\\
    (_|   |_)
""",
    ]

    static let pawPrint = " - -"

    // MARK: - Sound Loading

    static func loadCustomSounds() -> [NSSound] {
        guard let res = Bundle.main.resourcePath else { return [] }
        let soundsDir = res + "/Sounds"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: soundsDir) else { return [] }
        let exts = ["aiff", "wav", "mp3", "m4a", "caf"]
        var sounds: [NSSound] = []
        for file in files.sorted() {
            let ext = (file as NSString).pathExtension.lowercased()
            if exts.contains(ext), let s = NSSound(contentsOfFile: "\(soundsDir)/\(file)", byReference: false) {
                sounds.append(s)
            }
        }
        return sounds
    }
}
