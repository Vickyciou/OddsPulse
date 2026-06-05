import Foundation

nonisolated enum OddsState: Equatable, Sendable {
    case available(teamAOdds: Decimal, teamBOdds: Decimal)
    case unavailable
}
