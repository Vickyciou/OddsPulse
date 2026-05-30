import XCTest
@testable import OddsPulse

final class MatchRecordMapperTests: XCTestCase {
    func testMakeRecordsSortsByStartTimeThenMatchID() throws {
        let matches = [
            makeMatch(matchID: 1003, startTime: "2025-07-04T14:00:00Z"),
            makeMatch(matchID: 1002, startTime: "2025-07-04T13:00:00Z"),
            makeMatch(matchID: 1001, startTime: "2025-07-04T13:00:00Z")
        ]
        let odds = matches.map { makeOdds(matchID: $0.matchID) }

        let records = try MatchRecordMapper.makeRecords(matches: matches, odds: odds)

        XCTAssertEqual(records.map(\.matchID), [1001, 1002, 1003])
    }

    func testMakeRecordsMarksMissingOddsAsUnavailable() throws {
        let matches = [
            makeMatch(matchID: 1001),
            makeMatch(matchID: 1002)
        ]
        let odds = [
            makeOdds(matchID: 1001)
        ]

        let records = try MatchRecordMapper.makeRecords(matches: matches, odds: odds)

        XCTAssertEqual(records.first { $0.matchID == 1001 }?.oddsState, .available(teamAOdds: 1.95, teamBOdds: 2.1))
        XCTAssertEqual(records.first { $0.matchID == 1002 }?.oddsState, .unavailable)
    }

    func testMakeRecordsIgnoresUnknownOdds() throws {
        let matches = [
            makeMatch(matchID: 1001)
        ]
        let odds = [
            makeOdds(matchID: 1001),
            makeOdds(matchID: 9999)
        ]

        let records = try MatchRecordMapper.makeRecords(matches: matches, odds: odds)

        XCTAssertEqual(records.map(\.matchID), [1001])
    }

    func testMakeRecordsThrowsWhenStartTimeIsInvalid() {
        let matches = [
            makeMatch(matchID: 1001, startTime: "invalid")
        ]

        XCTAssertThrowsError(try MatchRecordMapper.makeRecords(matches: matches, odds: [])) { error in
            XCTAssertEqual(
                error as? MatchRecordMapper.MappingError,
                .invalidStartTime(matchID: 1001, value: "invalid")
            )
        }
    }

    private func makeMatch(
        matchID: Int,
        startTime: String = "2025-07-04T13:00:00Z"
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
        teamAOdds: Decimal = 1.95,
        teamBOdds: Decimal = 2.10
    ) -> OddsResponseDTO {
        OddsResponseDTO(
            matchID: matchID,
            teamAOdds: teamAOdds,
            teamBOdds: teamBOdds
        )
    }
}
