import Foundation
import MailSearchDomain

struct MemoryCache<Key: Equatable, Value> {
    private struct Entry {
        let key: Key
        let value: Value
        let expires: ContinuousClock.Instant
        let bytes: Int
    }

    private var entries: [Entry] = []

    mutating func value(for key: Key, now: ContinuousClock.Instant = .now) -> Value? {
        entries.removeAll { $0.expires <= now }
        return entries.first { $0.key == key }?.value
    }

    mutating func insert(_ value: Value, for key: Key, bytes: Int, now: ContinuousClock.Instant = .now) {
        entries.removeAll { $0.key == key || $0.expires <= now }
        guard bytes <= 16 * 1024 * 1024 else { return }
        entries.append(Entry(key: key, value: value, expires: now.advanced(by: .seconds(300)), bytes: bytes))
        while entries.count > 8 || entries.reduce(0, { $0 + $1.bytes }) > 16 * 1024 * 1024 {
            entries.removeFirst()
        }
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}

enum MailCacheKey: Equatable {
    case search(connectionKey: String, query: SearchQuery)
    case preview(connectionKey: String, location: MessageLocation)
}
