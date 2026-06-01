import Foundation

@MainActor
protocol OddsWebSocketClientProtocol: AnyObject {
    func connect(matchIDs: [Int]) -> AsyncStream<[OddsUpdateDTO]>
    func disconnect()
}

@MainActor
final class MockOddsWebSocketClient: OddsWebSocketClientProtocol {
    private enum Constants {
        static let interval: TimeInterval = 1
        static let batchSizeRange = 1...10
        static let oddsCentsRange = 100...500
    }

    private var timer: Timer?
    private var connectedMatchIDs: [Int] = []
    private var oddsUpdatesContinuation: AsyncStream<[OddsUpdateDTO]>.Continuation?

    isolated deinit {
        disconnect()
    }

    func connect(matchIDs: [Int]) -> AsyncStream<[OddsUpdateDTO]> {
        disconnect()

        let streamPair = AsyncStream<[OddsUpdateDTO]>.makeStream(
            of: [OddsUpdateDTO].self,
            bufferingPolicy: .bufferingNewest(1)
        )
        oddsUpdatesContinuation = streamPair.continuation

        connectedMatchIDs = Array(Set(matchIDs))
        guard !connectedMatchIDs.isEmpty else {
            streamPair.continuation.finish()
            return streamPair.stream
        }

        let timer = Timer(timeInterval: Constants.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendNextBatch()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        return streamPair.stream
    }

    func disconnect() {
        timer?.invalidate()
        timer = nil
        connectedMatchIDs = []
        oddsUpdatesContinuation?.finish()
        oddsUpdatesContinuation = nil
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

        oddsUpdatesContinuation?.yield(batch)
    }

    private func makeRandomOdds() -> Decimal {
        Decimal(Int.random(in: Constants.oddsCentsRange)) / Decimal(100)
    }
}
