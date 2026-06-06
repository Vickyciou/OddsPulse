import XCTest
@testable import OddsPulse

@MainActor
final class LiveOddsProviderTests: XCTestCase {
    func testFirstSubscriberReceivesLoadingRefreshAndLiveConnectionEvents() async throws {
        // 準備
        let recordsRepository = FakeRecordsRepository(records: [
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002)
        ])
        let store = FakeOddsStore()
        let webSocketService = ControllableOddsWebSocketService()
        let provider = makeProvider(
            recordsRepository: recordsRepository,
            webSocketService: webSocketService,
            store: store
        )
        let eventCollector = LiveOddsEventCollector(stream: provider.stream())

        // 執行
        let initialEvents = try await eventCollector.collectNextEvents(count: 3, in: self)
        webSocketService.send(.connected)
        let liveEvents = try await eventCollector.collectNextEvents(count: 1, in: self)
        let recordsFetchCount = await recordsRepository.fetchCallCount()

        // 驗證
        guard case let .recordsLoaded(loadedRecords) = initialEvents[1] else {
            return XCTFail("Expected recordsLoaded event")
        }

        XCTAssertEqual(initialEvents[0], .loading)
        XCTAssertEqual(loadedRecords.map(\.matchID), [1001, 1002])
        XCTAssertEqual(initialEvents[2], .feedStatusChanged(.connecting))
        XCTAssertEqual(liveEvents, [.feedStatusChanged(.live)])
        XCTAssertEqual(recordsFetchCount, 1)
        XCTAssertEqual(webSocketService.connectCallCount, 1)
        XCTAssertEqual(webSocketService.connectedMatchIDsHistory, [[1001, 1002]])
        XCTAssertEqual(store.replaceRecordsCallCount, 1)
        XCTAssertEqual(store.lastReplacedRecords.map(\.matchID), [1001, 1002])
    }

    func testRefreshFailureDoesNotConnectWebSocket() async throws {
        // 準備
        let recordsRepository = FakeRecordsRepository(result: .failure(TestError.expected))
        let webSocketService = ControllableOddsWebSocketService()
        let provider = makeProvider(
            recordsRepository: recordsRepository,
            webSocketService: webSocketService
        )

        // 執行
        let events = try await collectEvents(from: provider.stream(), count: 2)

        // 驗證
        XCTAssertEqual(events, [
            .loading,
            .refreshFailed(message: "Unable to load matches")
        ])
        XCTAssertEqual(webSocketService.connectCallCount, 0)
    }

    func testCachedSnapshotSubscriberReceivesSnapshotThenRefreshesRecords() async throws {
        // 準備
        let store = FakeOddsStore()
        store.snapshotOverride = [
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002)
        ]
        let recordsRepository = FakeRecordsRepository(records: [
            makeRecord(matchID: 9999)
        ])
        let webSocketService = ControllableOddsWebSocketService()
        let provider = makeProvider(
            recordsRepository: recordsRepository,
            webSocketService: webSocketService,
            store: store
        )

        // 執行
        let events = try await collectEvents(from: provider.stream(), count: 3)

        // 驗證
        guard case let .recordsLoaded(snapshotRecords) = events[0] else {
            return XCTFail("Expected cached recordsLoaded event")
        }

        guard case let .recordsLoaded(refreshedRecords) = events[2] else {
            return XCTFail("Expected refreshed recordsLoaded event")
        }

        XCTAssertEqual(snapshotRecords.map(\.matchID), [1001, 1002])
        XCTAssertEqual(events[1], .feedStatusChanged(.connecting))
        XCTAssertEqual(refreshedRecords.map(\.matchID), [9999])
        XCTAssertEqual(webSocketService.connectedMatchIDsHistory, [[1001, 1002]])
    }

    func testMultipleSubscribersShareSingleRefreshAndWebSocketConnection() async throws {
        // 準備
        let recordsRepository = SuspendedRecordsRepository(records: [
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002)
        ])
        let webSocketService = ControllableOddsWebSocketService()
        let provider = makeProvider(
            recordsRepository: recordsRepository,
            webSocketService: webSocketService
        )
        let firstCollector = LiveOddsEventCollector(stream: provider.stream())
        let secondCollector = LiveOddsEventCollector(stream: provider.stream())

        // 執行
        let firstInitialEvents = try await firstCollector.collectNextEvents(count: 1, in: self)
        let secondInitialEvents = try await secondCollector.collectNextEvents(count: 1, in: self)
        await recordsRepository.release()
        let firstRefreshEvents = try await firstCollector.collectNextEvents(count: 2, in: self)
        let secondRefreshEvents = try await secondCollector.collectNextEvents(count: 2, in: self)
        let recordsFetchCount = await recordsRepository.fetchCallCount()

        // 驗證
        XCTAssertEqual(firstInitialEvents, [.loading])
        XCTAssertEqual(secondInitialEvents, [.loading])
        assertLoadedRecordsAndConnectingEvent(firstRefreshEvents, expectedMatchIDs: [1001, 1002])
        assertLoadedRecordsAndConnectingEvent(secondRefreshEvents, expectedMatchIDs: [1001, 1002])
        XCTAssertEqual(recordsFetchCount, 1)
        XCTAssertEqual(webSocketService.connectCallCount, 1)
        XCTAssertEqual(webSocketService.connectedMatchIDsHistory, [[1001, 1002]])
    }

    func testOddsUpdateBroadcastsOnlyChangedKnownRecords() async throws {
        // 準備
        let provider = makeProviderWithLoadedRecords(matchIDs: [1001, 1002])
        let eventCollector = LiveOddsEventCollector(stream: provider.provider.stream())
        _ = try await eventCollector.collectNextEvents(count: 3, in: self)

        // 執行
        provider.webSocketService.send(.oddsUpdated([
            OddsUpdate(matchID: 1002, teamAOdds: 1.88, teamBOdds: 2.05),
            OddsUpdate(matchID: 9999, teamAOdds: 4.00, teamBOdds: 5.00)
        ]))
        let events = try await eventCollector.collectNextEvents(count: 1, in: self)

        // 驗證
        guard let event = events.first,
              case let .oddsUpdated(changedRecords) = event else {
            return XCTFail("Expected oddsUpdated event")
        }

        XCTAssertEqual(changedRecords.map(\.matchID), [1002])
        XCTAssertEqual(
            changedRecords.first?.oddsState,
            .available(teamAOdds: 1.88, teamBOdds: 2.05)
        )
        XCTAssertEqual(provider.store.applyOddsUpdatesCallCount, 1)
        XCTAssertEqual(provider.store.lastAppliedUpdates.map(\.matchID), [1002, 9999])
    }

    func testManualDisconnectStopsWithoutReconnectOrUnavailableEvent() async throws {
        // 準備
        let provider = makeProviderWithLoadedRecords(matchIDs: [1001])
        let eventCollector = LiveOddsEventCollector(stream: provider.provider.stream())
        _ = try await eventCollector.collectNextEvents(count: 3, in: self)

        // 執行
        provider.webSocketService.send(.disconnected(reason: .manual))

        // 驗證
        await eventCollector.assertNoEvent(in: self)
        XCTAssertEqual(provider.webSocketService.connectCallCount, 1)
    }

    func testStreamEndedDisconnectDoesNotReconnectBecauseWebSocketServiceOwnsReconnect() async throws {
        // 準備
        let provider = makeProviderWithLoadedRecords(matchIDs: [1001])
        let eventCollector = LiveOddsEventCollector(stream: provider.provider.stream())
        _ = try await eventCollector.collectNextEvents(count: 3, in: self)

        // 執行
        provider.webSocketService.send(.disconnected(reason: .streamEnded))
        await yieldMainActor()

        // 驗證
        XCTAssertEqual(provider.webSocketService.connectCallCount, 1)
    }

    func testNoMatchIDsDisconnectBroadcastsUnavailableAndDoesNotReconnect() async throws {
        // 準備
        let provider = makeProviderWithLoadedRecords(matchIDs: [1001])
        let eventCollector = LiveOddsEventCollector(stream: provider.provider.stream())
        _ = try await eventCollector.collectNextEvents(count: 3, in: self)

        // 執行
        provider.webSocketService.send(.disconnected(reason: .noMatchIDs))
        let events = try await eventCollector.collectNextEvents(count: 1, in: self)

        // 驗證
        let unavailableEvent = try XCTUnwrap(events.first)
        XCTAssertEqual(
            unavailableEvent,
            .feedStatusChanged(.unavailable(message: "No matches available for live odds"))
        )
        XCTAssertEqual(provider.webSocketService.connectCallCount, 1)
    }

    func testFailedWebSocketEventBroadcastsUnavailableAndStops() async throws {
        // 準備
        let provider = makeProviderWithLoadedRecords(matchIDs: [1001])
        let eventCollector = LiveOddsEventCollector(stream: provider.provider.stream())
        _ = try await eventCollector.collectNextEvents(count: 3, in: self)

        // 執行
        provider.webSocketService.send(.failed(.connectionFailed))
        let events = try await eventCollector.collectNextEvents(count: 1, in: self)

        // 驗證
        let unavailableEvent = try XCTUnwrap(events.first)
        XCTAssertEqual(
            unavailableEvent,
            .feedStatusChanged(.unavailable(message: "Live odds unavailable"))
        )
        XCTAssertEqual(provider.webSocketService.connectCallCount, 1)
    }

    func testReconnectingEventBroadcastsReconnectingFeedStatus() async throws {
        // 準備
        let provider = makeProviderWithLoadedRecords(matchIDs: [1001])
        let eventCollector = LiveOddsEventCollector(stream: provider.provider.stream())
        _ = try await eventCollector.collectNextEvents(count: 3, in: self)

        // 執行
        provider.webSocketService.send(.reconnecting)
        let events = try await eventCollector.collectNextEvents(count: 1, in: self)

        // 驗證
        XCTAssertEqual(events, [.feedStatusChanged(.reconnecting)])
        XCTAssertEqual(provider.webSocketService.connectCallCount, 1)
    }

    func testCancelingLastSubscriberDisconnectsWebSocket() async throws {
        // 準備
        let provider = makeProviderWithLoadedRecords(matchIDs: [1001])
        let task = Task { @MainActor in
            let eventCollector = LiveOddsEventCollector(stream: provider.provider.stream())
            while !Task.isCancelled {
                _ = eventCollector
                await Task.yield()
            }
        }
        await Task.yield()

        // 執行
        task.cancel()
        await task.value
        await Task.yield()

        // 驗證
        XCTAssertEqual(provider.webSocketService.disconnectCallCount, 1)
    }

    func testSecondSubscriberAfterOddsUpdateReceivesUpdatedSnapshotThenRefreshedRecords() async throws {
        // 準備
        let provider = makeProviderWithLoadedRecords(matchIDs: [1001])
        let firstCollector = LiveOddsEventCollector(stream: provider.provider.stream())
        _ = try await firstCollector.collectNextEvents(count: 3, in: self)

        // 傳送賠率更新
        provider.webSocketService.send(.oddsUpdated([
            OddsUpdate(matchID: 1001, teamAOdds: 1.88, teamBOdds: 2.05)
        ]))
        _ = try await firstCollector.collectNextEvents(count: 1, in: self)

        // 新 subscriber 加入：snapshot + re-fetch 共兩個 events
        let secondCollector = LiveOddsEventCollector(stream: provider.provider.stream())
        let secondEvents = try await secondCollector.collectNextEvents(count: 2, in: self)

        // 第一個 event 是 snapshot，應包含 WebSocket 更新後的賠率
        guard case let .recordsLoaded(snapshotRecords) = secondEvents[0] else {
            return XCTFail("Expected snapshot recordsLoaded for late subscriber")
        }
        XCTAssertEqual(snapshotRecords.count, 1)
        XCTAssertEqual(
            snapshotRecords.first?.oddsState,
            .available(teamAOdds: 1.88, teamBOdds: 2.05)
        )

        // 第二個 event 是 re-fetch 結果（API 原始賠率 1.50），覆蓋了 store
        guard case let .recordsLoaded(refreshedRecords) = secondEvents[1] else {
            return XCTFail("Expected refreshed recordsLoaded event")
        }
        XCTAssertEqual(
            refreshedRecords.first?.oddsState,
            .available(teamAOdds: 1.50, teamBOdds: 2.50)
        )

        // Store 被呼叫兩次 snapshot：first subscriber（empty）+ late subscriber
        XCTAssertEqual(provider.store.snapshotCallCount, 2)
    }

}

private extension LiveOddsProviderTests {
    struct LoadedProvider {
        let provider: LiveOddsProvider
        let webSocketService: ControllableOddsWebSocketService
        let store: FakeOddsStore
    }

    enum TestError: Error {
        case expected
    }

    func makeProvider(
        recordsRepository: RecordsRepositoryProtocol? = nil,
        webSocketService: ControllableOddsWebSocketService? = nil,
        store: OddsStoreProtocol = FakeOddsStore()
    ) -> LiveOddsProvider {
        let webSocketService = webSocketService ?? ControllableOddsWebSocketService()
        return LiveOddsProvider(
            recordsRepository: recordsRepository ?? FakeRecordsRepository(records: [
                makeRecord(matchID: 1001)
            ]),
            oddsWebSocketService: webSocketService,
            oddsStore: store
        )
    }

    func makeProviderWithLoadedRecords(matchIDs: [Int]) -> LoadedProvider {
        let store = FakeOddsStore()
        let webSocketService = ControllableOddsWebSocketService()
        let provider = makeProvider(
            recordsRepository: FakeRecordsRepository(
                records: matchIDs.map { makeRecord(matchID: $0, oddsState: .available(teamAOdds: 1.50, teamBOdds: 2.50)) }
            ),
            webSocketService: webSocketService,
            store: store
        )
        return LoadedProvider(provider: provider, webSocketService: webSocketService, store: store)
    }

    func collectEvents(
        from stream: AsyncStream<LiveOddsEvent>,
        count: Int,
        timeout: TimeInterval = 1
    ) async throws -> [LiveOddsEvent] {
        let eventCollector = LiveOddsEventCollector(stream: stream)
        return try await eventCollector.collectNextEvents(
            count: count,
            in: self,
            timeout: timeout
        )
    }

    func assertLoadedRecordsAndConnectingEvent(
        _ events: [LiveOddsEvent],
        expectedMatchIDs: [Int],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard events.count == 2 else {
            return XCTFail("Expected recordsLoaded and connecting events", file: file, line: line)
        }

        guard case let .recordsLoaded(records) = events[0] else {
            return XCTFail("Expected recordsLoaded event", file: file, line: line)
        }

        XCTAssertEqual(records.map(\.matchID), expectedMatchIDs, file: file, line: line)
        XCTAssertEqual(events[1], .feedStatusChanged(.connecting), file: file, line: line)
    }

    func waitForConnectCallCount(
        _ expectedConnectCallCount: Int,
        in webSocketService: ControllableOddsWebSocketService
    ) async throws {
        for _ in 0..<10 {
            if webSocketService.connectCallCount == expectedConnectCallCount {
                return
            }

            await Task.yield()
        }

        throw EventCollectionError.missingEvents
    }

    func yieldMainActor(iterations: Int = 5) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    func makeRecord(
        matchID: Int,
        oddsState: OddsState = .unavailable
    ) -> MatchRecord {
        MatchRecord(
            matchID: matchID,
            teamA: "Eagles",
            teamB: "Tigers",
            startTime: Date(timeIntervalSince1970: TimeInterval(matchID)),
            oddsState: oddsState
        )
    }
}

private extension ReconnectPolicy {
    static let test = ReconnectPolicy(
        initialDelayNanoseconds: 0,
        maxDelayNanoseconds: 0,
        jitterRangeNanoseconds: 0,
        maxAttempts: 0
    )
}

private enum EventCollectionError: Error {
    case missingEvents
}

@MainActor
private final class LiveOddsEventCollector {
    private var pendingEvents: [LiveOddsEvent] = []
    private var pendingExpectations: [EventExpectation] = []
    private var collectionTask: Task<Void, Never>?

    init(stream: AsyncStream<LiveOddsEvent>) {
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
    ) async throws -> [LiveOddsEvent] {
        guard count > 0 else { return [] }

        let expectation = testCase.expectation(
            description: "Collect next \(count) LiveOddsEvent values"
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
        let expectation = testCase.expectation(description: "No LiveOddsEvent")
        expectation.isInverted = true
        pendingExpectations.append(EventExpectation(targetCount: 1, expectation: expectation))
        fulfillReadyExpectations()

        await testCase.fulfillment(of: [expectation], timeout: timeout)
    }

    private func record(_ event: LiveOddsEvent) {
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

private actor FakeRecordsRepository: RecordsRepositoryProtocol {
    private let result: Result<[MatchRecord], Error>
    private(set) var fetchCount = 0

    init(records: [MatchRecord]) {
        result = .success(records)
    }

    init(result: Result<[MatchRecord], Error>) {
        self.result = result
    }

    func fetchRecords() async throws -> [MatchRecord] {
        fetchCount += 1
        return try result.get()
    }

    func fetchCallCount() -> Int {
        fetchCount
    }
}

private actor SuspendedRecordsRepository: RecordsRepositoryProtocol {
    private let records: [MatchRecord]
    private var fetchCount = 0
    private var isReleased = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(records: [MatchRecord]) {
        self.records = records
    }

    func fetchRecords() async throws -> [MatchRecord] {
        fetchCount += 1

        if !isReleased {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }

        return records
    }

    func release() {
        isReleased = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }

    func fetchCallCount() -> Int {
        fetchCount
    }
}

@MainActor
private final class ControllableOddsWebSocketService: OddsWebSocketServiceProtocol {
    private var continuation: AsyncStream<OddsWebSocketServiceEvent>.Continuation?

    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var connectedMatchIDsHistory: [[Int]] = []

    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketServiceEvent> {
        connectCallCount += 1
        connectedMatchIDsHistory.append(matchIDs)

        let streamPair = AsyncStream<OddsWebSocketServiceEvent>.makeStream(
            of: OddsWebSocketServiceEvent.self,
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

    func send(_ event: OddsWebSocketServiceEvent) {
        continuation?.yield(event)
        switch event {
        case .disconnected, .failed:
            continuation?.finish()
        case .connected, .reconnecting, .oddsUpdated:
            break
        }
    }
}

private final class FakeOddsStore: OddsStoreProtocol {
    private var records: [MatchRecord] = []
    private var indexByMatchID: [Int: Int] = [:]

    var snapshotOverride: [MatchRecord]?

    private(set) var replaceRecordsCallCount = 0
    private(set) var lastReplacedRecords: [MatchRecord] = []
    private(set) var snapshotCallCount = 0
    private(set) var applyOddsUpdatesCallCount = 0
    private(set) var lastAppliedUpdates: [OddsUpdate] = []

    func replaceRecords(_ records: [MatchRecord]) async {
        replaceRecordsCallCount += 1
        lastReplacedRecords = records
        self.records = records
        indexByMatchID = Dictionary(
            uniqueKeysWithValues: records.enumerated().map { ($1.matchID, $0) }
        )
    }

    func snapshot() async -> [MatchRecord] {
        snapshotCallCount += 1
        if let override = snapshotOverride {
            return override
        }
        return records
    }

    func applyOddsUpdates(_ updates: [OddsUpdate]) async -> UpdateResult {
        applyOddsUpdatesCallCount += 1
        lastAppliedUpdates = updates

        var changedRecords: [MatchRecord] = []
        var unknownMatchIDs: [Int] = []

        for update in updates {
            guard let index = indexByMatchID[update.matchID] else {
                unknownMatchIDs.append(update.matchID)
                continue
            }
            records[index].oddsState = .available(
                teamAOdds: update.teamAOdds,
                teamBOdds: update.teamBOdds
            )
            changedRecords.append(records[index])
        }

        return UpdateResult(
            changedRecords: changedRecords,
            unknownMatchIDs: unknownMatchIDs
        )
    }
}
