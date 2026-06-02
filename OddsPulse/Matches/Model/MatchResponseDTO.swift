import Foundation

struct MatchResponseDTO: Decodable, Equatable, Sendable {
    let matchID: Int
    let teamA: String
    let teamB: String
    let startTime: String
}
