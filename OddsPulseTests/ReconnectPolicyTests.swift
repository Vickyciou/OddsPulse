import XCTest
@testable import OddsPulse

final class ReconnectPolicyTests: XCTestCase {
    func testDelayUsesExponentialBackoffCappedByMaxDelay() {
        let policy = ReconnectPolicy(
            initialDelayNanoseconds: 1_000_000_000,
            maxDelayNanoseconds: 4_000_000_000,
            jitterRangeNanoseconds: 0
        )

        XCTAssertEqual(policy.delayNanoseconds(forAttempt: 0), 1_000_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forAttempt: 1), 2_000_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forAttempt: 2), 4_000_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forAttempt: 3), 4_000_000_000)
    }
}
