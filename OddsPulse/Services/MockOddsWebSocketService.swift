import Foundation

@MainActor
protocol OddsWebSocketServiceProtocol: AnyObject {
    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketEvent>
    func disconnect()
}

@MainActor
final class MockOddsWebSocketService: OddsWebSocketServiceProtocol {
    private let webSocketClient: OddsWebSocketClientProtocol

    init() {
        webSocketClient = MockOddsWebSocketClient()
    }

    init(webSocketClient: OddsWebSocketClientProtocol) {
        self.webSocketClient = webSocketClient
    }

    func connect(matchIDs: [Int]) -> AsyncStream<OddsWebSocketEvent> {
        webSocketClient.connect(matchIDs: matchIDs)
    }

    func disconnect() {
        webSocketClient.disconnect()
    }
}
