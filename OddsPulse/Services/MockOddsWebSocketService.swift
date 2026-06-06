import Foundation

@MainActor
protocol OddsWebSocketServiceProtocol: AnyObject {
    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketServiceEvent>
    func disconnect()
}

enum OddsWebSocketServiceEvent: Equatable {
    case connected
    case reconnecting
    case oddsUpdated([OddsUpdate])
    case disconnected(reason: OddsWebSocketDisconnectReason)
    case failed(OddsWebSocketError)
}

@MainActor
final class MockOddsWebSocketService: OddsWebSocketServiceProtocol {
    private enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    private let webSocketClient: OddsWebSocketClientProtocol
    private let reconnectPolicy: ReconnectPolicy

    private var connectionState: ConnectionState = .disconnected
    private var connectionTask: Task<Void, Never>?
    private var eventsContinuation: AsyncStream<OddsWebSocketServiceEvent>.Continuation?
    private var reconnectAttempt = 0

    init(reconnectPolicy: ReconnectPolicy = .default) {
        webSocketClient = MockOddsWebSocketClient()
        self.reconnectPolicy = reconnectPolicy
    }

    init(
        webSocketClient: OddsWebSocketClientProtocol,
        reconnectPolicy: ReconnectPolicy = .default
    ) {
        self.webSocketClient = webSocketClient
        self.reconnectPolicy = reconnectPolicy
    }

    isolated deinit {
        disconnect()
    }

    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketServiceEvent> {
        disconnect()

        let streamPair = AsyncStream<OddsWebSocketServiceEvent>.makeStream(
            of: OddsWebSocketServiceEvent.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        eventsContinuation = streamPair.continuation
        reconnectAttempt = 0
        connectionState = .connecting

        connectionTask = Task { @MainActor [weak self] in
            await self?.runConnectionLoop(matchIDs: matchIDs)
        }

        return streamPair.stream
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        connectionState = .disconnected
        reconnectAttempt = 0
        webSocketClient.disconnect()
        eventsContinuation?.finish()
        eventsContinuation = nil
    }

    private func runConnectionLoop(matchIDs: [Int]) async {
        var shouldEmitReconnecting = false

        while !Task.isCancelled {
            if shouldEmitReconnecting {
                guard await waitForReconnectDelay() else { return }
                connectionState = .reconnecting
                eventsContinuation?.yield(.reconnecting)
            }

            connectionState = .connecting
            let clientEvents = webSocketClient.connect(matchIDs: matchIDs)
            let shouldReconnect = await receiveEvents(from: clientEvents)
            guard shouldReconnect else { return }

            guard reconnectPolicy.shouldRetry(afterAttempt: reconnectAttempt) else {
                connectionState = .disconnected
                eventsContinuation?.yield(.failed(.connectionFailed))
                eventsContinuation?.finish()
                eventsContinuation = nil
                return
            }

            reconnectAttempt += 1
            shouldEmitReconnecting = true
        }
    }

    private func receiveEvents(from clientEvents: AsyncStream<OddsWebSocketEvent>) async -> Bool {
        for await event in clientEvents {
            guard !Task.isCancelled else { return false }

            switch event {
            case .connected:
                connectionState = .connected
                eventsContinuation?.yield(.connected)
            case .reconnecting:
                connectionState = .reconnecting
                eventsContinuation?.yield(.reconnecting)
            case let .oddsUpdated(updates):
                eventsContinuation?.yield(.oddsUpdated(updates.map(\.domainUpdate)))
            case let .disconnected(reason):
                connectionState = .disconnected
                eventsContinuation?.yield(.disconnected(reason: reason))
                return reason == .streamEnded
            case let .failed(error):
                connectionState = .disconnected
                eventsContinuation?.yield(.failed(error))
                eventsContinuation?.finish()
                eventsContinuation = nil
                return false
            }
        }

        connectionState = .disconnected
        return true
    }

    private func waitForReconnectDelay() async -> Bool {
        let reconnectDelayNanoseconds = reconnectPolicy.delayNanoseconds(
            forAttempt: reconnectAttempt - 1
        )

        do {
            try await Task.sleep(nanoseconds: reconnectDelayNanoseconds)
            return true
        } catch {
            return false
        }
    }
}

private extension OddsUpdateDTO {
    var domainUpdate: OddsUpdate {
        OddsUpdate(
            matchID: matchID,
            teamAOdds: teamAOdds,
            teamBOdds: teamBOdds
        )
    }
}
