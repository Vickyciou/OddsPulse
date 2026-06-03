import Foundation

@MainActor
final class SceneDependencies {
    let liveOddsProvider: LiveOddsProviderProtocol

    init() {
        liveOddsProvider = LiveOddsProvider()
    }
}
