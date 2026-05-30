import Foundation

struct OddsResponseDTO: Decodable, Equatable, Sendable {
    let matchID: Int
    let teamAOdds: Decimal
    let teamBOdds: Decimal
}
