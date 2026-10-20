// Posts real, OS-level mouse events, so a terminal's own mouse reporting is what a probe measures.
//   mouse-inject bounds OWNER                       -> x y w h of that app's largest on-screen window
//   mouse-inject click X Y [flags]                  -> press and release
//   mouse-inject drag X1 Y1 X2 Y2 [flags]           -> press, move in steps, release
//   mouse-inject wheel X Y LINES [flags]            -> scroll (positive is up)
// flags: shift option control command, comma separated.
import CoreGraphics
import Foundation

func flags(_ text: String?) -> CGEventFlags {
    var out: CGEventFlags = []
    for name in (text ?? "").split(separator: ",") {
        switch name {
            case "shift": out.insert(.maskShift)
            case "option": out.insert(.maskAlternate)
            case "control": out.insert(.maskControl)
            case "command": out.insert(.maskCommand)
            case "fn": out.insert(.maskSecondaryFn)
            default: break
        }
    }
    return out
}
let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ point: CGPoint, _ mods: CGEventFlags) {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    event?.flags = mods
    event?.post(tap: .cghidEventTap)
    usleep(30_000)
}
let a = CommandLine.arguments
func n(_ i: Int) -> Double { Double(a[i]) ?? 0 }
switch a.count > 1 ? a[1] : "" {
    case "bounds":
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        var best: (Double, [String: Double])?
        for window in windows
        where (window[kCGWindowOwnerName as String] as? String) == a[2]
            && (window[kCGWindowLayer as String] as? Int) == 0
        {
            guard let b = window[kCGWindowBounds as String] as? [String: Double] else { continue }
            let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
            if area > (best?.0 ?? 0) { best = (area, b) }
        }
        if let b = best?.1 {
            print(Int(b["X"] ?? 0), Int(b["Y"] ?? 0), Int(b["Width"] ?? 0), Int(b["Height"] ?? 0))
        } else {
            exit(1)
        }
    case "owners":
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        var seen = Set<String>()
        for window in windows where (window[kCGWindowLayer as String] as? Int) == 0 {
            if let owner = window[kCGWindowOwnerName as String] as? String { seen.insert(owner) }
        }
        print(seen.sorted().joined(separator: " | "))
    case "click":
        let p = CGPoint(x: n(2), y: n(3))
        let m = flags(a.count > 4 ? a[4] : nil)
        post(.mouseMoved, p, m)
        post(.leftMouseDown, p, m)
        post(.leftMouseUp, p, m)
    case "drag":
        let p1 = CGPoint(x: n(2), y: n(3))
        let p2 = CGPoint(x: n(4), y: n(5))
        let m = flags(a.count > 6 ? a[6] : nil)
        post(.mouseMoved, p1, m)
        post(.leftMouseDown, p1, m)
        for step in 1 ... 10 {
            let t = Double(step) / 10
            post(.leftMouseDragged, CGPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t), m)
        }
        post(.leftMouseUp, p2, m)
    case "wheel":
        let p = CGPoint(x: n(2), y: n(3))
        post(.mouseMoved, p, [])
        let event = CGEvent(
            scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: Int32(n(4)), wheel2: 0, wheel3: 0)
        event?.flags = flags(a.count > 5 ? a[5] : nil)
        event?.post(tap: .cghidEventTap)
    default:
        FileHandle.standardError.write(Data("usage: see the header\n".utf8))
        exit(2)
}
