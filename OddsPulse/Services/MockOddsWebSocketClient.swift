import Foundation

@MainActor
protocol OddsWebSocketClientProtocol: AnyObject {
    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketEvent>
    func disconnect()
}

enum OddsWebSocketEvent: Equatable {
    case connected
    case reconnecting
    case oddsUpdated([OddsUpdateDTO])
    case disconnected(reason: OddsWebSocketDisconnectReason)
    case failed(OddsWebSocketError)
}

enum OddsWebSocketDisconnectReason: Equatable {
    case noMatchIDs
    case manual
    case streamEnded
}

enum OddsWebSocketError: Error, Equatable {
    case connectionFailed
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
    private var eventsContinuation: AsyncStream<OddsWebSocketEvent>.Continuation?

    isolated deinit {
        disconnect()
    }

    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketEvent> {
        disconnect()

        let streamPair = AsyncStream<OddsWebSocketEvent>.makeStream(
            of: OddsWebSocketEvent.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        eventsContinuation = streamPair.continuation

        connectedMatchIDs = Array(Set(matchIDs))
        guard !connectedMatchIDs.isEmpty else {
            streamPair.continuation.yield(.disconnected(reason: .noMatchIDs))
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
        streamPair.continuation.yield(.connected)

        return streamPair.stream
    }

    func disconnect() {
        timer?.invalidate()
        timer = nil
        connectedMatchIDs = []
        eventsContinuation?.yield(.disconnected(reason: .manual))
        eventsContinuation?.finish()
        eventsContinuation = nil
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

        eventsContinuation?.yield(.oddsUpdated(batch))
    }

    private func makeRandomOdds() -> Decimal {
        Decimal(Int.random(in: Constants.oddsCentsRange)) / Decimal(100)
    }
}
