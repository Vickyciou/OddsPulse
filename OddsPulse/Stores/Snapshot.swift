import Foundation

nonisolated struct Snapshot: Equatable, Sendable {
    private var records: [MatchRecord]
    private var indexByMatchID: [Int: Int]

    init(records: [MatchRecord] = []) {
        self.records = records
        indexByMatchID = Self.makeIndexByMatchID(from: records)
    }

    var orderedRecords: [MatchRecord] {
        records
    }

    func record(for matchID: Int) -> MatchRecord? {
        guard let index = indexByMatchID[matchID] else { return nil }

        return records[index]
    }

    mutating func replaceRecords(_ records: [MatchRecord]) {
        self.records = records
        indexByMatchID = Self.makeIndexByMatchID(from: records)
    }

    mutating func upsertRecord(_ record: MatchRecord) {
        guard let index = indexByMatchID[record.matchID] else {
            indexByMatchID[record.matchID] = records.count
            records.append(record)
            return
        }

        records[index] = record
    }

    mutating func removeRecord(matchID: Int) -> MatchRecord? {
        guard let removedIndex = indexByMatchID[matchID] else { return nil }

        let removedRecord = records.remove(at: removedIndex)
        indexByMatchID = Self.makeIndexByMatchID(from: records)
        return removedRecord
    }

    mutating func applyOddsUpdates(_ updates: [OddsUpdateDTO]) -> UpdateResult {
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

    private static func makeIndexByMatchID(from records: [MatchRecord]) -> [Int: Int] {
        Dictionary(
            uniqueKeysWithValues: records.enumerated().map { index, record in
                (record.matchID, index)
            }
        )
    }
}
