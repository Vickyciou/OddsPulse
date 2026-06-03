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

    func testConnectPublishesConnectedEventWhenMatchIDsAreProvided() async {
        let client = MockOddsWebSocketClient()
        let matchIDs = [1001, 1002, 1003]
        let events = client.connect(matchIDs: matchIDs)
        var iterator = events.makeAsyncIterator()

        let event = await iterator.next()
        client.disconnect()

        XCTAssertEqual(event, .connected)
    }

    func testConnectFinishesStreamWhenMatchIDsAreEmpty() async {
        let client = MockOddsWebSocketClient()
        let events = client.connect(matchIDs: [])
        var iterator = events.makeAsyncIterator()

        let event = await iterator.next()
        let nextEvent = await iterator.next()

        XCTAssertEqual(event, .disconnected(reason: .noMatchIDs))
        XCTAssertNil(nextEvent)
    }

    func testDisconnectFinishesOddsUpdatesStream() async {
        let client = MockOddsWebSocketClient()
        let events = client.connect(matchIDs: [1001])
        var iterator = events.makeAsyncIterator()

        client.disconnect()

        let event = await iterator.next()
        let nextEvent = await iterator.next()
        XCTAssertEqual(event, .disconnected(reason: .manual))
        XCTAssertNil(nextEvent)
    }

}
