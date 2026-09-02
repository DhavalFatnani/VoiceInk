import Foundation

/// How long to wait for an enhancement, which is a different question for a hosted API than for a
/// model running on this machine.
///
/// Seven seconds is generous for a cloud endpoint and impossible for a local one — a 7B model has
/// to be paged off disk and loaded before it produces its first token, which alone can take longer
/// than that. The local allowance exists so that work can finish.
///
/// It is kept here, away from `UserDefaults.register(defaults:)`, because that is what broke it
/// before. `EnhancementTimeoutSeconds` was registered as `7`, and a registered value is
/// indistinguishable from a stored one through `UserDefaults.integer(forKey:)` — it is returned
/// just the same. The override check therefore matched on every launch, the local branch became
/// unreachable, and every local model kept the cloud's seven seconds no matter what the code below
/// it said. Nothing appeared in `defaults read` to explain it, because registered defaults live in
/// memory and never reach the plist.
///
/// So: this key must never be registered. Only a person setting it explicitly may override.
enum EnhancementTimeoutPolicy {
    static let userDefaultsKey = "EnhancementTimeoutSeconds"

    /// Enough for a network round trip and a hosted model's reply.
    static let cloudSeconds: TimeInterval = 7

    /// Enough to load a local model off disk and let it answer.
    static let localSeconds: TimeInterval = 180

    /// - Parameter overrideSeconds: what the person has explicitly chosen, or `0` when they have
    ///   not chosen anything. A registered fallback must never arrive here.
    static func seconds(runsLocally: Bool, overrideSeconds: Int) -> TimeInterval {
        if overrideSeconds > 0 {
            return TimeInterval(overrideSeconds)
        }
        return runsLocally ? localSeconds : cloudSeconds
    }

    static func seconds(runsLocally: Bool, defaults: UserDefaults = .standard) -> TimeInterval {
        seconds(runsLocally: runsLocally, overrideSeconds: defaults.integer(forKey: userDefaultsKey))
    }
}
