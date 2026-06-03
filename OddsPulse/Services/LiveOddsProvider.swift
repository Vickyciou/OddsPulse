import Foundation

protocol LiveOddsProviderProtocol: Sendable {
    func stream() -> AsyncStream<LiveOddsEvent>
}

enum LiveOddsEvent: Equatable {
    case loading
    case recordsLoaded([MatchRecord])
    case oddsUpdated(changedRecords: [MatchRecord])
    case feedStatusChanged(LiveOddsFeedStatus)
    case initialLoadFailed(message: String)
}

enum LiveOddsFeedStatus: Equatable {
    case idle
    case connecting
    case live
    case reconnecting
    case unavailable(message: String)
}
