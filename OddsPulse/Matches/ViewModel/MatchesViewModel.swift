import Foundation

@MainActor
final class MatchesViewModel {
    var onStateChange: ((MatchesViewState) -> Void)?
    var onRowsUpdated: (([MatchRowViewModel], [Int]) -> Void)?
    var onLiveConnectionStateChange: ((LiveConnectionState) -> Void)?

    private(set) var state: MatchesViewState = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    private(set) var displayRows: [MatchRowViewModel] = []
    private(set) var liveConnectionState: LiveConnectionState = .idle {
        didSet {
            onLiveConnectionStateChange?(liveConnectionState)
        }
    }

    private let matchesService: MatchesServiceProtocol
    private let oddsService: OddsServiceProtocol
    private let oddsWebSocketClient: OddsWebSocketClientProtocol
    private let oddsStore: OddsStore
    private let rowMapper: MatchRowViewModelMapper
    private let reconnectDelayNanoseconds: UInt64
    private var rowIndexByMatchID: [Int: Int] = [:]
    private var oddsUpdateTask: Task<Void, Never>?
    private var isLiveUpdatesStopped = true

    init(
        matchesService: MatchesServiceProtocol? = nil,
        oddsService: OddsServiceProtocol? = nil,
        oddsWebSocketClient: OddsWebSocketClientProtocol? = nil,
        oddsStore: OddsStore = OddsStore(),
        rowMapper: MatchRowViewModelMapper? = nil,
        reconnectDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.matchesService = matchesService ?? MockMatchesService()
        self.oddsService = oddsService ?? MockOddsService()
        self.oddsWebSocketClient = oddsWebSocketClient ?? MockOddsWebSocketClient()
        self.oddsStore = oddsStore
        self.rowMapper = rowMapper ?? MatchRowViewModelMapper()
        self.reconnectDelayNanoseconds = reconnectDelayNanoseconds
    }

    isolated deinit {
        stopLiveUpdates()
    }

    func loadInitialMatches() async {
        state = .loading

        do {
            async let matches = matchesService.fetchMatches()
            async let odds = oddsService.fetchInitialOdds()

            let records = try MatchRecordMapper.makeRecords(
                matches: try await matches,
                odds: try await odds
            )
            await oddsStore.replaceAll(records)
            displayRows = rowMapper.makeRows(from: records)
            rowIndexByMatchID = makeRowIndexByMatchID(from: displayRows)
            state = .loaded(rows: displayRows)
            startListeningForOddsUpdates(matchIDs: records.map(\.matchID))
        } catch is CancellationError {
            return
        } catch {
            state = .failed(message: "Unable to load matches")
        }
    }

    func stopLiveUpdates() {
        isLiveUpdatesStopped = true
        oddsUpdateTask?.cancel()
        oddsUpdateTask = nil
        oddsWebSocketClient.disconnect()
        liveConnectionState = .disconnected(message: "Live updates stopped")
    }

    private func startListeningForOddsUpdates(matchIDs: [Int]) {
        oddsUpdateTask?.cancel()
        isLiveUpdatesStopped = false
        liveConnectionState = .connecting
        let initialEvents = oddsWebSocketClient.connect(matchIDs: matchIDs)

        oddsUpdateTask = Task { @MainActor [weak self] in
            await self?.runLiveUpdates(
                matchIDs: matchIDs,
                initialEvents: initialEvents
            )
        }
    }

    private func runLiveUpdates(
        matchIDs: [Int],
        initialEvents: AsyncStream<OddsWebSocketEvent>
    ) async {
        var events: AsyncStream<OddsWebSocketEvent>? = initialEvents

        while !Task.isCancelled && !isLiveUpdatesStopped {
            let currentEvents = events ?? oddsWebSocketClient.connect(matchIDs: matchIDs)
            events = nil

            for await event in currentEvents {
                guard !Task.isCancelled else { return }
                await handleWebSocketEvent(event)
            }

            guard !Task.isCancelled, !isLiveUpdatesStopped else { return }
            liveConnectionState = .reconnecting

            do {
                try await Task.sleep(nanoseconds: reconnectDelayNanoseconds)
            } catch {
                return
            }
        }
    }

    private func handleWebSocketEvent(_ event: OddsWebSocketEvent) async {
        switch event {
        case .connected:
            liveConnectionState = .connected
        case let .disconnected(reason):
            handleDisconnect(reason)
        case let .failed(error):
            handleWebSocketError(error)
        case let .oddsUpdated(updates):
            await handleOddsUpdates(updates)
        }
    }

    private func handleDisconnect(_ reason: OddsWebSocketDisconnectReason) {
        switch reason {
        case .manual:
            liveConnectionState = .disconnected(message: "Live updates stopped")
        case .noMatchIDs:
            liveConnectionState = .disconnected(message: "No matches available for live updates")
        case .streamEnded:
            liveConnectionState = .reconnecting
        }
    }

    private func handleWebSocketError(_ error: OddsWebSocketError) {
        switch error {
        case .connectionFailed:
            liveConnectionState = .failed(message: "Live updates unavailable")
        }
    }

    private func handleOddsUpdates(_ updates: [OddsUpdateDTO]) async {
        guard !Task.isCancelled else { return }

        let changedRecords = await oddsStore.applyOddsUpdates(updates)

        guard !Task.isCancelled else { return }

        let changedRows = rowMapper.makeRows(from: changedRecords)
        var updatedIndexes: [Int] = []

        for row in changedRows {
            guard !Task.isCancelled else { return }
            guard let rowIndex = rowIndexByMatchID[row.matchID] else { continue }

            displayRows[rowIndex] = row
            updatedIndexes.append(rowIndex)
        }

        guard !updatedIndexes.isEmpty else { return }

        onRowsUpdated?(displayRows, updatedIndexes)
    }

    private func makeRowIndexByMatchID(from rows: [MatchRowViewModel]) -> [Int: Int] {
        Dictionary(
            uniqueKeysWithValues: rows.enumerated().map { index, row in
                (row.matchID, index)
            }
        )
    }
}
