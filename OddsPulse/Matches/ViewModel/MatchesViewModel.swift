import Foundation

@MainActor
final class MatchesViewModel {
    private typealias MatchID = Int
    private typealias RowIndex = Int

    var onStateChange: ((MatchesViewState) -> Void)?
    var onRowIndexesUpdated: (([Int]) -> Void)?
    var onFeedStatusChange: ((LiveOddsFeedStatus) -> Void)?

    private(set) var state: MatchesViewState = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    private(set) var rows: [MatchRowViewModel] = []
    private(set) var feedStatus: LiveOddsFeedStatus = .idle {
        didSet {
            onFeedStatusChange?(feedStatus)
        }
    }

    private let liveOddsProvider: LiveOddsProviderProtocol
    private let rowMapper: MatchRowViewModelMapper
    private var rowIndexByMatchID: [MatchID: RowIndex] = [:]
    private var liveOddsTask: Task<Void, Never>?

    init(
        liveOddsProvider: LiveOddsProviderProtocol? = nil,
        rowMapper: MatchRowViewModelMapper? = nil
    ) {
        self.liveOddsProvider = liveOddsProvider ?? LiveOddsProvider()
        self.rowMapper = rowMapper ?? MatchRowViewModelMapper()
    }

    isolated deinit {
        stopObservingLiveOdds()
    }

    func start() {
        guard liveOddsTask == nil else { return }

        let liveOddsProvider = liveOddsProvider
        liveOddsTask = Task { @MainActor [weak self, liveOddsProvider] in
            for await event in liveOddsProvider.stream() {
                guard let self else { break }

                handle(event)
            }
        }
    }

    func stopObservingLiveOdds() {
        liveOddsTask?.cancel()
        liveOddsTask = nil
    }

    private func handle(_ event: LiveOddsEvent) {
        switch event {
        case .loading:
            clearRows()
            state = .loading
        case let .recordsLoaded(records):
            renderRecords(records)
        case let .oddsUpdated(changedRecords):
            updateRows(from: changedRecords)
        case let .feedStatusChanged(feedStatus):
            self.feedStatus = feedStatus
        case let .initialLoadFailed(message):
            clearRows()
            state = .failed(message: message)
        }
    }

    private func renderRecords(_ records: [MatchRecord]) {
        let rows = rowMapper.makeRows(from: records)
        replaceRows(with: rows)
        state = .loaded(rows: rows)
    }

    private func updateRows(from changedRecords: [MatchRecord]) {
        let changedRows = rowMapper.makeRows(from: changedRecords)
        var updatedRowIndexes: [RowIndex] = []

        for row in changedRows {
            guard let rowIndex = rowIndexByMatchID[row.matchID] else { continue }

            rows[rowIndex] = row
            updatedRowIndexes.append(rowIndex)
        }

        guard !updatedRowIndexes.isEmpty else { return }

        onRowIndexesUpdated?(updatedRowIndexes)
    }

    private func replaceRows(with rows: [MatchRowViewModel]) {
        self.rows = rows
        rowIndexByMatchID = makeRowIndexByMatchID(from: rows)
    }

    private func clearRows() {
        replaceRows(with: [])
    }

    private func makeRowIndexByMatchID(from rows: [MatchRowViewModel]) -> [MatchID: RowIndex] {
        Dictionary(
            uniqueKeysWithValues: rows.enumerated().map { index, row in
                (row.matchID, index)
            }
        )
    }
}
