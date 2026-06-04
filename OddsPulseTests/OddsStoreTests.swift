import XCTest
@testable import OddsPulse

@MainActor
final class OddsStoreTests: XCTestCase {
    func testApplyOddsUpdatesChangesKnownRecordsOnly() async {
        let store = OddsStore()
        let records = [
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002)
        ]
        await store.replaceRecords(records)

        let applyResult = await store.applyOddsUpdates([
            OddsUpdateDTO(matchID: 1002, teamAOdds: 1.88, teamBOdds: 2.05),
            OddsUpdateDTO(matchID: 9999, teamAOdds: 4.00, teamBOdds: 5.00)
        ])
        let snapshotRecords = await store.snapshot()

        XCTAssertEqual(applyResult.changedRecords.map(\.matchID), [1002])
        XCTAssertEqual(applyResult.unknownMatchIDs, [9999])
        XCTAssertEqual(
            snapshotRecords.first { $0.matchID == 1001 }?.oddsState,
            .unavailable
        )
        XCTAssertEqual(
            snapshotRecords.first { $0.matchID == 1002 }?.oddsState,
            .available(teamAOdds: 1.88, teamBOdds: 2.05)
        )
    }

    func testReplaceRecordsResetsPreviousRecords() async {
        let store = OddsStore()
        await store.replaceRecords([makeRecord(matchID: 1001)])
        await store.replaceRecords([makeRecord(matchID: 2001)])

        let applyResult = await store.applyOddsUpdates([
            OddsUpdateDTO(matchID: 1001, teamAOdds: 1.50, teamBOdds: 2.50),
            OddsUpdateDTO(matchID: 2001, teamAOdds: 1.75, teamBOdds: 2.25)
        ])

        XCTAssertEqual(applyResult.changedRecords.map(\.matchID), [2001])
        XCTAssertEqual(applyResult.unknownMatchIDs, [1001])
    }

    func testSnapshotReturnsLatestRecords() async {
        let store = OddsStore()
        await store.replaceRecords([makeRecord(matchID: 1001)])
        _ = await store.applyOddsUpdates([
            OddsUpdateDTO(matchID: 1001, teamAOdds: 1.75, teamBOdds: 2.25)
        ])

        let snapshotRecords = await store.snapshot()

        XCTAssertEqual(snapshotRecords.map(\.matchID), [1001])
        XCTAssertEqual(
            snapshotRecords.first?.oddsState,
            .available(teamAOdds: 1.75, teamBOdds: 2.25)
        )
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
