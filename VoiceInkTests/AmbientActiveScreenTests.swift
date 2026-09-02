import AppKit
import Testing

@testable import VoiceInk

/// Choosing the display the ambient light belongs on.
///
/// The panel was placed with `NSScreen.main`, which is the screen holding the *active app's key
/// window* — not the screen the person is looking at. With two displays that regularly put the glow
/// on the wrong one, or on the one carrying the menu bar when no app had a key window at all, and
/// from the front it looked like the ambient randomly failing to appear.
///
/// The geometry is what is testable here, and it is where the mistakes live: a coordinate space
/// flip, or a window straddling two displays.
struct AmbientActiveScreenTests {

    // A built-in Retina display with an ultra-wide to its right, as on the machine this was found on.
    private let builtIn = CGRect(x: 0, y: 0, width: 1280, height: 832)
    private let ultraWide = CGRect(x: 1280, y: 0, width: 1720, height: 720)

    private var screens: [CGRect] { [builtIn, ultraWide] }

    @Test func aWindowOnTheBuiltInPicksTheBuiltIn() {
        let window = CGRect(x: 100, y: 100, width: 600, height: 400)
        #expect(AmbientActiveScreen.indexOfScreen(bestMatching: window, in: screens) == 0)
    }

    @Test func aWindowOnTheUltraWidePicksTheUltraWide() {
        let window = CGRect(x: 1500, y: 100, width: 600, height: 400)
        #expect(AmbientActiveScreen.indexOfScreen(bestMatching: window, in: screens) == 1)
    }

    @Test func aStraddlingWindowPicksWhicheverShowsMoreOfIt() {
        // Mostly on the ultra-wide: 100pt of it left of the boundary, 500pt right of it.
        let window = CGRect(x: 1180, y: 100, width: 600, height: 400)
        #expect(AmbientActiveScreen.indexOfScreen(bestMatching: window, in: screens) == 1)

        // And the mirror image.
        let mirrored = CGRect(x: 780, y: 100, width: 600, height: 400)
        #expect(AmbientActiveScreen.indexOfScreen(bestMatching: mirrored, in: screens) == 0)
    }

    @Test func aWindowOffEveryDisplayFallsBackToTheNearest() {
        // Minimised or on a space being torn down — no overlap anywhere.
        let strays = CGRect(x: 4000, y: 3000, width: 100, height: 100)
        #expect(AmbientActiveScreen.indexOfScreen(bestMatching: strays, in: screens) == 1)
    }

    @Test func noScreensMeansNoChoice() {
        #expect(AmbientActiveScreen.indexOfScreen(bestMatching: builtIn, in: []) == nil)
    }

    @Test func coreGraphicsCoordinatesAreFlippedIntoAppKitsSpace() {
        // CG measures y down from the top of the primary display; AppKit measures it up from the
        // bottom. A window flush with the top of an 832pt primary starts at CG y=0...
        let atTop = CGRect(x: 0, y: 0, width: 600, height: 400)
        let converted = AmbientActiveScreen.convertFromCoreGraphics(atTop, primaryHeight: 832)

        // ...and its AppKit origin is therefore 832 - 0 - 400.
        #expect(converted.origin.y == 432)
        #expect(converted.origin.x == 0)
        #expect(converted.size == atTop.size)
    }

    @Test func aWindowFlushWithTheBottomConvertsToZero() {
        let atBottom = CGRect(x: 0, y: 432, width: 600, height: 400)
        let converted = AmbientActiveScreen.convertFromCoreGraphics(atBottom, primaryHeight: 832)
        #expect(converted.origin.y == 0)
    }

    @Test func conversionRoundTrips() {
        let original = CGRect(x: 120, y: 240, width: 800, height: 300)
        let there = AmbientActiveScreen.convertFromCoreGraphics(original, primaryHeight: 832)
        let back = AmbientActiveScreen.convertFromCoreGraphics(there, primaryHeight: 832)
        #expect(back == original)
    }

    @Test func aDisplayAboveThePrimaryStillResolves() {
        // Vertically stacked displays are exactly where a coordinate flip goes unnoticed.
        let stacked = [builtIn, CGRect(x: 0, y: 832, width: 1280, height: 800)]
        let upper = CGRect(x: 100, y: 900, width: 600, height: 400)
        #expect(AmbientActiveScreen.indexOfScreen(bestMatching: upper, in: stacked) == 1)
    }
}
