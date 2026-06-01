import XCTest
@testable import OddsPulse

final class MatchRowViewModelMapperTests: XCTestCase {
    func testMakeRowsDisplaysUnavailableOddsAsDashes() {
        let mapper = MatchRowViewModelMapper()
        let records = [
            MatchRecord(
                matchID: 1001,
                teamA: "Eagles",
                teamB: "Tigers",
                startTime: Date(timeIntervalSince1970: 0),
                oddsState: .unavailable
            )
        ]

        let rows = mapper.makeRows(from: records)

        XCTAssertEqual(rows.first?.teamAOddsText, "--")
        XCTAssertEqual(rows.first?.teamBOddsText, "--")
    }
}
