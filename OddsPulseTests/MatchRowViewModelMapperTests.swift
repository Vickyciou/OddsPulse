import XCTest
@testable import OddsPulse

final class MatchRowViewModelMapperTests: XCTestCase {
    func testMakeRowsMapsRecordIdentityTeamsDateAndAvailableOdds() {
        // 準備
        let mapper = MatchRowViewModelMapper(dateFormatter: makeDateFormatter())
        let records = [
            MatchRecord(
                matchID: 1001,
                teamA: "Eagles",
                teamB: "Tigers",
                startTime: Date(timeIntervalSince1970: 1_704_110_400),
                oddsState: .available(teamAOdds: 1.88, teamBOdds: 2.05)
            )
        ]

        // 執行
        let rows = mapper.makeRows(from: records)

        // 驗證
        XCTAssertEqual(rows.first?.matchID, 1001)
        XCTAssertEqual(rows.first?.teamA, "Eagles")
        XCTAssertEqual(rows.first?.teamB, "Tigers")
        XCTAssertEqual(rows.first?.startTimeText, "Jan 1, 12:00")
        XCTAssertEqual(rows.first?.teamAOddsText, "1.88")
        XCTAssertEqual(rows.first?.teamBOddsText, "2.05")
    }

    func testMakeRowsDisplaysUnavailableOddsAsDashes() {
        // 準備
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

        // 執行
        let rows = mapper.makeRows(from: records)

        // 驗證
        XCTAssertEqual(rows.first?.teamAOddsText, "--")
        XCTAssertEqual(rows.first?.teamBOddsText, "--")
    }

    private func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }
}
