import Foundation
import Security
import os

/// Stores credentials with caller-selected Keychain synchronization and accessibility.
/// Keychain access is thread-safe; the imports just cannot express it.
final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()

    enum Accessibility {
        case afterFirstUnlockThisDeviceOnly

        fileprivate var value: CFString {
            switch self {
            case .afterFirstUnlockThisDeviceOnly:
                return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }

    enum ReadResult<Value> {
        case value(Value)
        case notFound
        case unavailable(OSStatus)
    }

    enum WriteResult {
        case saved
        case failed(OSStatus)

        var didSave: Bool {
            if case .saved = self { return true }
            return false
        }

        /// Whether retrying could ever succeed.
        var isPermanent: Bool {
            guard case .failed(let status) = self else { return false }
            return KeychainService.isPermanentFailure(status)
        }
    }

    /// Whether a Security status can clear on its own.
    ///
    /// A locked Keychain or a busy `securityd` does. A build the Keychain refuses to talk to — no
    /// signing entitlement, which is every ad-hoc signed build — refuses every subsequent call the
    /// same way, so anything looping on it is looping forever.
    static func isPermanentFailure(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecNotAvailable
    }

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "KeychainService")
    private let service = "com.prakashjoshipax.VoiceInk"

    private init() {}

    // MARK: - Public API

    /// Saves a string value to Keychain.
    @discardableResult
    func save(
        _ value: String,
        forKey key: String,
        syncable: Bool = true,
        accessibility: Accessibility? = nil
    ) -> Bool {
        write(value, forKey: key, syncable: syncable, accessibility: accessibility).didSave
    }

    /// Saves data to Keychain.
    @discardableResult
    func save(
        data: Data,
        forKey key: String,
        syncable: Bool = true,
        accessibility: Accessibility? = nil
    ) -> Bool {
        write(data: data, forKey: key, syncable: syncable, accessibility: accessibility).didSave
    }

    /// Saves a string while preserving the Security framework status, so callers that retry can
    /// tell a transient failure from one that will never clear.
    func write(
        _ value: String,
        forKey key: String,
        syncable: Bool = true,
        accessibility: Accessibility? = nil
    ) -> WriteResult {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to convert value to data for key: \(key, privacy: .public)")
            return .failed(errSecParam)
        }
        return write(data: data, forKey: key, syncable: syncable, accessibility: accessibility)
    }

    /// Saves data while preserving the Security framework status.
    func write(
        data: Data,
        forKey key: String,
        syncable: Bool = true,
        accessibility: Accessibility? = nil
    ) -> WriteResult {
        let query = baseQuery(forKey: key, syncable: syncable)
        var attributes: [String: Any] = [kSecValueData as String: data]
        if let accessibility {
            attributes[kSecAttrAccessible as String] = accessibility.value
        }
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            logger.info("Successfully updated keychain item for key: \(key, privacy: .public)")
            return .saved
        }

        guard updateStatus == errSecItemNotFound else {
            logger.error(
                "Failed to update keychain item for key: \(key, privacy: .public), status: \(updateStatus, privacy: .public)"
            )
            return .failed(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        if let accessibility {
            addQuery[kSecAttrAccessible as String] = accessibility.value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecSuccess {
            logger.info("Successfully saved keychain item for key: \(key, privacy: .public)")
            return .saved
        }

        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if retryStatus == errSecSuccess {
                logger.info("Successfully updated concurrently created keychain item for key: \(key, privacy: .public)")
                return .saved
            }

            logger.error(
                "Failed to update concurrently created keychain item for key: \(key, privacy: .public), status: \(retryStatus, privacy: .public)"
            )
            return .failed(retryStatus)
        }

        logger.error(
            "Failed to save keychain item for key: \(key, privacy: .public), status: \(addStatus, privacy: .public)"
        )
        return .failed(addStatus)
    }

    /// Retrieves a string value from Keychain.
    func getString(forKey key: String, syncable: Bool = true) -> String? {
        guard let data = getData(forKey: key, syncable: syncable) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieves a string while distinguishing missing data from unavailable storage.
    func readString(forKey key: String, syncable: Bool = true) -> ReadResult<String> {
        switch readData(forKey: key, syncable: syncable) {
        case .value(let data):
            guard let value = String(data: data, encoding: .utf8) else {
                logger.error("Failed to decode keychain string for key: \(key, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .value(value)
        case .notFound:
            return .notFound
        case .unavailable(let status):
            return .unavailable(status)
        }
    }

    /// Retrieves data from Keychain.
    func getData(forKey key: String, syncable: Bool = true) -> Data? {
        guard case .value(let data) = readData(forKey: key, syncable: syncable) else {
            return nil
        }
        return data
    }

    /// Retrieves data while preserving the Security framework status.
    func readData(forKey key: String, syncable: Bool = true) -> ReadResult<Data> {
        var query = baseQuery(forKey: key, syncable: syncable)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            guard let data = result as? Data else {
                logger.error("Keychain returned invalid data for key: \(key, privacy: .public)")
                return .unavailable(errSecDecode)
            }
            return .value(data)
        }

        if status == errSecItemNotFound {
            return .notFound
        }

        logger.error(
            "Failed to retrieve keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)"
        )
        return .unavailable(status)
    }

    /// Deletes an item from Keychain.
    @discardableResult
    func delete(forKey key: String, syncable: Bool = true) -> Bool {
        let query = baseQuery(forKey: key, syncable: syncable)
        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            if status == errSecSuccess {
                logger.info("Successfully deleted keychain item for key: \(key, privacy: .public)")
            }
            return true
        } else {
            logger.error(
                "Failed to delete keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)"
            )
            return false
        }
    }

    /// Checks if a key exists in Keychain.
    func exists(forKey key: String, syncable: Bool = true) -> Bool {
        var query = baseQuery(forKey: key, syncable: syncable)
        query[kSecReturnData as String] = kCFBooleanFalse

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Private Helpers

    /// Creates a base Keychain query.
    private func baseQuery(forKey key: String, syncable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]

        if syncable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }

        return query
    }
}
