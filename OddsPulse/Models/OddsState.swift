import Foundation

enum OddsState: Equatable, Sendable {
    case available(teamAOdds: Decimal, teamBOdds: Decimal)
    case unavailable
}
