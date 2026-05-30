import Foundation

struct OddsUpdateDTO: Equatable, Sendable {
    let matchID: Int
    let teamAOdds: Decimal
    let teamBOdds: Decimal
}
