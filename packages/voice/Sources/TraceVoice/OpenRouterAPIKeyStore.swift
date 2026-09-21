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
    private let service: String
    private let account: String

    public init(
        service: String = "com.traceproject.app.openrouter",
        account: String = "api-key"
    ) {
        self.service = service
        self.account = account
    }

    public func loadAPIKey() throws -> String? {
        var query = baseQuery
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
        guard let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8)
        else {
            throw OpenRouterAPIKeyStoreError.keychain(errSecDecode)
        }
        return apiKey
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            throw OpenRouterAPIKeyStoreError.emptyAPIKey
        }
        let data = Data(trimmed.utf8)
        let attributes = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlock,
        ] as [String: Any]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw OpenRouterAPIKeyStoreError.keychain(updateStatus)
        }
        var item = baseQuery
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenRouterAPIKeyStoreError.keychain(addStatus)
        }
    }

    public func removeAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenRouterAPIKeyStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
