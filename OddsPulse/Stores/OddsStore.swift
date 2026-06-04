import Foundation

actor OddsStore {
    private var records: [MatchRecord] = []
    private var indexByMatchID: [Int: Int] = [:]

    func replaceRecords(_ records: [MatchRecord]) {
        self.records = records
        indexByMatchID = Dictionary(
            uniqueKeysWithValues: records.enumerated().map { index, record in
                (record.matchID, index)
            }
        )
    }

    func snapshot() -> Snapshot {
        Snapshot(records: records)
    }

    func applyOddsUpdates(_ updates: [OddsUpdateDTO]) -> UpdateResult {
        var changedRecords: [MatchRecord] = []
        var unknownMatchIDs: [Int] = []

        for update in updates {
            guard let index = indexByMatchID[update.matchID] else {
                unknownMatchIDs.append(update.matchID)
                continue
            }

            records[index].oddsState = .available(
                teamAOdds: update.teamAOdds,
                teamBOdds: update.teamBOdds
            )
            changedRecords.append(records[index])
        }

        return UpdateResult(
            changedRecords: changedRecords,
            unknownMatchIDs: unknownMatchIDs
        )
    }
}

extension OddsStore {
    struct UpdateResult: Equatable {
        let changedRecords: [MatchRecord]
        let unknownMatchIDs: [Int]
    }

    struct Snapshot: Equatable {
        let records: [MatchRecord]

        var isEmpty: Bool {
            records.isEmpty
        }
    }
}
