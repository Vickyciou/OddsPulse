import Foundation

nonisolated struct UpdateResult: Equatable, Sendable {
    let changedRecords: [MatchRecord]
    let unknownMatchIDs: [Int]
}

protocol OddsStoreProtocol: AnyObject {
    func replaceRecords(_ records: [MatchRecord]) async
    func snapshot() async -> [MatchRecord]
    func applyOddsUpdates(_ updates: [OddsUpdateDTO]) async -> UpdateResult
}

actor OddsStore: OddsStoreProtocol {
    private var currentSnapshot = Snapshot()

    func replaceRecords(_ records: [MatchRecord]) {
        currentSnapshot.replaceRecords(records)
    }

    func snapshot() -> [MatchRecord] {
        currentSnapshot.orderedRecords
    }

    func applyOddsUpdates(_ updates: [OddsUpdateDTO]) -> UpdateResult {
        currentSnapshot.applyOddsUpdates(updates)
    }
}
