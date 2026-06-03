import XCTest
@testable import OddsPulse

@MainActor
final class LiveOddsProviderTests: XCTestCase {
    func testStreamLoadsInitialRecordsAndStartsLiveFeed() async {
        let webSocketClient = FakeLiveOddsWebSocketClient()
        let provider = makeProvider(oddsWebSocketClient: webSocketClient)
        let eventRecorder = EventRecorder()
        let collectionTask = collectEvents(from: provider, into: eventRecorder)

        await waitUntil {
            eventRecorder.events.contains(.feedStatusChanged(.live))
        }
        collectionTask.cancel()

        XCTAssertEqual(eventRecorder.events.first, .loading)
        XCTAssertTrue(eventRecorder.events.contains(.feedStatusChanged(.connecting)))
        XCTAssertTrue(eventRecorder.events.contains(.feedStatusChanged(.live)))
        XCTAssertEqual(webSocketClient.connectedMatchIDs, [1001, 1002])

        guard case let .recordsLoaded(records) = eventRecorder.events.first(where: { event in
            if case .recordsLoaded = event { return true }
            return false
        }) else {
            XCTFail("Expected recordsLoaded event")
            return
        }

        XCTAssertEqual(records.map(\.matchID), [1001, 1002])
    }

    func testNewSubscriberReceivesCachedRecordsWithLatestOdds() async {
        let webSocketClient = FakeLiveOddsWebSocketClient()
        let provider = makeProvider(oddsWebSocketClient: webSocketClient)
        let firstEventRecorder = EventRecorder()
        let firstCollectionTask = collectEvents(from: provider, into: firstEventRecorder)

        await waitUntil {
            firstEventRecorder.events.contains(.feedStatusChanged(.live))
        }
        webSocketClient.send([
            OddsUpdateDTO(matchID: 1001, teamAOdds: 2.45, teamBOdds: 1.65)
        ])
        await waitUntil {
            firstEventRecorder.events.contains { event in
                guard case let .oddsUpdated(changedRecords) = event else { return false }
                return changedRecords.first?.matchID == 1001
            }
        }

        let secondEventRecorder = EventRecorder()
        let secondCollectionTask = collectEvents(from: provider, into: secondEventRecorder)

        await waitUntil {
            secondEventRecorder.events.contains { event in
                guard case .recordsLoaded = event else { return false }
                return true
            }
        }
        firstCollectionTask.cancel()
        secondCollectionTask.cancel()

        guard case let .recordsLoaded(records) = secondEventRecorder.events.first else {
            XCTFail("Expected cached records as first event")
            return
        }

        let restoredRecord = records.first { $0.matchID == 1001 }
        XCTAssertEqual(
            restoredRecord?.oddsState,
            .available(teamAOdds: 2.45, teamBOdds: 1.65)
        )
    }

    func testUnknownOddsUpdateDoesNotEmitOddsUpdated() async {
        let webSocketClient = FakeLiveOddsWebSocketClient()
        let provider = makeProvider(oddsWebSocketClient: webSocketClient)
        let eventRecorder = EventRecorder()
        let collectionTask = collectEvents(from: provider, into: eventRecorder)

        await waitUntil {
            eventRecorder.events.contains(.feedStatusChanged(.live))
        }
        webSocketClient.send([
            OddsUpdateDTO(matchID: 9999, teamAOdds: 1.88, teamBOdds: 2.05)
        ])
        webSocketClient.send([
            OddsUpdateDTO(matchID: 1001, teamAOdds: 2.45, teamBOdds: 1.65)
        ])
        await waitUntil {
            eventRecorder.events.contains { event in
                guard case let .oddsUpdated(changedRecords) = event else {
                    return false
                }

                return changedRecords.map(\.matchID) == [1001]
            }
        }
        collectionTask.cancel()

        let oddsUpdatedEvents = eventRecorder.events.compactMap { event -> [MatchRecord]? in
            guard case let .oddsUpdated(changedRecords) = event else {
                return nil
            }

            return changedRecords
        }

        XCTAssertEqual(oddsUpdatedEvents.count, 1)
        XCTAssertEqual(oddsUpdatedEvents.first?.map(\.matchID), [1001])
    }

    func testStreamCancellationDisconnectsWebSocket() async {
        let webSocketClient = FakeLiveOddsWebSocketClient()
        let provider = makeProvider(oddsWebSocketClient: webSocketClient)
        let eventRecorder = EventRecorder()
        let collectionTask = collectEvents(from: provider, into: eventRecorder)

        await waitUntil {
            eventRecorder.events.contains(.feedStatusChanged(.live))
        }
        collectionTask.cancel()
        await waitUntil {
            webSocketClient.disconnectCallCount == 1
        }

        XCTAssertEqual(webSocketClient.disconnectCallCount, 1)
    }

    func testReconnectStopsAfterMaxAttempts() async {
        let webSocketClient = FakeLiveOddsWebSocketClient(connectBehavior: .finishImmediately)
        let provider = makeProvider(
            oddsWebSocketClient: webSocketClient,
            reconnectPolicy: ReconnectPolicy(
                initialDelayNanoseconds: 0,
                maxDelayNanoseconds: 0,
                jitterRangeNanoseconds: 0,
                maxAttempts: 2
            )
        )
        let eventRecorder = EventRecorder()
        let collectionTask = collectEvents(from: provider, into: eventRecorder)

        await waitUntil {
            eventRecorder.events.contains(.feedStatusChanged(.unavailable(message: "Live odds unavailable")))
        }
        collectionTask.cancel()

        XCTAssertEqual(webSocketClient.connectCallCount, 3)
    }

    private func makeProvider(
        matchesService: MatchesServiceProtocol? = nil,
        oddsService: OddsServiceProtocol? = nil,
        oddsWebSocketClient: OddsWebSocketClientProtocol? = nil,
        reconnectPolicy: ReconnectPolicy = .zeroDelay
    ) -> LiveOddsProvider {
        LiveOddsProvider(
            matchesService: matchesService ?? FakeLiveOddsMatchesService(),
            oddsService: oddsService ?? FakeLiveOddsService(),
            oddsWebSocketClient: oddsWebSocketClient ?? FakeLiveOddsWebSocketClient(),
            reconnectPolicy: reconnectPolicy
        )
    }

    private func collectEvents(
        from provider: LiveOddsProviderProtocol,
        into eventRecorder: EventRecorder
    ) -> Task<Void, Never> {
        Task { @MainActor in
            for await event in provider.stream() {
                eventRecorder.events.append(event)
            }
        }
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))

        while ContinuousClock.now < deadline {
            if condition() {
                return
            }

            await Task.yield()
        }

        XCTFail("Condition was not met before timeout", file: file, line: line)
    }
}

@MainActor
private final class EventRecorder {
    var events: [LiveOddsEvent] = []
}

private extension ReconnectPolicy {
    static let zeroDelay = ReconnectPolicy(
        initialDelayNanoseconds: 0,
        maxDelayNanoseconds: 0,
        jitterRangeNanoseconds: 0,
        maxAttempts: 5
    )
}

private struct FakeLiveOddsMatchesService: MatchesServiceProtocol {
    func fetchMatches() async throws -> [MatchResponseDTO] {
        [
            MatchResponseDTO(
                matchID: 1001,
                teamA: "Eagles",
                teamB: "Tigers",
                startTime: "2025-07-04T13:00:00Z"
            ),
            MatchResponseDTO(
                matchID: 1002,
                teamA: "Hawks",
                teamB: "Lions",
                startTime: "2025-07-04T14:00:00Z"
            )
        ]
    }
}

private struct FakeLiveOddsService: OddsServiceProtocol {
    func fetchInitialOdds() async throws -> [OddsResponseDTO] {
        [
            OddsResponseDTO(matchID: 1001, teamAOdds: 1.95, teamBOdds: 2.10),
            OddsResponseDTO(matchID: 1002, teamAOdds: 2.20, teamBOdds: 1.75)
        ]
    }
}

@MainActor
private final class FakeLiveOddsWebSocketClient: OddsWebSocketClientProtocol {
    enum ConnectBehavior {
        case yieldConnected
        case finishImmediately
    }

    private let connectBehavior: ConnectBehavior
    private var continuations: [AsyncStream<OddsWebSocketEvent>.Continuation] = []

    private(set) var connectedMatchIDs: [Int] = []
    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0

    init(connectBehavior: ConnectBehavior = .yieldConnected) {
        self.connectBehavior = connectBehavior
    }

    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketEvent> {
        connectCallCount += 1
        connectedMatchIDs = matchIDs

        let streamPair = AsyncStream<OddsWebSocketEvent>.makeStream(
            of: OddsWebSocketEvent.self
        )
        continuations.append(streamPair.continuation)

        switch connectBehavior {
        case .yieldConnected:
            streamPair.continuation.yield(.connected)
        case .finishImmediately:
            streamPair.continuation.finish()
        }

        return streamPair.stream
    }

    func disconnect() {
        disconnectCallCount += 1
        continuations.forEach { $0.finish() }
        continuations = []
    }

    func send(_ updates: [OddsUpdateDTO]) {
        continuations.last?.yield(.oddsUpdated(updates))
    }
}
