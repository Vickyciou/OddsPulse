import Foundation

actor OddsStore {
    private var records: [MatchRecord] = []
    private var indexByMatchID: [Int: Int] = [:]

    func replaceAll(_ records: [MatchRecord]) {
        self.records = records
        indexByMatchID = Dictionary(
            uniqueKeysWithValues: records.enumerated().map { index, record in
                (record.matchID, index)
            }
        )
    }

    func allRecords() -> [MatchRecord] {
        records
    }

    func snapshot() -> OddsSnapshot {
        OddsSnapshot(records: records)
    }

    func applyOddsUpdates(_ updates: [OddsUpdateDTO]) -> OddsUpdateApplyResult {
        var changedRecords: [MatchRecord] = []
        var ignoredMatchIDs: [Int] = []

        for update in updates {
            guard let index = indexByMatchID[update.matchID] else {
                ignoredMatchIDs.append(update.matchID)
                continue
            }

            records[index].oddsState = .available(
                teamAOdds: update.teamAOdds,
                teamBOdds: update.teamBOdds
            )
            changedRecords.append(records[index])
        }

        return OddsUpdateApplyResult(
            changedRecords: changedRecords,
            ignoredMatchIDs: ignoredMatchIDs
        )
    }
}

struct OddsUpdateApplyResult: Equatable {
    let changedRecords: [MatchRecord]
    let ignoredMatchIDs: [Int]
}

struct OddsSnapshot: Equatable {
    let records: [MatchRecord]

    var isEmpty: Bool {
        records.isEmpty
    }
}
