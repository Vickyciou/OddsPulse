import Foundation

nonisolated protocol RecordsRepositoryProtocol: Sendable {
    func fetchRecords() async throws -> [MatchRecord]
}

nonisolated protocol RecordsMapping: Sendable {
    func makeRecords(
        matches: [MatchResponseDTO],
        odds: [OddsResponseDTO]
    ) throws -> [MatchRecord]
}

nonisolated struct MatchRecordsMapper: RecordsMapping {
    func makeRecords(
        matches: [MatchResponseDTO],
        odds: [OddsResponseDTO]
    ) throws -> [MatchRecord] {
        try MatchRecordMapper.makeRecords(matches: matches, odds: odds)
    }
}

nonisolated struct RecordsRepository: RecordsRepositoryProtocol {
    private let matchesService: MatchesServiceProtocol
    private let oddsService: OddsServiceProtocol
    private let recordsMapper: RecordsMapping

    init(
        matchesService: MatchesServiceProtocol = MockMatchesService(),
        oddsService: OddsServiceProtocol = MockOddsService(),
        recordsMapper: RecordsMapping = MatchRecordsMapper()
    ) {
        self.matchesService = matchesService
        self.oddsService = oddsService
        self.recordsMapper = recordsMapper
    }

    func fetchRecords() async throws -> [MatchRecord] {
        async let matches = matchesService.fetchMatches()
        async let odds = oddsService.fetchInitialOdds()

        return try recordsMapper.makeRecords(
            matches: try await matches,
            odds: try await odds
        )
    }
}
