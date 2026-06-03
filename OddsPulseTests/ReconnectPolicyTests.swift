import XCTest
@testable import OddsPulse

final class ReconnectPolicyTests: XCTestCase {
    func testDelayUsesExponentialBackoffCappedByMaxDelay() {
        let policy = ReconnectPolicy(
            initialDelayNanoseconds: 1_000_000_000,
            maxDelayNanoseconds: 4_000_000_000,
            jitterRangeNanoseconds: 0,
            maxAttempts: 5
        )

        XCTAssertEqual(policy.delayNanoseconds(forAttempt: 0), 1_000_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forAttempt: 1), 2_000_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forAttempt: 2), 4_000_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forAttempt: 3), 4_000_000_000)
    }

    func testShouldRetryUntilMaxAttemptsIsReached() {
        let policy = ReconnectPolicy(
            initialDelayNanoseconds: 1,
            maxDelayNanoseconds: 1,
            jitterRangeNanoseconds: 0,
            maxAttempts: 3
        )

        XCTAssertTrue(policy.shouldRetry(afterAttempt: 0))
        XCTAssertTrue(policy.shouldRetry(afterAttempt: 1))
        XCTAssertTrue(policy.shouldRetry(afterAttempt: 2))
        XCTAssertFalse(policy.shouldRetry(afterAttempt: 3))
    }
}
