enum MatchesViewState: Equatable {
    case idle
    case loading
    case loaded(rows: [MatchRowViewModel])
    case failed(message: String)
}

enum LiveConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    case disconnected(message: String)
    case failed(message: String)
}
