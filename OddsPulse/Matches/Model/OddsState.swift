import Foundation

nonisolated enum OddsState: Equatable, Sendable {
    case available(teamAOdds: Decimal, teamBOdds: Decimal)
    case unavailable
}

nonisolated struct OddsUpdate: Equatable, Sendable {
    let matchID: Int
    let teamAOdds: Decimal
    let teamBOdds: Decimal
}
