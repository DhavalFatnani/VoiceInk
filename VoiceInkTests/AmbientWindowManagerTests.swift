import AppKit
import SwiftUI
import Testing

@testable import VoiceInk

/// The ambient window's lifecycle, which is where the worst bug of the session lived.
///
/// Switching the recorder style to Mini left this window alive — the teardown was skipped whenever
/// the panel was not currently on screen — and the 1s watchdog that keeps it on the active display
/// went on calling `orderFrontRegardless` forever. A display-sized window forced itself to the
/// front once a second while the user was in a different recorder style entirely, and swallowed
/// every click on the machine.
///
/// Nothing here was covered, and none of it is hard to cover. The through-line of these tests is
/// that a window told to go away stays away, including past the watchdog's next tick.
@MainActor
struct AmbientWindowManagerTests {

    /// Longer than the 1s watchdog interval, so anything that resurrects the panel has had its
    /// chance to do so before the assertion runs.
    private let pastOneWatchdogTick = Duration.milliseconds(1_400)

    private func makeManager() -> AmbientWindowManager {
        AmbientWindowManager { AnyView(Color.clear) }
    }

    // MARK: - Showing

    @Test func showPutsAPanelOnScreen() {
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        #expect(manager.panelExists)
        #expect(manager.isPanelOnScreen)
    }

    @Test func theWindowNeverTakesFocus() {
        // It sits over whatever you are working in. Becoming key would pull focus out of the app
        // the text is about to land in, which is the failure that broke Undo earlier.
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        #expect(manager.panelCanBecomeKey == false)
    }

    @Test func showingTwiceIsHarmless() {
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        manager.show()
        #expect(manager.isPanelOnScreen)
    }

    // MARK: - The mouse
    //
    // The window is display-sized, so accepting events it does not need is how it ends up eating
    // clicks meant for other apps.

    @Test func theLightNeverAcceptsAMouseEvent() {
        // The invariant the whole two-window split exists to guarantee. This window is the size of
        // the display, and macOS offers exactly one real passthrough — a hitTest override stops a
        // *view* handling a click the window was already handed, it does not return the click to
        // the app underneath. Twice this cost the user their mouse before it was made permanent.
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        #expect(manager.panelIgnoresMouseEvents == true)

        manager.hide()
        manager.show()
        #expect(manager.panelIgnoresMouseEvents == true)
    }

    // MARK: - Going away, and staying away

    @Test func hideTakesThePanelOffScreen() {
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        manager.hide()
        #expect(!manager.isPanelOnScreen)
    }

    @Test func destroyLeavesNothingBehind() {
        let manager = makeManager()
        manager.show()
        manager.destroyWindow()
        #expect(!manager.panelExists)
    }

    @Test func aHiddenPanelIsNotResurrectedByTheWatchdog() async throws {
        // The exact shape of the bug. The watchdog exists to put the window back when a display
        // change strands it, and it must not confuse "hidden on purpose" with "stranded".
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        manager.hide()

        try await Task.sleep(for: pastOneWatchdogTick)
        #expect(!manager.isPanelOnScreen)
        #expect(manager.panelIgnoresMouseEvents == true)
    }

    @Test func aDestroyedPanelStaysDestroyed() async throws {
        let manager = makeManager()
        manager.show()
        manager.destroyWindow()

        try await Task.sleep(for: pastOneWatchdogTick)
        #expect(!manager.panelExists)
    }

    @Test func destroyingWithoutShowingIsSafe() {
        let manager = makeManager()
        manager.destroyWindow()
        #expect(!manager.panelExists)
    }

    @Test func itCanBeShownAgainAfterBeingDestroyed() {
        // Switching recorder style away and back does exactly this.
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        manager.destroyWindow()
        manager.show()
        #expect(manager.isPanelOnScreen)
    }

    // MARK: - Click-through

    @Test func theHostViewPassesThroughWhatItDoesNotDraw() {
        // NSHostingView answers a hit anywhere in its bounds with itself, which for a display-sized
        // window means claiming every click on the machine. Returning nil in that case is what lets
        // the event reach the window underneath.
        let host = AmbientPassthroughHostingView(rootView: Color.clear)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        #expect(host.hitTest(NSPoint(x: 400, y: 300)) == nil)
    }
}

/// Apps where the light is suppressed. Small, but it decides whether a full-screen overlay appears
/// during a video call.
@MainActor
struct AmbientAppExclusionsTests {

    private func withCleanExclusions(_ body: () -> Void) {
        let original = AmbientAppExclusions.bundleIdentifiers
        defer { AmbientAppExclusions.bundleIdentifiers = original }
        AmbientAppExclusions.bundleIdentifiers = []
        body()
    }

    @Test func nothingIsExcludedByDefault() {
        withCleanExclusions {
            #expect(!AmbientAppExclusions.isExcluded("com.example.anything"))
        }
    }

    @Test func anExcludedAppIsRecognised() {
        withCleanExclusions {
            AmbientAppExclusions.bundleIdentifiers = ["us.zoom.xos"]
            #expect(AmbientAppExclusions.isExcluded("us.zoom.xos"))
            #expect(!AmbientAppExclusions.isExcluded("com.apple.TextEdit"))
        }
    }

    @Test func anUnknownAppIsNotExcluded() {
        // A nil bundle identifier is normal — some processes have none — and must not be treated
        // as a match, which would suppress the light at random.
        withCleanExclusions {
            AmbientAppExclusions.bundleIdentifiers = ["us.zoom.xos"]
            #expect(!AmbientAppExclusions.isExcluded(nil))
        }
    }

    @Test func duplicatesCollapse() {
        withCleanExclusions {
            AmbientAppExclusions.bundleIdentifiers = ["a", "b", "a"]
            #expect(AmbientAppExclusions.bundleIdentifiers == ["a", "b"])
        }
    }

    @Test func removalSticks() {
        withCleanExclusions {
            AmbientAppExclusions.bundleIdentifiers = ["a", "b"]
            AmbientAppExclusions.bundleIdentifiers = ["b"]
            #expect(!AmbientAppExclusions.isExcluded("a"))
            #expect(AmbientAppExclusions.isExcluded("b"))
        }
    }

    @Test func changingTheListAnnouncesItself() {
        // The window manager re-evaluates on this notification. Without it a newly excluded app
        // keeps the light until the next take.
        withCleanExclusions {
            var announced = false
            let token = NotificationCenter.default.addObserver(
                forName: .ambientExclusionsChanged, object: nil, queue: .main
            ) { _ in announced = true }
            defer { NotificationCenter.default.removeObserver(token) }

            AmbientAppExclusions.bundleIdentifiers = ["us.zoom.xos"]
            #expect(announced)
        }
    }
}


/// The clickable half. Small, content-sized, and the only ambient window allowed to take a click.
@MainActor
struct AmbientControlWindowManagerTests {

    private func makeManager<V: View>(@ViewBuilder content: @escaping () -> V)
        -> AmbientControlWindowManager
    {
        AmbientControlWindowManager { AnyView(content()) }
    }

    private func withControls() -> AmbientControlWindowManager {
        makeManager { Text("Undo").padding(20) }
    }

    @Test func showPutsAPanelOnScreen() {
        let manager = withControls()
        defer { manager.destroyWindow() }

        manager.show()
        #expect(manager.panelExists)
        #expect(manager.isPanelOnScreen)
    }

    @Test func itNeverTakesFocus() {
        // Clicking Undo must not pull focus off the app the text just landed in, or the
        // synthesized Cmd+Z arrives here and does nothing. That bug is not being reintroduced
        // through a second window.
        let manager = withControls()
        defer { manager.destroyWindow() }

        manager.show()
        #expect(manager.panelCanBecomeKey == false)
    }

    @Test func theWindowIsOnlyAsBigAsItsContents() {
        // The safety property of the split. A window that accepts clicks must not cover anything
        // it does not draw, so it can never be anywhere near the size of the display.
        let manager = withControls()
        defer { manager.destroyWindow() }

        manager.show()
        let size = manager.panelSize
        #expect(size != nil)
        let screen = NSScreen.main?.frame.size ?? NSSize(width: 1440, height: 900)
        #expect(size!.width < screen.width / 2)
        #expect(size!.height < 200)
    }

    @Test func emptyContentIsTakenOffScreenEntirely() {
        // Sizing to content is not enough on its own: an empty rectangle left on screen still
        // absorbs clicks, which is the exact failure the split removes.
        let manager = AmbientControlWindowManager(hasContent: { false }) {
            AnyView(EmptyView())
        }
        defer { manager.destroyWindow() }

        manager.show()
        #expect(!manager.isPanelOnScreen)
    }

    @Test func hideTakesItOffScreen() {
        let manager = withControls()
        defer { manager.destroyWindow() }

        manager.show()
        manager.hide()
        #expect(!manager.isPanelOnScreen)
    }

    @Test func repositioningWhileHiddenDoesNotBringItBack() {
        // The screen-change observers call reposition(); none of them may resurrect a window that
        // was hidden on purpose.
        let manager = withControls()
        defer { manager.destroyWindow() }

        manager.show()
        manager.hide()
        manager.reposition()
        #expect(!manager.isPanelOnScreen)
    }

    @Test func destroyLeavesNothingBehind() {
        let manager = withControls()
        manager.show()
        manager.destroyWindow()
        #expect(!manager.panelExists)
    }

    @Test func destroyingWithoutShowingIsSafe() {
        let manager = withControls()
        manager.destroyWindow()
        #expect(!manager.panelExists)
    }

    @Test func itCanBeShownAgainAfterBeingDestroyed() {
        let manager = withControls()
        defer { manager.destroyWindow() }

        manager.show()
        manager.destroyWindow()
        manager.show()
        #expect(manager.isPanelOnScreen)
    }
}
