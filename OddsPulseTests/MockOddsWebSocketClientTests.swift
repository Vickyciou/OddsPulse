import XCTest
@testable import OddsPulse

@MainActor
final class MockOddsWebSocketClientTests: XCTestCase {
    func testMakeUpdateBatchUsesKnownMatchIDsWithoutDuplicates() {
        let client = MockOddsWebSocketClient()
        let matchIDs = Array(1001...1100)

        for _ in 0..<20 {
            let batch = client.makeUpdateBatch(matchIDs: matchIDs)
            let batchMatchIDs = batch.map(\.matchID)

            XCTAssertTrue((1...10).contains(batch.count))
            XCTAssertEqual(Set(batchMatchIDs).count, batchMatchIDs.count)
            XCTAssertTrue(batchMatchIDs.allSatisfy { matchIDs.contains($0) })
        }
    }

    func testMakeUpdateBatchReturnsEmptyBatchWhenMatchIDsAreEmpty() {
        let client = MockOddsWebSocketClient()

        XCTAssertEqual(client.makeUpdateBatch(matchIDs: []), [])
    }

    func testConnectPublishesOddsUpdatesToStream() async {
        let client = MockOddsWebSocketClient()
        let matchIDs = [1001, 1002, 1003]
        let oddsUpdates = client.connect(matchIDs: matchIDs)
        var iterator = oddsUpdates.makeAsyncIterator()

        let batch = await iterator.next()
        client.disconnect()

        let batchMatchIDs = batch?.map(\.matchID) ?? []
        XCTAssertFalse(batchMatchIDs.isEmpty)
        XCTAssertTrue(batchMatchIDs.allSatisfy { matchIDs.contains($0) })
    }

    func testDisconnectFinishesOddsUpdatesStream() async {
        let client = MockOddsWebSocketClient()
        let oddsUpdates = client.connect(matchIDs: [1001])
        var iterator = oddsUpdates.makeAsyncIterator()

        client.disconnect()

        let batch = await iterator.next()
        XCTAssertNil(batch)
    }

    func testReconnectPublishesOddsUpdatesToNewStream() async {
        let client = MockOddsWebSocketClient()
        let matchIDs = [1001, 1002, 1003]

        let firstOddsUpdates = client.connect(matchIDs: matchIDs)
        var firstIterator = firstOddsUpdates.makeAsyncIterator()
        let firstBatch = await firstIterator.next()
        client.disconnect()

        let secondOddsUpdates = client.connect(matchIDs: matchIDs)
        var secondIterator = secondOddsUpdates.makeAsyncIterator()
        let secondBatch = await secondIterator.next()
        client.disconnect()

        let firstBatchMatchIDs = firstBatch?.map(\.matchID) ?? []
        let secondBatchMatchIDs = secondBatch?.map(\.matchID) ?? []
        XCTAssertFalse(firstBatchMatchIDs.isEmpty)
        XCTAssertFalse(secondBatchMatchIDs.isEmpty)
        XCTAssertTrue(firstBatchMatchIDs.allSatisfy { matchIDs.contains($0) })
        XCTAssertTrue(secondBatchMatchIDs.allSatisfy { matchIDs.contains($0) })
    }
}
