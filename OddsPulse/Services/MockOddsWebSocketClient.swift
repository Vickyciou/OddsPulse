import Foundation

@MainActor
protocol OddsWebSocketClientProtocol: AnyObject {
    var onReceiveOddsUpdates: (([OddsUpdateDTO]) -> Void)? { get set }

    func connect(matchIDs: [Int])
    func disconnect()
}

@MainActor
final class MockOddsWebSocketClient: OddsWebSocketClientProtocol {
    var onReceiveOddsUpdates: (([OddsUpdateDTO]) -> Void)?

    private enum Constants {
        static let interval: TimeInterval = 1
        static let batchSizeRange = 1...10
        static let oddsCentsRange = 100...500
    }

    private var timer: Timer?
    private var connectedMatchIDs: [Int] = []

    isolated deinit {
        disconnect()
    }

    func connect(matchIDs: [Int]) {
        disconnect()

        connectedMatchIDs = Array(Set(matchIDs))
        guard !connectedMatchIDs.isEmpty else { return }

        let timer = Timer(timeInterval: Constants.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendNextBatch()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func disconnect() {
        timer?.invalidate()
        timer = nil
        connectedMatchIDs = []
    }

    func makeUpdateBatch(matchIDs: [Int]) -> [OddsUpdateDTO] {
        guard !matchIDs.isEmpty else { return [] }

        let batchSize = Int.random(
            in: Constants.batchSizeRange.lowerBound...min(
                Constants.batchSizeRange.upperBound,
                matchIDs.count
            )
        )

        return matchIDs.shuffled().prefix(batchSize).map { matchID in
            OddsUpdateDTO(
                matchID: matchID,
                teamAOdds: makeRandomOdds(),
                teamBOdds: makeRandomOdds()
            )
        }
    }

    private func sendNextBatch() {
        let batch = makeUpdateBatch(matchIDs: connectedMatchIDs)
        guard !batch.isEmpty else { return }

        onReceiveOddsUpdates?(batch)
    }

    private func makeRandomOdds() -> Decimal {
        Decimal(Int.random(in: Constants.oddsCentsRange)) / Decimal(100)
    }
}
