import XCTest
@testable import OddsPulse

final class OddsStoreTests: XCTestCase {
    func testApplyOddsUpdatesChangesKnownRecordsOnly() async {
        let store = OddsStore()
        let records = [
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002)
        ]
        await store.replaceAll(records)

        let applyResult = await store.applyOddsUpdates([
            OddsUpdateDTO(matchID: 1002, teamAOdds: 1.88, teamBOdds: 2.05),
            OddsUpdateDTO(matchID: 9999, teamAOdds: 4.00, teamBOdds: 5.00)
        ])
        let allRecords = await store.allRecords()

        XCTAssertEqual(applyResult.changedRecords.map(\.matchID), [1002])
        XCTAssertEqual(applyResult.ignoredMatchIDs, [9999])
        XCTAssertEqual(
            allRecords.first { $0.matchID == 1001 }?.oddsState,
            .unavailable
        )
        XCTAssertEqual(
            allRecords.first { $0.matchID == 1002 }?.oddsState,
            .available(teamAOdds: 1.88, teamBOdds: 2.05)
        )
    }

    func testReplaceAllResetsPreviousRecords() async {
        let store = OddsStore()
        await store.replaceAll([makeRecord(matchID: 1001)])
        await store.replaceAll([makeRecord(matchID: 2001)])

        let applyResult = await store.applyOddsUpdates([
            OddsUpdateDTO(matchID: 1001, teamAOdds: 1.50, teamBOdds: 2.50),
            OddsUpdateDTO(matchID: 2001, teamAOdds: 1.75, teamBOdds: 2.25)
        ])

        XCTAssertEqual(applyResult.changedRecords.map(\.matchID), [2001])
        XCTAssertEqual(applyResult.ignoredMatchIDs, [1001])
    }

    private func makeRecord(matchID: Int) -> MatchRecord {
        MatchRecord(
            matchID: matchID,
            teamA: "Eagles",
            teamB: "Tigers",
            startTime: Date(timeIntervalSince1970: 0),
            oddsState: .unavailable
        )
    }
}
