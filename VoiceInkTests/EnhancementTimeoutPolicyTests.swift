import Foundation
import Testing

@testable import VoiceInk

/// How long an enhancement is given before it is abandoned.
///
/// The local allowance was written once already and never took effect: `EnhancementTimeoutSeconds`
/// was also passed to `UserDefaults.register(defaults:)` as `7`, and a registered value comes back
/// from `integer(forKey:)` exactly like a stored one. Every read looked like a person's override,
/// the local branch was unreachable, and local models kept timing out after seven seconds — long
/// before a 7B model had finished loading off disk. Nothing showed up in `defaults read`, because
/// registered defaults never reach the plist.
///
/// The last test is the one that matters: it fails if anyone registers the key again.
struct EnhancementTimeoutPolicyTests {

    @Test func aLocalModelGetsTimeToLoadAndAnswer() {
        #expect(
            EnhancementTimeoutPolicy.seconds(runsLocally: true, overrideSeconds: 0)
                == EnhancementTimeoutPolicy.localSeconds
        )
    }

    @Test func aCloudCallGetsARoundTripsWorth() {
        #expect(
            EnhancementTimeoutPolicy.seconds(runsLocally: false, overrideSeconds: 0)
                == EnhancementTimeoutPolicy.cloudSeconds
        )
    }

    @Test func theLocalAllowanceIsLongerThanACloudRoundTrip() {
        // The whole point of the split: a local model cannot answer in a cloud call's budget.
        #expect(EnhancementTimeoutPolicy.localSeconds > EnhancementTimeoutPolicy.cloudSeconds)
    }

    @Test func anExplicitChoiceWinsForBoth() {
        #expect(EnhancementTimeoutPolicy.seconds(runsLocally: true, overrideSeconds: 45) == 45)
        #expect(EnhancementTimeoutPolicy.seconds(runsLocally: false, overrideSeconds: 45) == 45)
    }

    @Test func zeroAndNegativeAreNotChoices() {
        // `integer(forKey:)` returns 0 for an unset key, which must not read as "wait no time".
        #expect(
            EnhancementTimeoutPolicy.seconds(runsLocally: true, overrideSeconds: 0)
                == EnhancementTimeoutPolicy.localSeconds
        )
        #expect(
            EnhancementTimeoutPolicy.seconds(runsLocally: true, overrideSeconds: -5)
                == EnhancementTimeoutPolicy.localSeconds
        )
    }

    @Test func unsetDefaultsLeaveTheLocalAllowanceIntact() {
        let defaults = UserDefaults(suiteName: "EnhancementTimeoutPolicyTests.unset")!
        defaults.removePersistentDomain(forName: "EnhancementTimeoutPolicyTests.unset")

        #expect(
            EnhancementTimeoutPolicy.seconds(runsLocally: true, defaults: defaults)
                == EnhancementTimeoutPolicy.localSeconds
        )
    }

    /// The regression guard. Registering this key silently disables the local allowance.
    @Test func theTimeoutKeyIsNeverRegisteredAsADefault() {
        let probe = UserDefaults(suiteName: "EnhancementTimeoutPolicyTests.registration")!
        probe.removePersistentDomain(forName: "EnhancementTimeoutPolicyTests.registration")

        AppDefaults.registerDefaults()

        // A registered value would make this non-nil on a domain where nobody stored anything.
        let persisted = UserDefaults.standard
            .persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[
                EnhancementTimeoutPolicy.userDefaultsKey
            ]
        let visible = UserDefaults.standard.object(forKey: EnhancementTimeoutPolicy.userDefaultsKey)

        // Either nobody set it at all, or the only value present is one a person stored.
        #expect(visible == nil || persisted != nil)
    }
}
