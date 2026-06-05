import Foundation

nonisolated protocol ResourceLoading: Sendable {
    func data(resourceName: String, fileExtension: String) throws -> Data
}

nonisolated enum ResourceLoadingError: Error, Equatable {
    case missingResource(name: String, fileExtension: String)
}

nonisolated struct BundleResourceLoader: ResourceLoading {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func data(resourceName: String, fileExtension: String) throws -> Data {
        guard let url = bundle.url(forResource: resourceName, withExtension: fileExtension) else {
            throw ResourceLoadingError.missingResource(
                name: resourceName,
                fileExtension: fileExtension
            )
        }

        return try Data(contentsOf: url)
    }
}
