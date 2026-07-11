import Foundation
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSystem

@Suite("Authorized location cache")
struct AuthorizedLocationCacheTests {
  @Test("one-shot location remains process-local, bounded, and clearable")
  func cacheLifetime() async {
    let cache = AuthorizedLocationCache()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let region = LocationRegion(latitude: 37.5, longitude: 127.0, radiusMeters: 25)

    await cache.store(region, timestamp: timestamp)

    #expect(
      await cache.recentLocation(
        maximumAge: 300,
        now: timestamp.addingTimeInterval(299)
      ) == region
    )
    #expect(
      await cache.recentLocation(
        maximumAge: 300,
        now: timestamp.addingTimeInterval(301)
      ) == nil
    )

    await cache.clear()
    #expect(await cache.recentLocation(maximumAge: 300, now: timestamp) == nil)
  }

  @Test("invalid coordinates are never cached")
  func rejectsInvalidCoordinates() async {
    let cache = AuthorizedLocationCache()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    await cache.store(
      LocationRegion(latitude: .nan, longitude: 0, radiusMeters: 10),
      timestamp: timestamp
    )

    #expect(await cache.recentLocation(maximumAge: 300, now: timestamp) == nil)
  }
}
