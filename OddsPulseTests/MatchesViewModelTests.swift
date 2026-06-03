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

        viewModel.start()
        await waitUntil { provider.streamCallCount == 1 }
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

        viewModel.start()
        await waitUntil { provider.streamCallCount == 1 }
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
        XCTAssertEqual(rows.first?.teamAOddsText, "1.95")
        XCTAssertEqual(rows.first?.teamBOddsText, "2.10")
        XCTAssertEqual(viewModel.displayRows, rows)
    }

    func testInitialLoadFailedEmitsFailedState() async {
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

        viewModel.start()
        await waitUntil { provider.streamCallCount == 1 }
        provider.send(.initialLoadFailed(message: "Unable to load matches"))
        await waitUntil {
            viewModel.state == .failed(message: "Unable to load matches")
        }

        XCTAssertEqual(states, [
            .failed(message: "Unable to load matches")
        ])
        XCTAssertEqual(viewModel.state, .failed(message: "Unable to load matches"))
    }

    func testOddsUpdatedEmitsRowsUpdatedForChangedRecord() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var updatedRows: [MatchRowViewModel] = []
        var updatedIndexes: [Int] = []
        viewModel.onRowsUpdated = { rows, indexes in
            updatedRows = rows
            updatedIndexes = indexes
        }

        viewModel.start()
        await waitUntil { provider.streamCallCount == 1 }
        provider.send(.recordsLoaded(Self.makeRecords()))
        await waitUntil { viewModel.displayRows.count == 2 }
        provider.send(.oddsUpdated(changedRecords: [
            MatchRecord(
                matchID: 1002,
                teamA: "Hawks",
                teamB: "Lions",
                startTime: Date(timeIntervalSince1970: 200),
                oddsState: .available(teamAOdds: 1.88, teamBOdds: 2.05)
            )
        ]))
        await waitUntil { updatedIndexes == [1] }

        XCTAssertEqual(updatedIndexes, [1])
        XCTAssertEqual(updatedRows[1].matchID, 1002)
        XCTAssertEqual(updatedRows[1].teamAOddsText, "1.88")
        XCTAssertEqual(updatedRows[1].teamBOddsText, "2.05")
    }

    func testOddsUpdatedForUnknownRowDoesNotEmitRowsUpdated() async {
        let provider = FakeLiveOddsProvider()
        let viewModel = MatchesViewModel(liveOddsProvider: provider)
        defer {
            viewModel.stopObservingLiveOdds()
            provider.finish()
        }
        var didUpdateRows = false
        viewModel.onRowsUpdated = { _, _ in
            didUpdateRows = true
        }

        viewModel.start()
        await waitUntil { provider.streamCallCount == 1 }
        provider.send(.recordsLoaded(Self.makeRecords()))
        await waitUntil { viewModel.displayRows.count == 2 }
        provider.send(.oddsUpdated(changedRecords: [
            MatchRecord(
                matchID: 9999,
                teamA: "Unknown",
                teamB: "Unknown",
                startTime: Date(timeIntervalSince1970: 300),
                oddsState: .available(teamAOdds: 1.88, teamBOdds: 2.05)
            )
        ]))
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

        viewModel.start()
        await waitUntil { provider.streamCallCount == 1 }
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

        viewModel.start()
        await waitUntil { provider.streamCallCount == 1 }
        provider.send(.loading)
        await waitUntil { viewModel.state == .loading }

        viewModel.stopObservingLiveOdds()
        await waitUntil { provider.terminationCount == 1 }
        provider.send(.initialLoadFailed(message: "Should not update stopped view model"))
        await yieldMainActor()

        XCTAssertEqual(viewModel.state, .loading)
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
