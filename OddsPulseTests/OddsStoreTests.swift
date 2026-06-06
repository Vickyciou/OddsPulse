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
            OddsUpdate(matchID: 1002, teamAOdds: 1.88, teamBOdds: 2.05),
            OddsUpdate(matchID: 9999, teamAOdds: 4.00, teamBOdds: 5.00)
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
            OddsUpdate(matchID: 1001, teamAOdds: 1.50, teamBOdds: 2.50),
            OddsUpdate(matchID: 2001, teamAOdds: 1.75, teamBOdds: 2.25)
        ])

        XCTAssertEqual(applyResult.changedRecords.map(\.matchID), [2001])
        XCTAssertEqual(applyResult.unknownMatchIDs, [1001])
    }

    func testSnapshotReturnsLatestRecords() async {
        let store = OddsStore()
        await store.replaceRecords([makeRecord(matchID: 1001)])
        _ = await store.applyOddsUpdates([
            OddsUpdate(matchID: 1001, teamAOdds: 1.75, teamBOdds: 2.25)
        ])

        let snapshotRecords = await store.snapshot()

        XCTAssertEqual(snapshotRecords.map(\.matchID), [1001])
        XCTAssertEqual(
            snapshotRecords.first?.oddsState,
            .available(teamAOdds: 1.75, teamBOdds: 2.25)
        )
    }

    func testConcurrentOddsUpdatesProduceConsistentSnapshot() async {
        let store = OddsStore()
        await store.replaceRecords([
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002),
            makeRecord(matchID: 1003)
        ])
        let updates = [
            OddsUpdate(matchID: 1001, teamAOdds: 1.11, teamBOdds: 2.11),
            OddsUpdate(matchID: 1002, teamAOdds: 1.22, teamBOdds: 2.22),
            OddsUpdate(matchID: 1003, teamAOdds: 1.33, teamBOdds: 2.33)
        ]

        await withTaskGroup(of: Void.self) { taskGroup in
            for update in updates {
                taskGroup.addTask {
                    _ = await store.applyOddsUpdates([update])
                }
            }
        }

        let snapshotRecords = await store.snapshot()

        XCTAssertEqual(
            snapshotRecords.first { $0.matchID == 1001 }?.oddsState,
            .available(teamAOdds: 1.11, teamBOdds: 2.11)
        )
        XCTAssertEqual(
            snapshotRecords.first { $0.matchID == 1002 }?.oddsState,
            .available(teamAOdds: 1.22, teamBOdds: 2.22)
        )
        XCTAssertEqual(
            snapshotRecords.first { $0.matchID == 1003 }?.oddsState,
            .available(teamAOdds: 1.33, teamBOdds: 2.33)
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
