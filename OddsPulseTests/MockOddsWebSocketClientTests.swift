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
        let updateTask = Task { @MainActor in
            var iterator = client.oddsUpdates.makeAsyncIterator()
            return await iterator.next()
        }

        client.connect(matchIDs: matchIDs)
        let batch = await updateTask.value
        client.disconnect()

        let batchMatchIDs = batch?.map(\.matchID) ?? []
        XCTAssertFalse(batchMatchIDs.isEmpty)
        XCTAssertTrue(batchMatchIDs.allSatisfy { matchIDs.contains($0) })
    }
}
