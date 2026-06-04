import Foundation

@MainActor
protocol LiveOddsProviderProtocol: Sendable {
    func stream() -> AsyncStream<LiveOddsEvent>
}

enum LiveOddsEvent: Equatable {
    case loading
    case recordsLoaded([MatchRecord])
    case oddsUpdated(changedRecords: [MatchRecord])
    case feedStatusChanged(LiveOddsFeedStatus)
    case refreshFailed(message: String)
}

enum LiveOddsFeedStatus: Equatable {
    case idle
    case connecting
    case live
    case reconnecting
    case unavailable(message: String)
}

@MainActor
final class LiveOddsProvider: LiveOddsProviderProtocol {
    private let matchesService: MatchesServiceProtocol
    private let oddsService: OddsServiceProtocol
    private let oddsWebSocketClient: OddsWebSocketClientProtocol
    private let oddsStore: OddsStoreProtocol
    private let reconnectPolicy: ReconnectPolicy

    private var eventContinuations: [UUID: AsyncStream<LiveOddsEvent>.Continuation] = [:]
    private var refreshTask: Task<Void, Never>?
    private var liveUpdatesTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    init(
        matchesService: MatchesServiceProtocol? = nil,
        oddsService: OddsServiceProtocol? = nil,
        oddsWebSocketClient: OddsWebSocketClientProtocol? = nil,
        oddsStore: OddsStoreProtocol? = nil,
        reconnectPolicy: ReconnectPolicy = .default
    ) {
        self.matchesService = matchesService ?? MockMatchesService()
        self.oddsService = oddsService ?? MockOddsService()
        self.oddsWebSocketClient = oddsWebSocketClient ?? MockOddsWebSocketClient()
        self.oddsStore = oddsStore ?? OddsStore()
        self.reconnectPolicy = reconnectPolicy
    }

    isolated deinit {
        stopLiveUpdates()
        refreshTask?.cancel()
        eventContinuations.values.forEach { $0.finish() }
    }

    func stream() -> AsyncStream<LiveOddsEvent> {
        let subscriberID = UUID()
        let streamPair = AsyncStream<LiveOddsEvent>.makeStream(
            of: LiveOddsEvent.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        eventContinuations[subscriberID] = streamPair.continuation
        streamPair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeSubscriber(id: subscriberID)
            }
        }

        Task { @MainActor [weak self] in
            await self?.prepareStream(for: subscriberID)
        }

        return streamPair.stream
    }

    private func prepareStream(for subscriberID: UUID) async {
        let snapshotRecords = await oddsStore.snapshot()
        if !snapshotRecords.isEmpty {
            send(.recordsLoaded(snapshotRecords), to: subscriberID)
            startLiveUpdatesIfNeeded(matchIDs: snapshotRecords.map(\.matchID))
        } else {
            send(.loading, to: subscriberID)
        }

        startRefreshIfNeeded()
    }

    private func startRefreshIfNeeded() {
        guard refreshTask == nil else { return }

        refreshTask = Task { @MainActor [weak self] in
            await self?.refreshRecords()
        }
    }

    private func refreshRecords() async {
        defer {
            refreshTask = nil
        }

        do {
            async let matches = matchesService.fetchMatches()
            async let odds = oddsService.fetchInitialOdds()

            let records = try MatchRecordMapper.makeRecords(
                matches: try await matches,
                odds: try await odds
            )
            await oddsStore.replaceRecords(records)
            broadcast(.recordsLoaded(records))
            startLiveUpdatesIfNeeded(matchIDs: records.map(\.matchID))
        } catch is CancellationError {
            return
        } catch {
            broadcast(.refreshFailed(message: "Unable to load matches"))
        }
    }

    private func startLiveUpdatesIfNeeded(matchIDs: [Int]) {
        guard liveUpdatesTask == nil else { return }

        reconnectAttempt = 0
        broadcast(.feedStatusChanged(.connecting))
        let initialEvents = oddsWebSocketClient.connect(matchIDs: matchIDs)
        liveUpdatesTask = Task { @MainActor [weak self] in
            await self?.runLiveUpdates(matchIDs: matchIDs, initialEvents: initialEvents)
        }
    }

    private func runLiveUpdates(
        matchIDs: [Int],
        initialEvents: AsyncStream<OddsWebSocketEvent>
    ) async {
        defer {
            liveUpdatesTask = nil
        }

        var events: AsyncStream<OddsWebSocketEvent>? = initialEvents

        while !Task.isCancelled && hasSubscribers {
            let currentEvents = events ?? oddsWebSocketClient.connect(matchIDs: matchIDs)
            events = nil

            for await event in currentEvents {
                guard !Task.isCancelled, hasSubscribers else { return }
                let shouldContinue = await handleWebSocketEvent(event)
                guard shouldContinue else { return }
            }

            guard !Task.isCancelled, hasSubscribers else { return }
            guard reconnectPolicy.shouldRetry(afterAttempt: reconnectAttempt) else {
                broadcast(.feedStatusChanged(.unavailable(message: "Live odds unavailable")))
                return
            }

            broadcast(.feedStatusChanged(.reconnecting))
            let reconnectDelayNanoseconds = reconnectPolicy.delayNanoseconds(
                forAttempt: reconnectAttempt
            )
            reconnectAttempt += 1

            do {
                try await Task.sleep(nanoseconds: reconnectDelayNanoseconds)
            } catch {
                return
            }
        }
    }

    private func handleWebSocketEvent(_ event: OddsWebSocketEvent) async -> Bool {
        switch event {
        case .connected:
            reconnectAttempt = 0
            broadcast(.feedStatusChanged(.live))
            return true
        case let .oddsUpdated(updates):
            await handleOddsUpdates(updates)
            return true
        case let .disconnected(reason):
            return handleDisconnect(reason)
        case .failed:
            broadcast(.feedStatusChanged(.unavailable(message: "Live odds unavailable")))
            return false
        }
    }

    private func handleOddsUpdates(_ updates: [OddsUpdateDTO]) async {
        let result = await oddsStore.applyOddsUpdates(updates)
        guard !result.changedRecords.isEmpty else { return }

        broadcast(.oddsUpdated(changedRecords: result.changedRecords))
    }

    private func handleDisconnect(_ reason: OddsWebSocketDisconnectReason) -> Bool {
        switch reason {
        case .manual:
            return false
        case .noMatchIDs:
            broadcast(.feedStatusChanged(.unavailable(message: "No matches available for live odds")))
            return false
        case .streamEnded:
            return true
        }
    }

    private func removeSubscriber(id: UUID) {
        eventContinuations[id] = nil

        guard eventContinuations.isEmpty else { return }

        refreshTask?.cancel()
        refreshTask = nil
        stopLiveUpdates()
    }

    private var hasSubscribers: Bool {
        !eventContinuations.isEmpty
    }

    private func stopLiveUpdates() {
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        oddsWebSocketClient.disconnect()
        reconnectAttempt = 0
    }

    private func send(_ event: LiveOddsEvent, to subscriberID: UUID) {
        eventContinuations[subscriberID]?.yield(event)
    }

    private func broadcast(_ event: LiveOddsEvent) {
        eventContinuations.values.forEach { $0.yield(event) }
    }
}
