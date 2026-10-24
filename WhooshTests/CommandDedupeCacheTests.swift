import Foundation
import Testing
import WhooshWire
@testable import Whoosh

/// Tests for the pure `CommandDedupeCache` (watch-companion task 6, design
/// "`RemoteCommandReducer`"; Requirements 6.2, 7.2–7.7). Written test-first.
///
/// The cache remembers completed replies keyed by `commandId` so a duplicate
/// delivery or a same-id retry (0 / 2.5 / 5 s) returns the identical reply
/// instead of re-applying the command. Entries expire after the window
/// (default 5 min) and the cache is capped (default 128), evicting the oldest.
struct CommandDedupeCacheTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func reply(_ outcome: WireCommandOutcome = .accepted) -> CommandDedupeCache.CachedReply {
        CommandDedupeCache.CachedReply(outcome: outcome)
    }

    // CD-1: a fresh cache has no reply for any id.
    @Test func cd1_emptyCacheMisses() {
        let cache = CommandDedupeCache()
        #expect(cache.cachedReply(for: "c1", at: t0) == nil)
        #expect(!cache.contains("c1", at: t0))
    }

    // CD-2: a recorded reply is returned for the same id (duplicate hit).
    @Test func cd2_duplicateReturnsCachedReply() {
        var cache = CommandDedupeCache()
        cache.recording("c1", reply: reply(.accepted), at: t0)
        #expect(cache.contains("c1", at: t0))
        #expect(cache.cachedReply(for: "c1", at: t0) == reply(.accepted))
    }

    // CD-3: an entry past the window expires and misses.
    @Test func cd3_expiresAfterWindow() {
        var cache = CommandDedupeCache(windowMs: 300_000, maxEntries: 128)
        cache.recording("c1", reply: reply(), at: t0)
        let justBefore = t0.addingTimeInterval(299.999)
        let atWindow = t0.addingTimeInterval(300) // 5 min boundary → expired
        #expect(cache.contains("c1", at: justBefore))
        #expect(!cache.contains("c1", at: atWindow))
    }

    // CD-4: inserting past the cap evicts the oldest entry.
    @Test func cd4_evictsOldestOverCap() {
        var cache = CommandDedupeCache(windowMs: 600_000, maxEntries: 2)
        cache.recording("old", reply: reply(), at: t0)
        cache.recording("mid", reply: reply(), at: t0.addingTimeInterval(1))
        cache.recording("new", reply: reply(), at: t0.addingTimeInterval(2))
        let now = t0.addingTimeInterval(2)
        #expect(cache.count == 2)
        #expect(!cache.contains("old", at: now)) // oldest evicted
        #expect(cache.contains("mid", at: now))
        #expect(cache.contains("new", at: now))
    }

    // CD-5: pruning drops only expired entries, keeping fresh ones.
    @Test func cd5_pruneKeepsFresh() {
        var cache = CommandDedupeCache(windowMs: 300_000, maxEntries: 128)
        cache.recording("stale", reply: reply(), at: t0)
        cache.recording("fresh", reply: reply(), at: t0.addingTimeInterval(299))
        let now = t0.addingTimeInterval(301) // stale is 301 s old, fresh is 2 s old
        cache.pruneExpired(at: now)
        #expect(!cache.contains("stale", at: now))
        #expect(cache.contains("fresh", at: now))
        #expect(cache.count == 1)
    }

    // CD-6: re-recording the same id overwrites and refreshes the timestamp.
    @Test func cd6_rerecordRefreshes() {
        var cache = CommandDedupeCache(windowMs: 300_000, maxEntries: 128)
        cache.recording("c1", reply: reply(.accepted), at: t0)
        // Re-record near expiry with a later timestamp.
        cache.recording("c1", reply: reply(.rejected), at: t0.addingTimeInterval(250))
        let now = t0.addingTimeInterval(400) // 400 s since t0, but 150 s since refresh
        #expect(cache.count == 1)
        #expect(cache.cachedReply(for: "c1", at: now) == reply(.rejected))
    }
}
