import XCTest
@testable import OddsPulse

@MainActor
final class SnapshotTests: XCTestCase {
    func testUpsertAppendsNewRecordAndPreservesOrdering() {
        var snapshot = Snapshot(records: [
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002)
        ])

        snapshot.upsertRecord(makeRecord(matchID: 1003))

        XCTAssertEqual(snapshot.orderedRecords.map(\.matchID), [1001, 1002, 1003])
    }

    func testUpsertReplacesExistingRecordWithoutChangingOrdering() {
        var snapshot = Snapshot(records: [
            makeRecord(matchID: 1001, teamA: "Eagles"),
            makeRecord(matchID: 1002)
        ])

        snapshot.upsertRecord(makeRecord(matchID: 1001, teamA: "Falcons"))

        XCTAssertEqual(snapshot.orderedRecords.map(\.matchID), [1001, 1002])
        XCTAssertEqual(snapshot.record(for: 1001)?.teamA, "Falcons")
    }

    func testRemoveDeletesRecordAndUpdatesLookupIndex() {
        var snapshot = Snapshot(records: [
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002),
            makeRecord(matchID: 1003)
        ])

        let removedRecord = snapshot.removeRecord(matchID: 1002)

        XCTAssertEqual(removedRecord?.matchID, 1002)
        XCTAssertEqual(snapshot.orderedRecords.map(\.matchID), [1001, 1003])
        XCTAssertNil(snapshot.record(for: 1002))
        XCTAssertEqual(snapshot.record(for: 1003)?.matchID, 1003)
    }

    func testLookupReturnsRecordForKnownMatchID() {
        let snapshot = Snapshot(records: [
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002)
        ])

        XCTAssertEqual(snapshot.record(for: 1002)?.matchID, 1002)
        XCTAssertNil(snapshot.record(for: 9999))
    }

    func testReplaceRecordsResetsStorageOrderingAndLookup() {
        var snapshot = Snapshot(records: [makeRecord(matchID: 1001)])

        snapshot.replaceRecords([
            makeRecord(matchID: 2001),
            makeRecord(matchID: 2002)
        ])

        XCTAssertEqual(snapshot.orderedRecords.map(\.matchID), [2001, 2002])
        XCTAssertNil(snapshot.record(for: 1001))
        XCTAssertEqual(snapshot.record(for: 2002)?.matchID, 2002)
    }

    func testApplyOddsUpdatesChangesKnownRecordsOnly() {
        var snapshot = Snapshot(records: [
            makeRecord(matchID: 1001),
            makeRecord(matchID: 1002)
        ])

        let applyResult = snapshot.applyOddsUpdates([
            OddsUpdate(matchID: 1002, teamAOdds: 1.88, teamBOdds: 2.05),
            OddsUpdate(matchID: 9999, teamAOdds: 4.00, teamBOdds: 5.00)
        ])

        XCTAssertEqual(applyResult.changedRecords.map(\.matchID), [1002])
        XCTAssertEqual(applyResult.unknownMatchIDs, [9999])
        XCTAssertEqual(
            snapshot.record(for: 1002)?.oddsState,
            .available(teamAOdds: 1.88, teamBOdds: 2.05)
        )
    }

    private func makeRecord(
        matchID: Int,
        teamA: String = "Eagles"
    ) -> MatchRecord {
        MatchRecord(
            matchID: matchID,
            teamA: teamA,
            teamB: "Tigers",
            startTime: Date(timeIntervalSince1970: TimeInterval(matchID)),
            oddsState: .unavailable
        )
    }
}
