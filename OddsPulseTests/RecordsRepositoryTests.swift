import XCTest
@testable import OddsPulse

final class RecordsRepositoryTests: XCTestCase {
    func testFetchRecordsRunsServicesInParallelAndReturnsMappedRecords() async throws {
        let parallelFetchCoordinator = ParallelFetchCoordinator()
        let expectedRecords = [
            makeRecord(matchID: 3001),
            makeRecord(matchID: 3002)
        ]
        let repository = RecordsRepository(
            matchesService: FakeMatchesService(
                result: .success([
                    makeMatch(matchID: 1001),
                    makeMatch(matchID: 1002)
                ]),
                parallelFetchCoordinator: parallelFetchCoordinator
            ),
            oddsService: FakeOddsService(
                result: .success([
                    makeOdds(matchID: 1001),
                    makeOdds(matchID: 1002)
                ]),
                parallelFetchCoordinator: parallelFetchCoordinator
            ),
            recordsMapper: StubRecordsMapper(result: .success(expectedRecords))
        )

        let records = try await repository.fetchRecords()
        let startedSources = await parallelFetchCoordinator.startedSources()

        XCTAssertEqual(records, expectedRecords)
        XCTAssertEqual(startedSources, [.matches, .odds])
    }

    func testFetchRecordsPropagatesMatchesFailure() async {
        let repository = RecordsRepository(
            matchesService: FakeMatchesService(result: .failure(TestError.matchesFailed)),
            oddsService: FakeOddsService(result: .success([makeOdds(matchID: 1001)])),
            recordsMapper: StubRecordsMapper(result: .success([makeRecord(matchID: 1001)]))
        )

        await XCTAssertThrowsErrorAsync(try await repository.fetchRecords()) { error in
            XCTAssertEqual(error as? TestError, .matchesFailed)
        }
    }

    func testFetchRecordsPropagatesOddsFailure() async {
        let repository = RecordsRepository(
            matchesService: FakeMatchesService(result: .success([makeMatch(matchID: 1001)])),
            oddsService: FakeOddsService(result: .failure(TestError.oddsFailed)),
            recordsMapper: StubRecordsMapper(result: .success([makeRecord(matchID: 1001)]))
        )

        await XCTAssertThrowsErrorAsync(try await repository.fetchRecords()) { error in
            XCTAssertEqual(error as? TestError, .oddsFailed)
        }
    }

    func testFetchRecordsPropagatesMapperFailure() async {
        let repository = RecordsRepository(
            matchesService: FakeMatchesService(result: .success([makeMatch(matchID: 1001)])),
            oddsService: FakeOddsService(result: .success([makeOdds(matchID: 1001)])),
            recordsMapper: StubRecordsMapper(result: .failure(TestError.mappingFailed))
        )

        await XCTAssertThrowsErrorAsync(try await repository.fetchRecords()) { error in
            XCTAssertEqual(error as? TestError, .mappingFailed)
        }
    }

    private func makeMatch(
        matchID: Int,
        startTime: String = "2026-01-01T12:00:00Z"
    ) -> MatchResponseDTO {
        MatchResponseDTO(
            matchID: matchID,
            teamA: "Eagles",
            teamB: "Tigers",
            startTime: startTime
        )
    }

    private func makeOdds(
        matchID: Int,
        teamAOdds: Decimal = 1.50,
        teamBOdds: Decimal = 2.50
    ) -> OddsResponseDTO {
        OddsResponseDTO(
            matchID: matchID,
            teamAOdds: teamAOdds,
            teamBOdds: teamBOdds
        )
    }

    private func makeRecord(matchID: Int) -> MatchRecord {
        MatchRecord(
            matchID: matchID,
            teamA: "Eagles",
            teamB: "Tigers",
            startTime: Date(timeIntervalSince1970: TimeInterval(matchID)),
            oddsState: .unavailable
        )
    }
}

nonisolated private enum TestError: Error, Equatable {
    case matchesFailed
    case oddsFailed
    case mappingFailed
    case fetchesDidNotStartInParallel
}

nonisolated private enum FetchSource: Hashable {
    case matches
    case odds
}

private actor ParallelFetchCoordinator {
    private var sources: Set<FetchSource> = []

    func markStarted(_ source: FetchSource) async throws {
        sources.insert(source)

        guard sources.count < 2 else { return }

        try await Task.sleep(nanoseconds: 50_000_000)
        guard sources.count == 2 else {
            throw TestError.fetchesDidNotStartInParallel
        }
    }

    func startedSources() -> Set<FetchSource> {
        sources
    }
}

private actor FakeMatchesService: MatchesServiceProtocol {
    private let result: Result<[MatchResponseDTO], Error>
    private let parallelFetchCoordinator: ParallelFetchCoordinator?

    init(
        result: Result<[MatchResponseDTO], Error>,
        parallelFetchCoordinator: ParallelFetchCoordinator? = nil
    ) {
        self.result = result
        self.parallelFetchCoordinator = parallelFetchCoordinator
    }

    func fetchMatches() async throws -> [MatchResponseDTO] {
        try await parallelFetchCoordinator?.markStarted(.matches)
        return try result.get()
    }
}

private actor FakeOddsService: OddsServiceProtocol {
    private let result: Result<[OddsResponseDTO], Error>
    private let parallelFetchCoordinator: ParallelFetchCoordinator?

    init(
        result: Result<[OddsResponseDTO], Error>,
        parallelFetchCoordinator: ParallelFetchCoordinator? = nil
    ) {
        self.result = result
        self.parallelFetchCoordinator = parallelFetchCoordinator
    }

    func fetchInitialOdds() async throws -> [OddsResponseDTO] {
        try await parallelFetchCoordinator?.markStarted(.odds)
        return try result.get()
    }
}

nonisolated private struct StubRecordsMapper: RecordsMapping {
    let result: Result<[MatchRecord], Error>

    func makeRecords(
        matches: [MatchResponseDTO],
        odds: [OddsResponseDTO]
    ) throws -> [MatchRecord] {
        try result.get()
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
