import AppKit

enum DesktopEnvironmentMonitor {
    static var isOnBatterySaver: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    static func isForegroundApplicationFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let values = window[kCGWindowBounds as String] as? [String: Any],
                  let x = (values["X"] as? NSNumber)?.doubleValue,
                  let y = (values["Y"] as? NSNumber)?.doubleValue,
                  let width = (values["Width"] as? NSNumber)?.doubleValue,
                  let height = (values["Height"] as? NSNumber)?.doubleValue
            else { continue }
            let bounds = CGRect(x: x, y: y, width: width, height: height)
            for screen in NSScreen.screens {
                let frame = screen.frame
                if abs(bounds.width - frame.width) <= 3, abs(bounds.height - frame.height) <= 3 {
                    return true
                }
            }
        }
        return false
    }
}
