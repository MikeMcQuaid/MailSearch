import MailSearchDomain

// MARK: - MemoryCache

struct MemoryCache<Key: Equatable, Value> {
    // MARK: Internal

    mutating func value(for key: Key, now: ContinuousClock.Instant = .now) -> Value? {
        entries.removeAll { $0.expires <= now }
        return entries.first { $0.key == key }?.value
    }

    mutating func insert(_ value: Value, for key: Key, bytes: Int, now: ContinuousClock.Instant = .now) {
        entries.removeAll { $0.key == key || $0.expires <= now }
        guard bytes <= byteLimit else {
            return
        }

        entries.append(Entry(key: key, value: value, expires: now.advanced(by: lifetime), bytes: bytes))
        while entries.count > entryLimit || entries.reduce(0, { $0 + $1.bytes }) > byteLimit {
            entries.removeFirst()
        }
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    // MARK: Private

    private struct Entry {
        let key: Key
        let value: Value
        let expires: ContinuousClock.Instant
        let bytes: Int
    }

    private let byteLimit = 16_777_216
    private let entryLimit = 8
    // swiftlint:disable:next no_magic_numbers - Cached results expire after five minutes.
    private let lifetime: Duration = .seconds(300)

    private var entries: [Entry] = []
}

// MARK: - MailCacheKey

enum MailCacheKey: Equatable {
    case search(connectionKey: String, query: SearchQuery)
    case preview(connectionKey: String, location: MessageLocation)
}
