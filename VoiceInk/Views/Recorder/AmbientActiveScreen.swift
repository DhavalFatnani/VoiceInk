import AppKit

/// Which display the person is actually working on.
///
/// `NSScreen.main` answers a narrower question than its name suggests: it is the screen holding the
/// key window of the *active* application. The ambient panel is deliberately non-activating, so
/// during a take the active application is whatever was already in front — and when that app has no
/// key window anywhere (a space just changed, the desktop has focus, a full-screen app is
/// transitioning) `NSScreen.main` falls back to the screen carrying the menu bar.
///
/// On one display that fallback is invisible. On two it strands the light on the display the person
/// is not looking at, which is indistinguishable from the ambient simply failing to appear.
///
/// So the frontmost application's own front window is asked first, and asked through the window
/// server rather than the accessibility API: `CGWindowListCopyWindowInfo` reads the server's own
/// records and does not wait on the other process. That matters because this runs on a one-second
/// watchdog, where blocking on a busy app would be far worse than a misplaced window.
enum AmbientActiveScreen {

    /// Nonisolated to match `AmbientGeometry.current()`, which resolves the same display from a
    /// view's stored-property initialiser. These are AppKit reads and every caller is on the main
    /// thread; the isolation would only move the problem to the call sites.
    static func current() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let windowFrame = frontmostWindowFrame(primaryHeight: screens[0].frame.maxY),
            let index = indexOfScreen(bestMatching: windowFrame, in: screens.map(\.frame))
        {
            return screens[index]
        }

        return NSScreen.main ?? screens.first
    }

    /// The frontmost application's front window, in AppKit coordinates.
    private static func frontmostWindowFrame(primaryHeight: CGFloat) -> CGRect? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }

        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return nil
        }

        // The list is front-to-back, so the first match is the window in front.
        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == frontmostPID,
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                rect.width > 0, rect.height > 0
            else {
                continue
            }

            return convertFromCoreGraphics(rect, primaryHeight: primaryHeight)
        }

        return nil
    }

    /// Core Graphics puts the origin at the top-left of the primary display with y increasing
    /// downward; AppKit puts it at the bottom-left with y increasing upward. Mixing them silently
    /// picks the wrong display on any stacked or vertically offset arrangement.
    static func convertFromCoreGraphics(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// The screen a window most belongs to: the one it covers most of, or failing any overlap the
    /// one nearest its centre.
    ///
    /// Overlap rather than "contains the centre", because a window straddling two displays belongs
    /// to whichever shows more of it — the display the person is reading.
    static func indexOfScreen(bestMatching rect: CGRect, in screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }

        var bestIndex: Int?
        var bestArea: CGFloat = 0

        for (index, frame) in screenFrames.enumerated() {
            let intersection = frame.intersection(rect)
            guard !intersection.isNull else { continue }

            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }

        if let bestIndex { return bestIndex }

        // Entirely off every display — minimised, or on a space being torn down. Nearest wins.
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        return screenFrames.indices.min { first, second in
            squaredDistance(from: centre, to: screenFrames[first])
                < squaredDistance(from: centre, to: screenFrames[second])
        }
    }

    private static func squaredDistance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        return dx * dx + dy * dy
    }
}
