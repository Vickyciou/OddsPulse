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
        bindOddsWebSocketClient()
    }

    isolated deinit {
        oddsWebSocketClient.disconnect()
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
            oddsWebSocketClient.connect(matchIDs: records.map(\.matchID))
        } catch is CancellationError {
            return
        } catch {
            state = .failed(message: "Unable to load matches")
        }
    }

    private func bindOddsWebSocketClient() {
        oddsWebSocketClient.onReceiveOddsUpdates = { [weak self] updates in
            Task { [weak self] in
                await self?.handleOddsUpdates(updates)
            }
        }
    }

    private func handleOddsUpdates(_ updates: [OddsUpdateDTO]) async {
        let changedRecords = await oddsStore.applyOddsUpdates(updates)
        let changedRows = rowMapper.makeRows(from: changedRecords)
        var updatedIndexes: [Int] = []

        for row in changedRows {
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
