import Foundation

/// Who started this launch.
///
/// "Hide Dock Icon" makes the app an accessory, and an accessory launch used to order the main
/// window straight back out — so opening VoiceInk from Applications looked like nothing happened
/// at all, while the same window opened fine from the menu bar. The setting is meant to remove the
/// Dock icon, not to make the app unopenable.
///
/// The two launches want opposite things: a login item should stay out of the way, and a launch a
/// person performed should put the window in front of them. macOS does not report the difference
/// directly, so the launchd job name stands in for it — login items registered through
/// `SMAppService` run under a job named after the bundle, and a Finder or Spotlight launch carries
/// no such name.
enum AppLaunchContext {
    /// Whether launchd started this process as a registered login item.
    ///
    /// Unknown environments count as a person's launch. An unexpected window at login is a smaller
    /// failure than an app that appears dead when opened, so the doubt resolves toward showing it.
    static func isLoginItemLaunch(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        guard let jobName = environment["XPC_SERVICE_NAME"] else { return false }
        return jobName.contains(bundleIdentifier)
    }
}
