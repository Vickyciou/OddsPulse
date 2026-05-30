import Foundation

protocol MatchesServiceProtocol: Sendable {
    func fetchMatches() async throws -> [MatchResponseDTO]
}

struct MockMatchesService: MatchesServiceProtocol {
    private enum Constants {
        static let resourceName = "matches"
        static let fileExtension = "json"
        static let simulatedLatencyNanoseconds: UInt64 = 300_000_000
    }

    private let resourceLoader: ResourceLoading
    private let jsonDecoder: JSONDecoder

    init(
        resourceLoader: ResourceLoading = BundleResourceLoader(),
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.resourceLoader = resourceLoader
        self.jsonDecoder = jsonDecoder
    }

    func fetchMatches() async throws -> [MatchResponseDTO] {
        try await Task.sleep(nanoseconds: Constants.simulatedLatencyNanoseconds)
        let data = try resourceLoader.data(
            resourceName: Constants.resourceName,
            fileExtension: Constants.fileExtension
        )
        return try jsonDecoder.decode([MatchResponseDTO].self, from: data)
    }
}
