import Foundation

nonisolated enum MatchRecordMapper {
    nonisolated enum MappingError: Error, Equatable {
        case invalidStartTime(matchID: Int, value: String)
    }

    static func makeRecords(
        matches: [MatchResponseDTO],
        odds: [OddsResponseDTO]
    ) throws -> [MatchRecord] {
        let oddsByMatchID = Dictionary(uniqueKeysWithValues: odds.map { ($0.matchID, $0) })
        let dateFormatter = ISO8601DateFormatter()

        let records = try matches.map { match in
            guard let startTime = dateFormatter.date(from: match.startTime) else {
                throw MappingError.invalidStartTime(
                    matchID: match.matchID,
                    value: match.startTime
                )
            }

            let oddsState: OddsState
            if let initialOdds = oddsByMatchID[match.matchID] {
                oddsState = .available(
                    teamAOdds: initialOdds.teamAOdds,
                    teamBOdds: initialOdds.teamBOdds
                )
            } else {
                oddsState = .unavailable
            }

            return MatchRecord(
                matchID: match.matchID,
                teamA: match.teamA,
                teamB: match.teamB,
                startTime: startTime,
                oddsState: oddsState
            )
        }

        return records.sorted { firstRecord, secondRecord in
            if firstRecord.startTime == secondRecord.startTime {
                return firstRecord.matchID < secondRecord.matchID
            }

            return firstRecord.startTime < secondRecord.startTime
        }
    }
}
