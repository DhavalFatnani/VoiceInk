import Foundation
import os

enum LicenseKeychainKeys {
    static let licenseKey = "voiceink.license.key"
    static let trialStartDate = "voiceink.license.trialStartDate"
    static let activationId = "voiceink.license.activationId"
}

/// Both stored dependencies are thread-safe; neither `UserDefaults` nor `KeychainService` can say
/// so in the type system, which is the same gap already bridged for `KeychainService` itself.
///
/// The migration runs on every state load until it succeeds, which is right when the Keychain is
/// merely locked or busy. It is wrong when the Keychain has refused the build outright: an ad-hoc
/// signed app has no Keychain entitlement, so all three writes fail with `errSecMissingEntitlement`
/// every time, the done-flag is never set, and the next load tries all three again. That turned
/// into a permanent stream of failing `securityd` round trips and error logs for as long as the app
/// was open. A permanent refusal now stops the retries for the rest of the process — a relaunch
/// still tries once, so a properly signed build installed later is not locked out.
final class LicenseKeychainAccessibilityMigration: @unchecked Sendable {
    private let keychain: KeychainService
    private let defaults: UserDefaults
    private let migrationKey = "VoiceInkLicenseAccessibilityMigrationV1"
    private let accessibility = KeychainService.Accessibility.afterFirstUnlockThisDeviceOnly
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "LicenseKeychainAccessibilityMigration"
    )

    private let lock = NSLock()
    private var keychainRefusedThisBuild = false

    init(
        keychain: KeychainService = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.defaults = defaults
    }

    /// Whether the migration is settled — because it ran, because it had nothing to do, or because
    /// this build cannot use the Keychain at all. Only a transient failure returns `false`, and
    /// only that is worth trying again.
    func runIfNeeded(for state: StoredLicenseState) -> Bool {
        guard !defaults.bool(forKey: migrationKey) else { return true }

        lock.lock()
        let alreadyRefused = keychainRefusedThisBuild
        lock.unlock()

        if alreadyRefused { return true }

        var results: [KeychainService.WriteResult] = []

        if let licenseKey = state.licenseKey {
            results.append(
                keychain.write(
                    licenseKey,
                    forKey: LicenseKeychainKeys.licenseKey,
                    syncable: false,
                    accessibility: accessibility
                )
            )
        }

        if let activationId = state.activationId {
            results.append(
                keychain.write(
                    activationId,
                    forKey: LicenseKeychainKeys.activationId,
                    syncable: false,
                    accessibility: accessibility
                )
            )
        }

        if let trialStartDate = state.trialStartDate {
            results.append(
                keychain.write(
                    String(trialStartDate.timeIntervalSince1970),
                    forKey: LicenseKeychainKeys.trialStartDate,
                    syncable: false,
                    accessibility: accessibility
                )
            )
        }

        guard results.contains(where: { !$0.didSave }) else {
            defaults.set(true, forKey: migrationKey)
            return true
        }

        guard results.contains(where: { $0.isPermanent }) else {
            return false
        }

        lock.lock()
        let shouldLog = !keychainRefusedThisBuild
        keychainRefusedThisBuild = true
        lock.unlock()

        if shouldLog {
            logger.error(
                "The Keychain will not accept writes from this build, so the license accessibility migration cannot run. Skipping it until the next launch."
            )
        }

        return true
    }
}
