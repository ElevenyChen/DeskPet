import Cocoa

struct CatRenderer {
    static func renderImage(state: CatState, size: CGSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawCat(in: rect, state: state)
            return true
        }
        return image
    }

    private static func drawCat(in rect: NSRect, state: CatState) {
        let cx = rect.midX
        let baseY = rect.minY + 10

        NSColor(red: 0.45, green: 0.45, blue: 0.5, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 25, y: baseY, width: 50, height: 35)).fill()

        let headY = baseY + 28
        NSColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 18, y: headY, width: 36, height: 30)).fill()

        NSColor(red: 0.55, green: 0.55, blue: 0.6, alpha: 1).setFill()
        for side: CGFloat in [-1, 1] {
            let ear = NSBezierPath()
            ear.move(to: NSPoint(x: cx + side * 12, y: headY + 25))
            ear.line(to: NSPoint(x: cx + side * 20, y: headY + 38))
            ear.line(to: NSPoint(x: cx + side * 6, y: headY + 30))
            ear.close()
            ear.fill()
        }

        NSColor(red: 0.85, green: 0.65, blue: 0.65, alpha: 1).setFill()
        for side: CGFloat in [-1, 1] {
            let inner = NSBezierPath()
            inner.move(to: NSPoint(x: cx + side * 13, y: headY + 26))
            inner.line(to: NSPoint(x: cx + side * 18, y: headY + 35))
            inner.line(to: NSPoint(x: cx + side * 8, y: headY + 29))
            inner.close()
            inner.fill()
        }

        switch state {
        case .sleeping: drawSleepingEyes(cx: cx, headY: headY)
        case .reminder: drawAlertEyes(cx: cx, headY: headY)
        default:        drawNormalEyes(cx: cx, headY: headY)
        }

        NSColor(red: 0.9, green: 0.6, blue: 0.6, alpha: 1).setFill()
        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: cx, y: headY + 10))
        nose.line(to: NSPoint(x: cx - 3, y: headY + 13))
        nose.line(to: NSPoint(x: cx + 3, y: headY + 13))
        nose.close()
        nose.fill()

        NSColor.darkGray.setStroke()
        let mouth = NSBezierPath()
        mouth.lineWidth = 1
        mouth.move(to: NSPoint(x: cx, y: headY + 10))
        mouth.line(to: NSPoint(x: cx - 4, y: headY + 7))
        mouth.move(to: NSPoint(x: cx, y: headY + 10))
        mouth.line(to: NSPoint(x: cx + 4, y: headY + 7))
        mouth.stroke()

        NSColor(white: 0.7, alpha: 0.8).setStroke()
        let whisker = NSBezierPath()
        whisker.lineWidth = 0.8
        for side: CGFloat in [-1, 1] {
            for dy: CGFloat in [-2, 0, 2] {
                whisker.move(to: NSPoint(x: cx + side * 8, y: headY + 11 + dy))
                whisker.line(to: NSPoint(x: cx + side * 28, y: headY + 12 + dy * 1.5))
            }
        }
        whisker.stroke()

        NSColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 1).setStroke()
        let tail = NSBezierPath()
        tail.lineWidth = 4
        tail.lineCapStyle = .round
        tail.move(to: NSPoint(x: cx + 22, y: baseY + 10))
        tail.curve(to: NSPoint(x: cx + 38, y: baseY + 30),
                   controlPoint1: NSPoint(x: cx + 30, y: baseY + 5),
                   controlPoint2: NSPoint(x: cx + 42, y: baseY + 18))
        tail.stroke()

        NSColor(red: 0.45, green: 0.45, blue: 0.5, alpha: 1).setFill()
        for xOff: CGFloat in [-14, 14] {
            NSBezierPath(ovalIn: NSRect(x: cx + xOff - 6, y: baseY - 3, width: 12, height: 8)).fill()
        }

        if state == .sleeping {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor(white: 0.6, alpha: 0.7)
            ]
            "zzZ".draw(at: NSPoint(x: cx + 18, y: headY + 30), withAttributes: attrs)
        }

        if state == .reminder {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.orange
            ]
            "!".draw(at: NSPoint(x: cx + 16, y: headY + 32), withAttributes: attrs)
        }
    }

    private static func drawNormalEyes(cx: CGFloat, headY: CGFloat) {
        NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1).setFill()
        for side: CGFloat in [-1, 1] {
            NSBezierPath(ovalIn: NSRect(x: cx + side * 7 - 3, y: headY + 16, width: 6, height: 7)).fill()
        }
        NSColor(red: 0.4, green: 0.7, blue: 0.4, alpha: 1).setFill()
        for side: CGFloat in [-1, 1] {
            NSBezierPath(ovalIn: NSRect(x: cx + side * 7 - 2.5, y: headY + 16.5, width: 5, height: 6)).fill()
        }
        NSColor.black.setFill()
        for side: CGFloat in [-1, 1] {
            NSBezierPath(ovalIn: NSRect(x: cx + side * 7 - 1.5, y: headY + 17, width: 3, height: 5)).fill()
        }
        NSColor.white.setFill()
        for side: CGFloat in [-1, 1] {
            NSBezierPath(ovalIn: NSRect(x: cx + side * 7, y: headY + 20, width: 1.5, height: 1.5)).fill()
        }
    }

    private static func drawSleepingEyes(cx: CGFloat, headY: CGFloat) {
        NSColor.darkGray.setStroke()
        for side: CGFloat in [-1, 1] {
            let eye = NSBezierPath()
            eye.lineWidth = 1.5
            eye.move(to: NSPoint(x: cx + side * 7 - 4, y: headY + 19))
            eye.curve(to: NSPoint(x: cx + side * 7 + 4, y: headY + 19),
                      controlPoint1: NSPoint(x: cx + side * 7 - 1, y: headY + 16),
                      controlPoint2: NSPoint(x: cx + side * 7 + 1, y: headY + 16))
            eye.stroke()
        }
    }

    private static func drawAlertEyes(cx: CGFloat, headY: CGFloat) {
        NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1).setFill()
        for side: CGFloat in [-1, 1] {
            NSBezierPath(ovalIn: NSRect(x: cx + side * 7 - 4, y: headY + 15, width: 8, height: 9)).fill()
        }
        NSColor(red: 0.9, green: 0.7, blue: 0.2, alpha: 1).setFill()
        for side: CGFloat in [-1, 1] {
            NSBezierPath(ovalIn: NSRect(x: cx + side * 7 - 3, y: headY + 15.5, width: 6, height: 8)).fill()
        }
        NSColor.black.setFill()
        for side: CGFloat in [-1, 1] {
            NSBezierPath(ovalIn: NSRect(x: cx + side * 7 - 1, y: headY + 16, width: 2, height: 7)).fill()
        }
        NSColor.white.setFill()
        for side: CGFloat in [-1, 1] {
            NSBezierPath(ovalIn: NSRect(x: cx + side * 7 + 1, y: headY + 21, width: 2, height: 2)).fill()
        }
    }
}
