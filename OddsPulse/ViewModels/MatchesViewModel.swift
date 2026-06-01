import Foundation

@MainActor
final class MatchesViewModel {
    var onStateChange: ((MatchesViewState) -> Void)?
    var onRowsUpdated: (([MatchRowViewModel], [Int]) -> Void)?

    private(set) var state: MatchesViewState = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    private(set) var displayRows: [MatchRowViewModel] = []

    private let matchesService: MatchesServiceProtocol
    private let oddsService: OddsServiceProtocol
    private let oddsWebSocketClient: OddsWebSocketClientProtocol
    private let oddsStore: OddsStore
    private let rowMapper: MatchRowViewModelMapper
    private var rowIndexByMatchID: [Int: Int] = [:]
    private var oddsUpdateTask: Task<Void, Never>?

    init(
        matchesService: MatchesServiceProtocol? = nil,
        oddsService: OddsServiceProtocol? = nil,
        oddsWebSocketClient: OddsWebSocketClientProtocol? = nil,
        oddsStore: OddsStore = OddsStore(),
        rowMapper: MatchRowViewModelMapper? = nil
    ) {
        self.matchesService = matchesService ?? MockMatchesService()
        self.oddsService = oddsService ?? MockOddsService()
        self.oddsWebSocketClient = oddsWebSocketClient ?? MockOddsWebSocketClient()
        self.oddsStore = oddsStore
        self.rowMapper = rowMapper ?? MatchRowViewModelMapper()
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
            startListeningForOddsUpdates()
            oddsWebSocketClient.connect(matchIDs: records.map(\.matchID))
        } catch is CancellationError {
            return
        } catch {
            state = .failed(message: "Unable to load matches")
        }
    }

    func stopLiveUpdates() {
        oddsUpdateTask?.cancel()
        oddsUpdateTask = nil
        oddsWebSocketClient.disconnect()
    }

    private func startListeningForOddsUpdates() {
        oddsUpdateTask?.cancel()

        let oddsUpdates = oddsWebSocketClient.oddsUpdates
        oddsUpdateTask = Task { @MainActor [weak self] in
            for await updates in oddsUpdates {
                guard !Task.isCancelled else { return }
                await self?.handleOddsUpdates(updates)
            }
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
