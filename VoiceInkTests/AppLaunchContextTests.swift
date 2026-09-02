import Foundation
import Testing

@testable import VoiceInk

/// Telling a login item's launch apart from a person's.
///
/// With "Hide Dock Icon" on, the app runs as an accessory and the main window was ordered out on
/// every launch — so opening VoiceInk from Applications did nothing visible, while the same window
/// opened fine from the menu bar. Only a login item should start silently, and the difference is
/// read from the launchd job name because macOS reports it nowhere else.
struct AppLaunchContextTests {

    private let bundleIdentifier = "com.prakashjoshipax.VoiceInk"

    private func isLoginItem(_ environment: [String: String]) -> Bool {
        AppLaunchContext.isLoginItemLaunch(
            environment: environment,
            bundleIdentifier: bundleIdentifier
        )
    }

    @Test func launchdNamesTheBundleForALoginItem() {
        // SMAppService registers login items under a job named after the bundle.
        #expect(isLoginItem(["XPC_SERVICE_NAME": "application.com.prakashjoshipax.VoiceInk.12345.67890"]))
    }

    @Test func finderLaunchesCarryNoJobName() {
        #expect(!isLoginItem([:]))
        #expect(!isLoginItem(["XPC_SERVICE_NAME": "0"]))
    }

    @Test func anotherAppsJobIsNotOurLoginItem() {
        #expect(!isLoginItem(["XPC_SERVICE_NAME": "application.com.example.Other.1.2"]))
    }

    @Test func anUnknownEnvironmentCountsAsAPersonsLaunch() {
        // The doubt resolves toward showing the window: an unexpected window beats a dead-looking app.
        #expect(!isLoginItem(["SOME_OTHER_KEY": "value"]))
    }

    @Test func amissingBundleIdentifierCountsAsAPersonsLaunch() {
        #expect(
            !AppLaunchContext.isLoginItemLaunch(
                environment: ["XPC_SERVICE_NAME": "application.com.prakashjoshipax.VoiceInk.1.2"],
                bundleIdentifier: nil
            )
        )
        #expect(
            !AppLaunchContext.isLoginItemLaunch(
                environment: ["XPC_SERVICE_NAME": "application.com.prakashjoshipax.VoiceInk.1.2"],
                bundleIdentifier: ""
            )
        )
    }
}
