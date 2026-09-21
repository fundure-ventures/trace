import Foundation
import Security

public protocol OpenRouterAPIKeyStoring: AnyObject {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func removeAPIKey() throws
}

public enum OpenRouterAPIKeyStoreError: LocalizedError, Equatable {
    case emptyAPIKey
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "Enter an OpenRouter API key."
        case let .keychain(status):
            if status == errSecInvalidOwnerEdit {
                return "Trace cannot reset this key because macOS assigned "
                    + "it to an older build. Delete the Trace OpenRouter key "
                    + "in Keychain Access, then add it again."
            }
            let detail = SecCopyErrorMessageString(status, nil) as String?
            return detail.map {
                "Trace could not access the OpenRouter key in Keychain: \($0)"
            } ?? "Trace could not access the OpenRouter key in Keychain."
        }
    }
}

public final class OpenRouterKeychainStore: OpenRouterAPIKeyStoring {
    private static let resetMarker = Data("reset".utf8)

    private let service: String
    private let legacyAccount: String
    private let activeAccount: String
    private let resetMarkerAccount: String

    public init(
        service: String = "com.traceproject.app.openrouter",
        account: String = "api-key"
    ) {
        self.service = service
        legacyAccount = account
        activeAccount = "\(account).v2"
        resetMarkerAccount = "\(account).v2-reset"
    }

    public func loadAPIKey() throws -> String? {
        if try itemData(account: resetMarkerAccount) != nil {
            return nil
        }
        if let data = try itemData(account: activeAccount) {
            return try decodeAPIKey(data)
        }
        guard let data = try itemData(account: legacyAccount) else {
            return nil
        }
        return try decodeAPIKey(data)
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            throw OpenRouterAPIKeyStoreError.emptyAPIKey
        }
        try upsert(
            Data(trimmed.utf8),
            account: activeAccount
        )
        try removeItem(account: resetMarkerAccount)
        try removeLegacyItem()
    }

    public func removeAPIKey() throws {
        try upsert(
            Self.resetMarker,
            account: resetMarkerAccount
        )
        try removeItem(account: activeAccount)
        try removeLegacyItem()
    }

    private func itemData(account: String) throws -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw OpenRouterAPIKeyStoreError.keychain(status)
        }
        guard let data = result as? Data else {
            throw OpenRouterAPIKeyStoreError.keychain(errSecDecode)
        }
        return data
    }

    private func decodeAPIKey(_ data: Data) throws -> String {
        guard let apiKey = String(data: data, encoding: .utf8) else {
            throw OpenRouterAPIKeyStoreError.keychain(errSecDecode)
        }
        return apiKey
    }

    private func upsert(_ data: Data, account: String) throws {
        let updateStatus = SecItemUpdate(
            query(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw OpenRouterAPIKeyStoreError.keychain(updateStatus)
        }
        var item = query(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenRouterAPIKeyStoreError.keychain(addStatus)
        }
    }

    private func removeItem(account: String) throws {
        let status = SecItemDelete(
            query(account: account) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenRouterAPIKeyStoreError.keychain(status)
        }
    }

    private func removeLegacyItem() throws {
        do {
            try removeItem(account: legacyAccount)
        } catch OpenRouterAPIKeyStoreError.keychain(let status)
            where status == errSecInvalidOwnerEdit {
            return
        }
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
