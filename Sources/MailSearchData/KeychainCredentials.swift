import Foundation
import MailSearchDomain
import Security

@safe public actor KeychainCredentials: CredentialStore {
    typealias Lookup = @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    typealias Update = @Sendable (CFDictionary, CFDictionary) -> OSStatus
    private let copyMatching: Lookup
    private let update: Update
    private let add: Lookup
    private var cached: Result<[String: String], SearchFailure>?

    public init() {
        unsafe self.init(
            copyMatching: { unsafe SecItemCopyMatching($0, $1) },
            update: { SecItemUpdate($0, $1) }, add: { unsafe SecItemAdd($0, $1) },
        )
    }

    init(
        copyMatching: @escaping Lookup,
        update: @escaping Update = { _, _ in errSecUnimplemented },
        add: @escaping Lookup = { _, _ in errSecUnimplemented },
    ) {
        unsafe self.copyMatching = copyMatching
        self.update = update
        unsafe self.add = add
    }

    public func contains(_ key: String) throws -> Bool {
        try Task.checkCancellation()
        if case let .success(passwords) = cached {
            return passwords[key] != nil
        }
        var query = attributes
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        var result: CFTypeRef?
        let status = unsafe copyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return false
        }
        guard status == errSecSuccess else { throw Self.failure(status) }
        guard let metadata = result as? [String: Any],
              let data = metadata[kSecAttrGeneric as String] as? Data,
              let keys = try? PropertyListDecoder().decode([String].self, from: data)
        else { throw SearchFailure.keychain }
        return keys.contains(key)
    }

    public func password(for key: String) throws -> String? {
        try passwords()[key]
    }

    public func authorise() throws {
        try Task.checkCancellation()
        if case .failure = cached {
            cached = nil
        }
        _ = try passwords()
    }

    public func save(password: String, for key: String) throws {
        var passwords = try passwords()
        passwords[key] = password
        try Task.checkCancellation()
        let values = try [
            kSecValueData as String: PropertyListEncoder().encode(passwords),
            kSecAttrGeneric as String: PropertyListEncoder().encode(passwords.keys.sorted()),
        ]
        let status = update(attributes as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var query = attributes.merging(values) { _, new in new }
            query[kSecAttrLabel as String] = "MailSearch Saved Passwords"
            let status = add(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw Self.failure(status) }
        } else if status != errSecSuccess {
            throw Self.failure(status)
        }
        cached = .success(passwords)
    }

    private func passwords() throws -> [String: String] {
        try Task.checkCancellation()
        if let cached {
            return try cached.get()
        }
        var query = attributes
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = unsafe copyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            cached = .success([:])
            return [:]
        }
        guard status == errSecSuccess else {
            let failure = Self.failure(status)
            cached = .failure(failure)
            throw failure
        }
        guard let data = result as? Data,
              let passwords = try? PropertyListDecoder().decode([String: String].self, from: data)
        else {
            cached = .failure(.keychain)
            throw SearchFailure.keychain
        }
        cached = .success(passwords)
        return passwords
    }

    private static func failure(_ status: OSStatus) -> SearchFailure {
        [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled].contains(status)
            ? .keychainAccess : .keychain
    }

    private var attributes: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.mikemcquaid.MailSearch.credentials",
         kSecAttrAccount as String: "imap-passwords-v1",
         kSecAttrSynchronizable as String: false]
    }
}
