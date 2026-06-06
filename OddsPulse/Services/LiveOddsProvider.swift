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
    private let recordsRepository: RecordsRepositoryProtocol
    private let oddsWebSocketService: OddsWebSocketServiceProtocol
    private let oddsStore: OddsStoreProtocol

    private var eventContinuations: [UUID: AsyncStream<LiveOddsEvent>.Continuation] = [:]
    private var refreshTask: Task<Void, Never>?
    private var liveUpdatesTask: Task<Void, Never>?

    init(
        recordsRepository: RecordsRepositoryProtocol? = nil,
        oddsWebSocketService: OddsWebSocketServiceProtocol? = nil,
        oddsStore: OddsStoreProtocol? = nil
    ) {
        self.recordsRepository = recordsRepository ?? RecordsRepository()
        self.oddsWebSocketService = oddsWebSocketService ?? MockOddsWebSocketService()
        self.oddsStore = oddsStore ?? OddsStore()
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
            let records = try await recordsRepository.fetchRecords()
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

        broadcast(.feedStatusChanged(.connecting))
        let events = oddsWebSocketService.connect(matchIDs: matchIDs)
        liveUpdatesTask = Task { @MainActor [weak self] in
            await self?.runLiveUpdates(events: events)
        }
    }

    private func runLiveUpdates(events: AsyncStream<OddsWebSocketServiceEvent>) async {
        defer {
            liveUpdatesTask = nil
        }

        for await event in events {
            guard !Task.isCancelled, hasSubscribers else { return }
            let shouldContinue = await handleWebSocketEvent(event)
            guard shouldContinue else { return }
        }
    }

    private func handleWebSocketEvent(_ event: OddsWebSocketServiceEvent) async -> Bool {
        switch event {
        case .connected:
            broadcast(.feedStatusChanged(.live))
            return true
        case .reconnecting:
            broadcast(.feedStatusChanged(.reconnecting))
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

    private func handleOddsUpdates(_ updates: [OddsUpdate]) async {
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
        oddsWebSocketService.disconnect()
    }

    private func send(_ event: LiveOddsEvent, to subscriberID: UUID) {
        eventContinuations[subscriberID]?.yield(event)
    }

    private func broadcast(_ event: LiveOddsEvent) {
        eventContinuations.values.forEach { $0.yield(event) }
    }
}
