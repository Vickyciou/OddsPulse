enum MatchesViewState: Equatable {
    case idle
    case loading
    case loaded(rows: [MatchRowViewModel])
    case failed(message: String)
}
