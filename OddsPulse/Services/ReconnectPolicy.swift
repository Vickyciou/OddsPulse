import Foundation

struct ReconnectPolicy: Equatable {
    nonisolated static let `default` = ReconnectPolicy(
        initialDelayNanoseconds: 1_000_000_000,
        maxDelayNanoseconds: 8_000_000_000,
        jitterRangeNanoseconds: 250_000_000,
        maxAttempts: 5
    )

    let initialDelayNanoseconds: UInt64
    let maxDelayNanoseconds: UInt64
    let jitterRangeNanoseconds: UInt64
    let maxAttempts: Int

    func delayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let multiplier = UInt64(1) << UInt64(max(0, min(attempt, 20)))
        let exponentialDelay = initialDelayNanoseconds.multipliedReportingOverflow(
            by: multiplier
        )
        let cappedDelay = min(
            exponentialDelay.overflow ? maxDelayNanoseconds : exponentialDelay.partialValue,
            maxDelayNanoseconds
        )

        guard jitterRangeNanoseconds > 0 else { return cappedDelay }

        return cappedDelay + UInt64.random(in: 0...jitterRangeNanoseconds)
    }

    func shouldRetry(afterAttempt attempt: Int) -> Bool {
        attempt < maxAttempts
    }
}
