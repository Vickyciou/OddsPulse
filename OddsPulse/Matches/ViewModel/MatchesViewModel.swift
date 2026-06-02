import Foundation

@MainActor
final class MatchesViewModel {
    var onStateChange: ((MatchesViewState) -> Void)?
    var onRowsUpdated: (([MatchRowViewModel], [Int]) -> Void)?
    var onLiveConnectionStateChange: ((LiveConnectionState) -> Void)?
    var onIgnoredOddsUpdates: (([Int]) -> Void)?

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
    private(set) var ignoredOddsUpdateMatchIDs: [Int] = []

    private let matchesService: MatchesServiceProtocol
    private let oddsService: OddsServiceProtocol
    private let oddsWebSocketClient: OddsWebSocketClientProtocol
    private let oddsStore: OddsStore
    private let rowMapper: MatchRowViewModelMapper
    private let reconnectPolicy: ReconnectPolicy
    private var rowIndexByMatchID: [Int: Int] = [:]
    private var oddsUpdateTask: Task<Void, Never>?
    private var isLiveUpdatesStopped = true
    private var reconnectAttempt = 0

    init(
        matchesService: MatchesServiceProtocol? = nil,
        oddsService: OddsServiceProtocol? = nil,
        oddsWebSocketClient: OddsWebSocketClientProtocol? = nil,
        oddsStore: OddsStore = OddsStore(),
        rowMapper: MatchRowViewModelMapper? = nil,
        reconnectPolicy: ReconnectPolicy = .default
    ) {
        self.matchesService = matchesService ?? MockMatchesService()
        self.oddsService = oddsService ?? MockOddsService()
        self.oddsWebSocketClient = oddsWebSocketClient ?? MockOddsWebSocketClient()
        self.oddsStore = oddsStore
        self.rowMapper = rowMapper ?? MatchRowViewModelMapper()
        self.reconnectPolicy = reconnectPolicy
    }

    isolated deinit {
        stopLiveUpdates()
    }

    func loadInitialMatches() async {
        state = .loading

        let snapshot = await oddsStore.snapshot()
        if restoreSnapshotIfAvailable(snapshot) {
            return
        }

        do {
            async let matches = matchesService.fetchMatches()
            async let odds = oddsService.fetchInitialOdds()

            let records = try MatchRecordMapper.makeRecords(
                matches: try await matches,
                odds: try await odds
            )
            await oddsStore.replaceAll(records)
            renderRecords(records)
            startListeningForOddsUpdates(matchIDs: records.map(\.matchID))
        } catch is CancellationError {
            return
        } catch {
            state = .failed(message: "Unable to load matches")
        }
    }

    private func restoreSnapshotIfAvailable(_ snapshot: OddsSnapshot) -> Bool {
        guard !snapshot.isEmpty else { return false }

        renderRecords(snapshot.records)
        startListeningForOddsUpdates(matchIDs: snapshot.records.map(\.matchID))
        return true
    }

    private func renderRecords(_ records: [MatchRecord]) {
        displayRows = rowMapper.makeRows(from: records)
        rowIndexByMatchID = makeRowIndexByMatchID(from: displayRows)
        state = .loaded(rows: displayRows)
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
        reconnectAttempt = 0
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
            let reconnectDelayNanoseconds = reconnectPolicy.delayNanoseconds(
                forAttempt: reconnectAttempt
            )
            reconnectAttempt += 1

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
            reconnectAttempt = 0
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
            isLiveUpdatesStopped = true
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

        let applyResult = await oddsStore.applyOddsUpdates(updates)
        ignoredOddsUpdateMatchIDs.append(contentsOf: applyResult.ignoredMatchIDs)
        if !applyResult.ignoredMatchIDs.isEmpty {
            onIgnoredOddsUpdates?(applyResult.ignoredMatchIDs)
        }

        guard !Task.isCancelled else { return }

        let changedRows = rowMapper.makeRows(from: applyResult.changedRecords)
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

struct ReconnectPolicy: Equatable {
    nonisolated static let `default` = ReconnectPolicy(
        initialDelayNanoseconds: 1_000_000_000,
        maxDelayNanoseconds: 8_000_000_000,
        jitterRangeNanoseconds: 250_000_000
    )

    let initialDelayNanoseconds: UInt64
    let maxDelayNanoseconds: UInt64
    let jitterRangeNanoseconds: UInt64

    func delayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let multiplier = UInt64(1) << UInt64(max(0, min(attempt, 20)))
        let exponentialDelay = initialDelayNanoseconds.multipliedReportingOverflow(
            by: multiplier
        )
        let cappedDelay = min(
            exponentialDelay.overflow ? maxDelayNanoseconds : exponentialDelay.partialValue,
            maxDelayNanoseconds
        )

        guard jitterRangeNanoseconds > 0 else { return cappedDelay }

        return cappedDelay + UInt64.random(in: 0...jitterRangeNanoseconds)
    }
}
