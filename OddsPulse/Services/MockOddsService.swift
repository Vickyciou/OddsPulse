import Foundation

protocol OddsServiceProtocol: Sendable {
    func fetchInitialOdds() async throws -> [OddsResponseDTO]
}

struct MockOddsService: OddsServiceProtocol {
    private enum Constants {
        static let resourceName = "odds"
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

    func fetchInitialOdds() async throws -> [OddsResponseDTO] {
        try await Task.sleep(nanoseconds: Constants.simulatedLatencyNanoseconds)
        let data = try resourceLoader.data(
            resourceName: Constants.resourceName,
            fileExtension: Constants.fileExtension
        )
        return try jsonDecoder.decode([OddsResponseDTO].self, from: data)
    }
}
