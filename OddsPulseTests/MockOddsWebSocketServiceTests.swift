import XCTest
@testable import OddsPulse

@MainActor
final class MockOddsWebSocketServiceTests: XCTestCase {
    func testConnectDelegatesMatchIDsToClientAndReturnsEvents() async throws {
        let client = ControllableOddsWebSocketClient()
        let service = MockOddsWebSocketService(webSocketClient: client)

        let stream = service.connect(matchIDs: [1001, 1002])
        try await waitForConnectCallCount(1, in: client)
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

    func testOddsUpdatedMapsClientDTOsToDomainUpdates() async throws {
        let client = ControllableOddsWebSocketClient()
        let service = MockOddsWebSocketService(webSocketClient: client)
        let eventCollector = OddsWebSocketEventCollector(stream: service.connect(matchIDs: [1001]))

        try await waitForConnectCallCount(1, in: client)
        client.send(.oddsUpdated([
            OddsUpdateDTO(matchID: 1001, teamAOdds: 1.88, teamBOdds: 2.05)
        ]))

        let events = try await eventCollector.collectNextEvents(count: 1, in: self)

        XCTAssertEqual(events, [
            .oddsUpdated([
                OddsUpdate(matchID: 1001, teamAOdds: 1.88, teamBOdds: 2.05)
            ])
        ])
    }

    func testStreamEndedReconnectsUntilPolicyIsExhausted() async throws {
        let client = ControllableOddsWebSocketClient()
        let service = MockOddsWebSocketService(
            webSocketClient: client,
            reconnectPolicy: ReconnectPolicy(
                initialDelayNanoseconds: 0,
                maxDelayNanoseconds: 0,
                jitterRangeNanoseconds: 0,
                maxAttempts: 2
            )
        )
        let eventCollector = OddsWebSocketEventCollector(stream: service.connect(matchIDs: [1001]))

        try await waitForConnectCallCount(1, in: client)
        client.send(.connected)
        client.send(.disconnected(reason: .streamEnded))
        try await waitForConnectCallCount(2, in: client)
        client.send(.connected)
        client.send(.disconnected(reason: .streamEnded))
        try await waitForConnectCallCount(3, in: client)
        client.send(.connected)
        client.send(.disconnected(reason: .streamEnded))

        let events = try await eventCollector.collectNextEvents(count: 8, in: self)

        XCTAssertEqual(events, [
            .connected,
            .disconnected(reason: .streamEnded),
            .reconnecting,
            .connected,
            .disconnected(reason: .streamEnded),
            .reconnecting,
            .connected,
            .disconnected(reason: .streamEnded)
        ])
        XCTAssertEqual(client.connectCallCount, 3)

        let finalEvent = try await eventCollector.collectNextEvents(count: 1, in: self)
        XCTAssertEqual(finalEvent, [.failed(.connectionFailed)])
    }

    func testManualDisconnectDoesNotReconnect() async throws {
        let client = ControllableOddsWebSocketClient()
        let service = MockOddsWebSocketService(
            webSocketClient: client,
            reconnectPolicy: ReconnectPolicy(
                initialDelayNanoseconds: 0,
                maxDelayNanoseconds: 0,
                jitterRangeNanoseconds: 0,
                maxAttempts: 2
            )
        )
        let eventCollector = OddsWebSocketEventCollector(stream: service.connect(matchIDs: [1001]))

        try await waitForConnectCallCount(1, in: client)
        client.send(.connected)
        client.send(.disconnected(reason: .manual))
        let events = try await eventCollector.collectNextEvents(count: 2, in: self)

        XCTAssertEqual(events, [
            .connected,
            .disconnected(reason: .manual)
        ])
        XCTAssertEqual(client.connectCallCount, 1)
        await eventCollector.assertNoEvent(in: self)
    }

    func testReconnectPolicyDelayIsAppliedBeforeReconnectEvent() async throws {
        let client = ControllableOddsWebSocketClient()
        let service = MockOddsWebSocketService(
            webSocketClient: client,
            reconnectPolicy: ReconnectPolicy(
                initialDelayNanoseconds: 50_000_000,
                maxDelayNanoseconds: 50_000_000,
                jitterRangeNanoseconds: 0,
                maxAttempts: 1
            )
        )
        let eventCollector = OddsWebSocketEventCollector(stream: service.connect(matchIDs: [1001]))

        try await waitForConnectCallCount(1, in: client)
        client.send(.connected)
        client.send(.disconnected(reason: .streamEnded))
        let initialEvents = try await eventCollector.collectNextEvents(count: 2, in: self)

        XCTAssertEqual(initialEvents, [
            .connected,
            .disconnected(reason: .streamEnded)
        ])
        await eventCollector.assertNoEvent(in: self, timeout: 0.01)
        let reconnectEvent = try await eventCollector.collectNextEvents(count: 1, in: self)
        XCTAssertEqual(reconnectEvent, [.reconnecting])
    }

    private func collectFirstEvent(
        from stream: AsyncStream<OddsWebSocketServiceEvent>,
        timeout: TimeInterval = 1
    ) async throws -> OddsWebSocketServiceEvent {
        let expectation = expectation(description: "Collect first OddsWebSocketEvent")
        var iterator = stream.makeAsyncIterator()
        var collectedEvent: OddsWebSocketServiceEvent?

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
    private var continuations: [AsyncStream<OddsWebSocketEvent>.Continuation] = []

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
        continuations.append(streamPair.continuation)
        return streamPair.stream
    }

    func disconnect() {
        disconnectCallCount += 1
        continuations.last?.yield(.disconnected(reason: .manual))
        continuations.last?.finish()
        continuations.removeAll()
    }

    func send(_ event: OddsWebSocketEvent) {
        continuations.last?.yield(event)
        switch event {
        case .disconnected, .failed:
            continuations.last?.finish()
        case .connected, .reconnecting, .oddsUpdated:
            break
        }
    }
}

@MainActor
private final class OddsWebSocketEventCollector {
    private var pendingEvents: [OddsWebSocketServiceEvent] = []
    private var pendingExpectations: [EventExpectation] = []
    private var collectionTask: Task<Void, Never>?

    init(stream: AsyncStream<OddsWebSocketServiceEvent>) {
        collectionTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.record(event)
            }
        }
    }

    deinit {
        collectionTask?.cancel()
    }

    func collectNextEvents(
        count: Int,
        in testCase: XCTestCase,
        timeout: TimeInterval = 1
    ) async throws -> [OddsWebSocketServiceEvent] {
        let expectation = testCase.expectation(
            description: "Collect next \(count) OddsWebSocketEvent values"
        )
        pendingExpectations.append(EventExpectation(targetCount: count, expectation: expectation))
        fulfillReadyExpectations()

        await testCase.fulfillment(of: [expectation], timeout: timeout)
        guard pendingEvents.count >= count else {
            throw EventCollectionError.missingEvents
        }

        let collectedEvents = Array(pendingEvents.prefix(count))
        pendingEvents.removeFirst(count)
        return collectedEvents
    }

    func assertNoEvent(
        in testCase: XCTestCase,
        timeout: TimeInterval = 0.05
    ) async {
        let expectation = testCase.expectation(description: "No OddsWebSocketEvent")
        expectation.isInverted = true
        pendingExpectations.append(EventExpectation(targetCount: 1, expectation: expectation))
        fulfillReadyExpectations()

        await testCase.fulfillment(of: [expectation], timeout: timeout)
    }

    private func record(_ event: OddsWebSocketServiceEvent) {
        pendingEvents.append(event)
        fulfillReadyExpectations()
    }

    private func fulfillReadyExpectations() {
        let readyExpectations = pendingExpectations.filter { pendingEvents.count >= $0.targetCount }
        pendingExpectations.removeAll { pendingEvents.count >= $0.targetCount }
        readyExpectations.forEach { $0.expectation.fulfill() }
    }
}

private struct EventExpectation {
    let targetCount: Int
    let expectation: XCTestExpectation
}

private enum EventCollectionError: Error {
    case missingEvents
}

@MainActor
private func waitForConnectCallCount(
    _ expectedConnectCallCount: Int,
    in client: ControllableOddsWebSocketClient
) async throws {
    for _ in 0..<10 {
        if client.connectCallCount == expectedConnectCallCount {
            return
        }

        await Task.yield()
    }

    throw EventCollectionError.missingEvents
}
