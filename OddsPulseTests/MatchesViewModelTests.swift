import XCTest
@testable import OddsPulse

@MainActor
final class MatchesViewModelTests: XCTestCase {
    func testStartWhenProviderEmitsLoadingUpdatesState() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var states: [MatchesViewState] = []
        viewModel.onStateChange = { state in
            states.append(state)
        }

        await startObserving(viewModel, provider: provider)
        provider.send(.loading)
        await waitUntil { viewModel.state == .loading }

        XCTAssertEqual(states, [.loading])
        XCTAssertEqual(viewModel.state, .loading)
    }

    func testRecordsLoadedMapsRowsAndEmitsLoadedState() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var states: [MatchesViewState] = []
        viewModel.onStateChange = { state in
            states.append(state)
        }

        await startObserving(viewModel, provider: provider)
        provider.send(.recordsLoaded(Self.makeRecords()))
        await waitUntil {
            if case .loaded = viewModel.state {
                return true
            }

            return false
        }

        guard case let .loaded(rows) = states.last else {
            XCTFail("Expected loaded state")
            return
        }

        XCTAssertEqual(rows.map(\.matchID), [1001, 1002])
        XCTAssertEqual(viewModel.rows, rows)
    }

    func testRefreshFailedEmitsFailedState() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var states: [MatchesViewState] = []
        viewModel.onStateChange = { state in
            states.append(state)
        }

        await startObserving(viewModel, provider: provider)
        provider.send(.refreshFailed(message: "Unable to load matches"))
        await waitUntil {
            viewModel.state == .failed(message: "Unable to load matches")
        }

        XCTAssertEqual(states, [
            .failed(message: "Unable to load matches")
        ])
        XCTAssertEqual(viewModel.state, .failed(message: "Unable to load matches"))
    }

    func testLoadingClearsRowsAndRowIndexMapping() async {
        await assertRowsAndRowIndexMappingCleared(
            by: .loading,
            expectedState: .loading
        )
    }

    func testRefreshFailedWithoutLoadedRecordsKeepsRowsEmptyAndEmitsFailedState() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }

        await startObserving(viewModel, provider: provider)
        provider.send(.refreshFailed(message: "Unable to load matches"))
        await waitUntil {
            viewModel.state == .failed(message: "Unable to load matches")
        }

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertEqual(viewModel.state, .failed(message: "Unable to load matches"))
    }

    func testRefreshFailedAfterRecordsLoadedPreservesRowsAndRowIndexMapping() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var updatedRowIndexes: [Int] = []
        viewModel.onRowIndexesUpdated = { rowIndexes in
            updatedRowIndexes = rowIndexes
        }

        await startObserving(viewModel, provider: provider)
        await loadRecords(in: viewModel, from: provider)
        let rowsBeforeRefreshFailure = viewModel.rows

        provider.send(.refreshFailed(message: "Unable to load matches"))
        await waitUntil {
            viewModel.state == .failed(message: "Unable to load matches")
        }

        XCTAssertEqual(viewModel.rows.count, rowsBeforeRefreshFailure.count)
        XCTAssertEqual(viewModel.rows, rowsBeforeRefreshFailure)
        XCTAssertEqual(viewModel.state, .failed(message: "Unable to load matches"))

        provider.send(.oddsUpdated(changedRecords: [Self.makeKnownOddsUpdateRecord()]))
        await waitUntil { updatedRowIndexes == [1] }

        XCTAssertEqual(updatedRowIndexes, [1])
        XCTAssertEqual(viewModel.rows[0], rowsBeforeRefreshFailure[0])
        XCTAssertEqual(viewModel.rows[1].matchID, 1002)
        XCTAssertEqual(viewModel.rows[1].teamA, "Hawks")
        XCTAssertEqual(viewModel.rows[1].teamB, "Lions")
    }

    func testOddsUpdatedEmitsRowsUpdatedForChangedRecord() async {
        // 準備
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var updatedRowIndexes: [Int] = []
        viewModel.onRowIndexesUpdated = { rowIndexes in
            updatedRowIndexes = rowIndexes
        }

        await startObserving(viewModel, provider: provider)
        await loadRecords(in: viewModel, from: provider)

        // 執行
        provider.send(.oddsUpdated(changedRecords: [Self.makeKnownOddsUpdateRecord()]))
        await waitUntil { updatedRowIndexes == [1] }

        // 驗證
        XCTAssertEqual(updatedRowIndexes, [1])
        XCTAssertEqual(viewModel.rows[1].matchID, 1002)
    }

    func testOddsUpdatedForUnknownRowDoesNotEmitRowsUpdated() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var didUpdateRows = false
        viewModel.onRowIndexesUpdated = { _ in
            didUpdateRows = true
        }

        await startObserving(viewModel, provider: provider)
        await loadRecords(in: viewModel, from: provider)
        provider.send(.oddsUpdated(changedRecords: [Self.makeUnknownOddsUpdateRecord()]))
        await yieldMainActor()

        XCTAssertFalse(didUpdateRows)
    }

    func testFeedStatusChangedUpdatesFeedStatus() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var feedStatuses: [LiveOddsFeedStatus] = []
        viewModel.onFeedStatusChange = { feedStatus in
            feedStatuses.append(feedStatus)
        }

        await startObserving(viewModel, provider: provider)
        provider.send(.feedStatusChanged(.connecting))
        provider.send(.feedStatusChanged(.live))
        provider.send(.feedStatusChanged(.reconnecting))
        await waitUntil {
            feedStatuses == [.connecting, .live, .reconnecting]
        }

        XCTAssertEqual(feedStatuses, [.connecting, .live, .reconnecting])
        XCTAssertEqual(viewModel.feedStatus, .reconnecting)
    }

    func testStopObservingLiveOddsCancelsProviderStream() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)

        await startObserving(viewModel, provider: provider)
        provider.send(.loading)
        await waitUntil { viewModel.state == .loading }

        viewModel.stopObservingLiveOdds()
        await waitUntil { provider.terminationCount == 1 }
        provider.send(.refreshFailed(message: "Should not update stopped view model"))
        await yieldMainActor()

        XCTAssertEqual(viewModel.state, .loading)
    }

    private func startObserving(
        _ viewModel: MatchesViewModel,
        provider: FakeLiveOddsProvider
    ) async {
        viewModel.start()
        await waitUntil { provider.streamCallCount == 1 }
    }

    private func loadRecords(
        in viewModel: MatchesViewModel,
        from provider: FakeLiveOddsProvider
    ) async {
        provider.send(.recordsLoaded(Self.makeRecords()))
        await waitUntil { viewModel.rows.count == 2 }
    }

    private func assertRowsAndRowIndexMappingCleared(
        by event: LiveOddsEvent,
        expectedState: MatchesViewState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var didUpdateRowIndexes = false
        viewModel.onRowIndexesUpdated = { _ in
            didUpdateRowIndexes = true
        }

        await startObserving(viewModel, provider: provider)
        await loadRecords(in: viewModel, from: provider)
        provider.send(event)
        await waitUntil { viewModel.state == expectedState }
        provider.send(.oddsUpdated(changedRecords: [Self.makeKnownOddsUpdateRecord()]))
        await yieldMainActor()

        XCTAssertTrue(viewModel.rows.isEmpty, file: file, line: line)
        XCTAssertFalse(didUpdateRowIndexes, file: file, line: line)
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

    private func yieldMainActor(iterations: Int = 5) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    private static func makeRecords() -> [MatchRecord] {
        [
            MatchRecord(
                matchID: 1001,
                teamA: "Eagles",
                teamB: "Tigers",
                startTime: Date(timeIntervalSince1970: 100),
                oddsState: .available(teamAOdds: 1.95, teamBOdds: 2.10)
            ),
            MatchRecord(
                matchID: 1002,
                teamA: "Hawks",
                teamB: "Lions",
                startTime: Date(timeIntervalSince1970: 200),
                oddsState: .available(teamAOdds: 2.20, teamBOdds: 1.75)
            )
        ]
    }

    private static func makeKnownOddsUpdateRecord() -> MatchRecord {
        MatchRecord(
            matchID: 1002,
            teamA: "Hawks",
            teamB: "Lions",
            startTime: Date(timeIntervalSince1970: 200),
            oddsState: .available(teamAOdds: 1.88, teamBOdds: 2.05)
        )
    }

    private static func makeUnknownOddsUpdateRecord() -> MatchRecord {
        MatchRecord(
            matchID: 9999,
            teamA: "Unknown",
            teamB: "Unknown",
            startTime: Date(timeIntervalSince1970: 300),
            oddsState: .available(teamAOdds: 1.88, teamBOdds: 2.05)
        )
    }
}

@MainActor
private final class FakeLiveOddsProvider: LiveOddsProviderProtocol {
    private var continuation: AsyncStream<LiveOddsEvent>.Continuation?

    private(set) var streamCallCount = 0
    private(set) var terminationCount = 0

    func stream() -> AsyncStream<LiveOddsEvent> {
        streamCallCount += 1

        let streamPair = AsyncStream<LiveOddsEvent>.makeStream(
            of: LiveOddsEvent.self
        )
        continuation = streamPair.continuation
        streamPair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.continuation = nil
                self?.terminationCount += 1
            }
        }
        return streamPair.stream
    }

    func send(_ event: LiveOddsEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
