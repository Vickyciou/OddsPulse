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

    func applyOddsUpdates(_ updates: [OddsUpdateDTO]) -> [MatchRecord] {
        var changedRecords: [MatchRecord] = []

        for update in updates {
            guard let index = indexByMatchID[update.matchID] else { continue }

            records[index].oddsState = .available(
                teamAOdds: update.teamAOdds,
                teamBOdds: update.teamBOdds
            )
            changedRecords.append(records[index])
        }

        return changedRecords
    }
}
