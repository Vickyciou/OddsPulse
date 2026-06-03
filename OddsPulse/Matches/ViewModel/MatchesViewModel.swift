import Foundation

@MainActor
final class MatchesViewModel {
    var onStateChange: ((MatchesViewState) -> Void)?
    var onRowsUpdated: (([MatchRowViewModel], [Int]) -> Void)?
    var onFeedStatusChange: ((LiveOddsFeedStatus) -> Void)?

    private(set) var state: MatchesViewState = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    private(set) var displayRows: [MatchRowViewModel] = []
    private(set) var feedStatus: LiveOddsFeedStatus = .idle {
        didSet {
            onFeedStatusChange?(feedStatus)
        }
    }

    private let liveOddsProvider: LiveOddsProviderProtocol
    private let rowMapper: MatchRowViewModelMapper
    private var rowIndexByMatchID: [Int: Int] = [:]
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

        liveOddsTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for await event in liveOddsProvider.stream() {
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
            state = .loading
        case let .recordsLoaded(records):
            renderRecords(records)
        case let .oddsUpdated(changedRecords):
            updateRows(from: changedRecords)
        case let .feedStatusChanged(feedStatus):
            self.feedStatus = feedStatus
        case let .initialLoadFailed(message):
            state = .failed(message: message)
        }
    }

    private func renderRecords(_ records: [MatchRecord]) {
        displayRows = rowMapper.makeRows(from: records)
        rowIndexByMatchID = makeRowIndexByMatchID(from: displayRows)
        state = .loaded(rows: displayRows)
    }

    private func updateRows(from changedRecords: [MatchRecord]) {
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
