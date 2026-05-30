import Foundation

struct MatchRecord: Equatable, Sendable {
    let matchID: Int
    let teamA: String
    let teamB: String
    let startTime: Date
    var oddsState: OddsState
}
