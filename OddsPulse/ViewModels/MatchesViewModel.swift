import Foundation

@MainActor
final class MatchesViewModel {
    var onStateChange: ((MatchesViewState) -> Void)?

    private(set) var state: MatchesViewState = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    private let matchesService: MatchesServiceProtocol
    private let oddsService: OddsServiceProtocol
    private let rowMapper: MatchRowViewModelMapper

    init(
        matchesService: MatchesServiceProtocol? = nil,
        oddsService: OddsServiceProtocol? = nil,
        rowMapper: MatchRowViewModelMapper? = nil
    ) {
        self.matchesService = matchesService ?? MockMatchesService()
        self.oddsService = oddsService ?? MockOddsService()
        self.rowMapper = rowMapper ?? MatchRowViewModelMapper()
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
            state = .loaded(rows: rowMapper.makeRows(from: records))
        } catch is CancellationError {
            return
        } catch {
            state = .failed(message: "Unable to load matches")
        }
    }
}
