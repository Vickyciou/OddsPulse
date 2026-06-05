import XCTest
@testable import OddsPulse

@MainActor
final class MockOddsWebSocketServiceTests: XCTestCase {
    func testConnectDelegatesMatchIDsToClientAndReturnsEvents() async throws {
        let client = ControllableOddsWebSocketClient()
        let service = MockOddsWebSocketService(webSocketClient: client)

        let stream = service.connect(matchIDs: [1001, 1002])
        client.send(.connected)

        let event = try await collectFirstEvent(from: stream)

        XCTAssertEqual(event, .connected)
        XCTAssertEqual(client.connectCallCount, 1)
        XCTAssertEqual(client.connectedMatchIDsHistory, [[1001, 1002]])
    }

    func testDisconnectDelegatesToClient() {
        let client = ControllableOddsWebSocketClient()
        let service = MockOddsWebSocketService(webSocketClient: client)

        service.disconnect()

        XCTAssertEqual(client.disconnectCallCount, 1)
    }

    private func collectFirstEvent(
        from stream: AsyncStream<OddsWebSocketEvent>,
        timeout: TimeInterval = 1
    ) async throws -> OddsWebSocketEvent {
        let expectation = expectation(description: "Collect first OddsWebSocketEvent")
        var iterator = stream.makeAsyncIterator()
        var collectedEvent: OddsWebSocketEvent?

        let task = Task { @MainActor in
            collectedEvent = await iterator.next()
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: timeout)
        task.cancel()

        return try XCTUnwrap(collectedEvent)
    }
}

@MainActor
private final class ControllableOddsWebSocketClient: OddsWebSocketClientProtocol {
    private var continuation: AsyncStream<OddsWebSocketEvent>.Continuation?

    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var connectedMatchIDsHistory: [[Int]] = []

    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketEvent> {
        connectCallCount += 1
        connectedMatchIDsHistory.append(matchIDs)

        let streamPair = AsyncStream<OddsWebSocketEvent>.makeStream(
            of: OddsWebSocketEvent.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        continuation = streamPair.continuation
        return streamPair.stream
    }

    func disconnect() {
        disconnectCallCount += 1
        continuation?.yield(.disconnected(reason: .manual))
        continuation?.finish()
        continuation = nil
    }

    func send(_ event: OddsWebSocketEvent) {
        continuation?.yield(event)
    }
}
