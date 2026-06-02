import XCTest
@testable import OddsPulse

@MainActor
final class MatchesViewModelTests: XCTestCase {
    func testLoadInitialMatchesWhenServicesSucceedEmitsLoadingThenLoaded() async {
        let webSocketClient = FakeOddsWebSocketClient()
        let viewModel = makeViewModel(oddsWebSocketClient: webSocketClient)
        var states: [MatchesViewState] = []
        viewModel.onStateChange = { state in
            states.append(state)
        }

        await viewModel.loadInitialMatches()

        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states.first, .loading)

        guard case let .loaded(rows) = states.last else {
            XCTFail("Expected loaded state")
            return
        }

        XCTAssertEqual(rows.map(\.matchID), [1001, 1002])
        XCTAssertEqual(rows.first?.teamAOddsText, "1.95")
        XCTAssertEqual(rows.first?.teamBOddsText, "2.10")
        XCTAssertEqual(viewModel.displayRows, rows)
        XCTAssertEqual(webSocketClient.connectedMatchIDs, [1001, 1002])
    }

    func testLoadInitialMatchesWhenMatchesServiceFailsEmitsLoadingThenFailed() async {
        let viewModel = makeViewModel(
            matchesService: FakeMatchesService(fetchResult: .failure)
        )
        var states: [MatchesViewState] = []
        viewModel.onStateChange = { state in
            states.append(state)
        }

        await viewModel.loadInitialMatches()

        XCTAssertEqual(states, [
            .loading,
            .failed(message: "Unable to load matches")
        ])
        XCTAssertEqual(viewModel.state, .failed(message: "Unable to load matches"))
    }

    func testLoadInitialMatchesWhenOddsServiceFailsEmitsLoadingThenFailed() async {
        let viewModel = makeViewModel(
            oddsService: FakeOddsService(fetchResult: .failure)
        )
        var states: [MatchesViewState] = []
        viewModel.onStateChange = { state in
            states.append(state)
        }

        await viewModel.loadInitialMatches()

        XCTAssertEqual(states, [
            .loading,
            .failed(message: "Unable to load matches")
        ])
        XCTAssertEqual(viewModel.state, .failed(message: "Unable to load matches"))
    }

    func testOddsUpdatesWhenKnownMatchUpdatedEmitsRowsUpdatedForCorrectIndex() async {
        let webSocketClient = FakeOddsWebSocketClient()
        let viewModel = makeViewModel(oddsWebSocketClient: webSocketClient)
        let rowsUpdatedExpectation = expectation(description: "Rows updated")
        var updatedRows: [MatchRowViewModel] = []
        var updatedIndexes: [Int] = []
        viewModel.onRowsUpdated = { rows, indexes in
            updatedRows = rows
            updatedIndexes = indexes
            rowsUpdatedExpectation.fulfill()
        }

        await viewModel.loadInitialMatches()
        webSocketClient.send([
            OddsUpdateDTO(matchID: 1002, teamAOdds: 1.88, teamBOdds: 2.05)
        ])

        await fulfillment(of: [rowsUpdatedExpectation], timeout: 1)

        XCTAssertEqual(updatedIndexes, [1])
        XCTAssertEqual(updatedRows[1].matchID, 1002)
        XCTAssertEqual(updatedRows[1].teamAOddsText, "1.88")
        XCTAssertEqual(updatedRows[1].teamBOddsText, "2.05")
    }

    func testLoadInitialMatchesEmitsLiveConnectionStates() async {
        let webSocketClient = FakeOddsWebSocketClient()
        let viewModel = makeViewModel(oddsWebSocketClient: webSocketClient)
        let connectedExpectation = expectation(description: "Live updates connected")
        var liveStates: [LiveConnectionState] = []
        viewModel.onLiveConnectionStateChange = { state in
            liveStates.append(state)
            if state == .connected {
                connectedExpectation.fulfill()
            }
        }

        await viewModel.loadInitialMatches()

        await fulfillment(of: [connectedExpectation], timeout: 1)

        XCTAssertEqual(liveStates, [.connecting, .connected])
    }

    func testOddsUpdatesReconnectsWhenStreamEndsUnexpectedly() async {
        let webSocketClient = FakeOddsWebSocketClient()
        let viewModel = makeViewModel(
            oddsWebSocketClient: webSocketClient,
            reconnectDelayNanoseconds: 0
        )
        let reconnectExpectation = expectation(description: "WebSocket reconnected")
        webSocketClient.onConnect = { connectCallCount in
            if connectCallCount == 2 {
                reconnectExpectation.fulfill()
            }
        }

        await viewModel.loadInitialMatches()
        webSocketClient.finishLatestConnection()

        await fulfillment(of: [reconnectExpectation], timeout: 1)

        let rowsUpdatedExpectation = expectation(description: "Rows updated after reconnect")
        var updatedRows: [MatchRowViewModel] = []
        var updatedIndexes: [Int] = []
        viewModel.onRowsUpdated = { rows, indexes in
            updatedRows = rows
            updatedIndexes = indexes
            rowsUpdatedExpectation.fulfill()
        }

        webSocketClient.send([
            OddsUpdateDTO(matchID: 1001, teamAOdds: 2.45, teamBOdds: 1.65)
        ])

        await fulfillment(of: [rowsUpdatedExpectation], timeout: 1)

        XCTAssertEqual(webSocketClient.connectCallCount, 2)
        XCTAssertEqual(updatedIndexes, [0])
        XCTAssertEqual(updatedRows[0].matchID, 1001)
        XCTAssertEqual(updatedRows[0].teamAOddsText, "2.45")
        XCTAssertEqual(updatedRows[0].teamBOddsText, "1.65")
    }

    func testUnexpectedStreamEndEmitsReconnectingState() async {
        let webSocketClient = FakeOddsWebSocketClient()
        let viewModel = makeViewModel(
            oddsWebSocketClient: webSocketClient,
            reconnectDelayNanoseconds: 0
        )
        let reconnectingExpectation = expectation(description: "Live updates reconnecting")
        var liveStates: [LiveConnectionState] = []
        viewModel.onLiveConnectionStateChange = { state in
            liveStates.append(state)
            if state == .reconnecting {
                reconnectingExpectation.fulfill()
            }
        }

        await viewModel.loadInitialMatches()
        webSocketClient.finishLatestConnection()

        await fulfillment(of: [reconnectingExpectation], timeout: 1)

        XCTAssertTrue(liveStates.contains(.connected))
        XCTAssertTrue(liveStates.contains(.reconnecting))
    }

    func testStopLiveUpdatesDisconnectsWebSocket() async {
        let webSocketClient = FakeOddsWebSocketClient()
        let viewModel = makeViewModel(oddsWebSocketClient: webSocketClient)
        await viewModel.loadInitialMatches()

        viewModel.stopLiveUpdates()

        XCTAssertEqual(webSocketClient.disconnectCallCount, 1)
    }

    func testStopLiveUpdatesPreventsReconnectWhenStreamFinishes() async {
        let webSocketClient = FakeOddsWebSocketClient()
        let viewModel = makeViewModel(
            oddsWebSocketClient: webSocketClient,
            reconnectDelayNanoseconds: 0
        )
        await viewModel.loadInitialMatches()

        viewModel.stopLiveUpdates()
        await Task.yield()

        XCTAssertEqual(webSocketClient.connectCallCount, 1)
        XCTAssertEqual(webSocketClient.disconnectCallCount, 1)
    }

    private func makeViewModel(
        matchesService: MatchesServiceProtocol? = nil,
        oddsService: OddsServiceProtocol? = nil,
        oddsWebSocketClient: OddsWebSocketClientProtocol? = nil,
        reconnectDelayNanoseconds: UInt64 = 0
    ) -> MatchesViewModel {
        MatchesViewModel(
            matchesService: matchesService ?? FakeMatchesService(),
            oddsService: oddsService ?? FakeOddsService(),
            oddsWebSocketClient: oddsWebSocketClient ?? FakeOddsWebSocketClient(),
            reconnectDelayNanoseconds: reconnectDelayNanoseconds
        )
    }
}

private struct FakeMatchesService: MatchesServiceProtocol {
    let fetchResult: FetchResult<[MatchResponseDTO]>

    init(fetchResult: FetchResult<[MatchResponseDTO]>? = nil) {
        self.fetchResult = fetchResult ?? .success([
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
        ])
    }

    func fetchMatches() async throws -> [MatchResponseDTO] {
        try fetchResult.value()
    }
}

private struct FakeOddsService: OddsServiceProtocol {
    let fetchResult: FetchResult<[OddsResponseDTO]>

    init(fetchResult: FetchResult<[OddsResponseDTO]>? = nil) {
        self.fetchResult = fetchResult ?? .success([
            OddsResponseDTO(matchID: 1001, teamAOdds: 1.95, teamBOdds: 2.10),
            OddsResponseDTO(matchID: 1002, teamAOdds: 2.20, teamBOdds: 1.75)
        ])
    }

    func fetchInitialOdds() async throws -> [OddsResponseDTO] {
        try fetchResult.value()
    }
}

@MainActor
private final class FakeOddsWebSocketClient: OddsWebSocketClientProtocol {
    private var continuations: [AsyncStream<OddsWebSocketEvent>.Continuation] = []

    var onConnect: ((Int) -> Void)?
    private(set) var connectedMatchIDs: [Int] = []
    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0

    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketEvent> {
        connectCallCount += 1
        connectedMatchIDs = matchIDs

        let streamPair = AsyncStream<OddsWebSocketEvent>.makeStream(
            of: OddsWebSocketEvent.self
        )
        continuations.append(streamPair.continuation)
        streamPair.continuation.yield(.connected)
        onConnect?(connectCallCount)
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

    func finishLatestConnection() {
        continuations.last?.finish()
    }
}

private enum FetchResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure

    func value() throws -> Value {
        switch self {
        case let .success(value):
            return value
        case .failure:
            throw FakeServiceError.fetchFailed
        }
    }
}

private enum FakeServiceError: Error {
    case fetchFailed
}
