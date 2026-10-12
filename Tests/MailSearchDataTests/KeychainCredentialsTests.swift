import Foundation
@testable import MailSearchData
import MailSearchDomain
import Security
import Synchronization
import Testing

@Test(arguments: [errSecSuccess, errSecItemNotFound, errSecInteractionNotAllowed])
func `credential discovery requests metadata without authentication UI`(status: OSStatus) async throws {
    let index = try PropertyListEncoder().encode(["fixture"])
    let credentials = unsafe KeychainCredentials { attributes, result in
        // swiftlint:disable:next legacy_objc_type - Required Objective-C API bridge.
        let query = attributes as NSDictionary
        #expect(query[kSecReturnData] == nil)
        #expect(query[kSecReturnAttributes] as? Bool == true)
        #expect(query[kSecUseAuthenticationUI] as? String == kSecUseAuthenticationUISkip as String)
        #expect(query[kSecAttrService] as? String == "com.mikemcquaid.MailSearch.credentials")
        #expect(query[kSecAttrAccount] as? String == "imap-passwords-v1")
        unsafe result?.pointee = [kSecAttrGeneric as String: index] as CFDictionary
        return status
    }
    if status == errSecInteractionNotAllowed {
        await #expect(throws: SearchFailure.keychainAccess) { try await credentials.contains("fixture") }
    } else {
        #expect(try await credentials.contains("fixture") == (status == errSecSuccess))
        #expect(try await credentials.contains("another-connection") == false)
    }
}

@Test(arguments: [errSecSuccess, errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed])
func `all accounts share one Keychain read and denial per app session`(status: OSStatus) async throws {
    let lookups = Mutex(0)
    let passwords = ["fixture-one": "first-secret", "fixture-two": "second-secret"]
    let data = try PropertyListEncoder().encode(passwords)
    let credentials = unsafe KeychainCredentials { attributes, result in
        // swiftlint:disable:next legacy_objc_type - Required Objective-C API bridge.
        #expect((attributes as NSDictionary)[kSecAttrService] as? String == "com.mikemcquaid.MailSearch.credentials")
        lookups.withLock { $0 += 1 }
        unsafe result?.pointee = data as CFData
        return status
    }
    for key in ["fixture-one", "fixture-two"] {
        for _ in 0 ..< 3 {
            if status == errSecSuccess {
                #expect(try await credentials.password(for: key) == passwords[key])
            } else {
                await #expect(throws: SearchFailure.keychainAccess) { try await credentials.password(for: key) }
            }
        }
    }
    #expect(lookups.withLock { $0 } == 1)
}

@Test(arguments: [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled])
func `denied Keychain access is distinct from IMAP authentication`(status: OSStatus) async {
    let credentials = unsafe KeychainCredentials { _, _ in status }
    await #expect(throws: SearchFailure.keychainAccess) { try await credentials.password(for: "fixture") }
}

@Test
func `cancelled searches never request a Keychain password`() async {
    let credentials = unsafe KeychainCredentials { _, _ in
        Issue.record("A cancelled task must not request credential access")
        return errSecItemNotFound
    }
    let task = Task {
        unsafe withUnsafeCurrentTask { unsafe $0?.cancel() }
        return try await credentials.password(for: "fixture")
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test
func `explicit authorisation retries once for all accounts and reuses success`() async throws {
    let state = Mutex((allowed: false, reads: 0))
    let data = try PropertyListEncoder().encode(["one": "first-secret", "two": "second-secret"])
    let credentials = unsafe KeychainCredentials { _, result in
        state.withLock { value in
            value.reads += 1
            unsafe result?.pointee = data as CFData
            return value.allowed ? errSecSuccess : errSecAuthFailed
        }
    }
    for key in ["one", "two"] {
        await #expect(throws: SearchFailure.keychainAccess) { try await credentials.password(for: key) }
    }
    state.withLock { $0.allowed = true }
    try await credentials.authorise()
    try await credentials.authorise()
    #expect(try await credentials.password(for: "one") == "first-secret")
    #expect(try await credentials.password(for: "two") == "second-secret")
    #expect(try await credentials.password(for: "another-connection") == nil)
    #expect(state.withLock { $0.reads } == 2)
}

@Test(arguments: [errSecSuccess, errSecAuthFailed])
func `saving updates cached credentials only on success`(status: OSStatus) async throws {
    let reads = Mutex(0)
    let data = try PropertyListEncoder().encode(["fixture": "old-fixture", "other": "other-fixture"])
    let credentials = unsafe KeychainCredentials(
        copyMatching: { _, result in
            reads.withLock { $0 += 1 }
            unsafe result?.pointee = data as CFData
            return errSecSuccess
        },
        update: { _, _ in status },
    )
    #expect(try await credentials.password(for: "fixture") == "old-fixture")
    if status == errSecSuccess {
        try await credentials.save(password: "new-fixture", for: "fixture")
        #expect(try await credentials.password(for: "fixture") == "new-fixture")
        #expect(try await credentials.contains("fixture"))
    } else {
        await #expect(throws: SearchFailure.keychainAccess) {
            try await credentials.save(password: "new-fixture", for: "fixture")
        }
        #expect(try await credentials.password(for: "fixture") == "old-fixture")
    }
    #expect(try await credentials.password(for: "other") == "other-fixture")
    #expect(reads.withLock { $0 } == 1)
}

// swiftlint:disable function_body_length - The fixture verifies the complete ordered protocol or UI lifecycle.
@Test
func `passwords share one persistent item and metadata excludes secrets`() async throws {
    let state = Mutex((data: Data?.none, index: Data?.none, reads: 0, adds: 0))
    // swiftlint:disable:next closure_body_length - Shared Keychain fixture state.
    let credentials = {
        unsafe KeychainCredentials(
            copyMatching: { attributes, result in
                // swiftlint:disable:next legacy_objc_type - Required Objective-C API bridge.
                let query = attributes as NSDictionary
                #expect(query[kSecAttrService] as? String == "com.mikemcquaid.MailSearch.credentials")
                #expect(query[kSecAttrAccount] as? String == "imap-passwords-v1")
                return state.withLock { value in
                    guard let data = value.data, let index = value.index else {
                        return errSecItemNotFound
                    }

                    if query[kSecReturnData] as? Bool == true {
                        value.reads += 1
                        unsafe result?.pointee = data as CFData
                    } else {
                        unsafe result?.pointee = [kSecAttrGeneric as String: index] as CFDictionary
                    }
                    return errSecSuccess
                }
            },
            update: { _, values in
                state.withLock { value in
                    guard value.data != nil else {
                        return errSecItemNotFound
                    }

                    // swiftlint:disable:next legacy_objc_type - Required Objective-C API bridge.
                    value.data = (values as NSDictionary)[kSecValueData] as? Data
                    // swiftlint:disable:next legacy_objc_type - Required Objective-C API bridge.
                    value.index = (values as NSDictionary)[kSecAttrGeneric] as? Data
                    return errSecSuccess
                }
            },
            add: { attributes, _ in
                // swiftlint:disable:next legacy_objc_type - Required Objective-C API bridge.
                let query = attributes as NSDictionary
                #expect(query[kSecAttrService] as? String == "com.mikemcquaid.MailSearch.credentials")
                #expect(query[kSecAttrSynchronizable] as? Bool == false)
                state.withLock { value in
                    value.adds += 1
                    value.data = query[kSecValueData] as? Data
                    value.index = query[kSecAttrGeneric] as? Data
                }
                return errSecSuccess
            },
        )
    }
    let first = credentials()
    try await first.save(password: "first-secret", for: "one")
    try await first.save(password: "second-secret", for: "two")
    #expect(state.withLock { $0.adds } == 1)
    #expect(try PropertyListDecoder().decode([String].self, from: #require(state.withLock { $0.index })) == [
        "one",
        "two",
    ])
    let second = credentials()
    #expect(try await second.contains("one"))
    #expect(try await second.contains("two"))
    #expect(state.withLock { $0.reads } == 0)
    async let one = second.password(for: "one")
    async let two = second.password(for: "two")
    #expect(try await one == "first-secret")
    #expect(try await two == "second-secret")
    #expect(state.withLock { $0.reads } == 1)
    try await second.save(password: "replacement", for: "one")
    let third = credentials()
    #expect(try await third.contains("one"))
    #expect(try await third.password(for: "one") == "replacement")
    #expect(try await third.password(for: "two") == "second-secret")
    #expect(state.withLock { $0.adds } == 1)
}

// swiftlint:enable function_body_length

@Test(arguments: [errSecItemNotFound, errSecSuccess, errSecAuthFailed])
func `missing corrupt or denied storage never triggers per account reads`(status: OSStatus) async throws {
    let reads = Mutex(0)
    let credentials = unsafe KeychainCredentials { _, result in
        reads.withLock { $0 += 1 }
        unsafe result?.pointee = Data("invalid-storage".utf8) as CFData
        return status
    }
    for key in ["one", "two"] {
        if status == errSecItemNotFound {
            #expect(try await credentials.password(for: key) == nil)
        } else {
            let failure: SearchFailure = status == errSecSuccess ? .keychain : .keychainAccess
            await #expect(throws: failure) { try await credentials.password(for: key) }
            await #expect(throws: failure) { try await credentials.save(password: "secret", for: key) }
        }
    }
    #expect(reads.withLock { $0 } == 1)
}
