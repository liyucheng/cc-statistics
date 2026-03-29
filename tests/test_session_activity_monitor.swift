// Self-contained test harness for SessionActivityMonitor state machine.
// Compiles with swiftc alongside the main source files (no XCTest dependency).
// Run: swiftc <all swift files> tests/test_session_activity_monitor.swift -o /tmp/test_runner ...
// Note: Since the main app uses @main, this test file is meant to be compiled
// separately or with the main entry point excluded. See below for standalone mode.

import Foundation

// MARK: - Minimal Test Harness

private var totalTests = 0
private var passedTests = 0
private var failedTests: [(String, String)] = []  // (name, message)

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if a == b {
        passedTests += 1
    } else {
        let detail = msg.isEmpty ? "\(a) != \(b)" : "\(msg): \(a) != \(b)"
        failedTests.append(("line \(line)", detail))
    }
}

func assertNotEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if a != b {
        passedTests += 1
    } else {
        let detail = msg.isEmpty ? "\(a) == \(b) (expected different)" : "\(msg): \(a) == \(b)"
        failedTests.append(("line \(line)", detail))
    }
}

func assertTrue(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if condition {
        passedTests += 1
    } else {
        failedTests.append(("line \(line)", msg.isEmpty ? "expected true" : msg))
    }
}

func assertFalse(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    assertTrue(!condition, msg.isEmpty ? "expected false" : msg, file: file, line: line)
}

// MARK: - SessionActivityState Tests

func testPriorityOrder() {
    assertTrue(SessionActivityState.idle.priority < SessionActivityState.active.priority, "idle < active")
    assertTrue(SessionActivityState.active.priority < SessionActivityState.thinking.priority, "active < thinking")
    assertTrue(SessionActivityState.thinking.priority < SessionActivityState.error.priority, "thinking < error")
}

func testRawValues() {
    assertEqual(SessionActivityState.idle.rawValue, "idle")
    assertEqual(SessionActivityState.active.rawValue, "active")
    assertEqual(SessionActivityState.thinking.rawValue, "thinking")
    assertEqual(SessionActivityState.error.rawValue, "error")
}

func testEquality() {
    assertEqual(SessionActivityState.idle, SessionActivityState.idle)
    assertNotEqual(SessionActivityState.idle, SessionActivityState.active)
}

// MARK: - State Evaluation (Pure Logic) Tests

let defaultThresholds = SessionActivityMonitor.Thresholds()

func testIdleWhenNoRecentActivity() {
    let now = Date()
    let oldMtime = now.addingTimeInterval(-600)
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: oldMtime, now: now, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(state, .idle, "600s ago → idle")
}

func testIdleWhenPastActiveThreshold() {
    let now = Date()
    let mtime = now.addingTimeInterval(-301)
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: mtime, now: now, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(state, .idle, "301s ago → idle")
}

func testIdleWithDistantPast() {
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: .distantPast, now: Date(), errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(state, .idle, "distantPast → idle")
}

func testThinkingWhenVeryRecent() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-5), now: now, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(state, .thinking, "5s ago → thinking")
}

func testThinkingAtExactThreshold() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-30), now: now, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(state, .thinking, "30s ago → thinking (boundary)")
}

func testThinkingWhenMtimeIsNow() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now, now: now, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(state, .thinking, "now → thinking")
}

func testActiveWhenRecentButNotImmediate() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-60), now: now, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(state, .active, "60s ago → active")
}

func testActiveJustAfterThinkingThreshold() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-31), now: now, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(state, .active, "31s ago → active")
}

func testActiveAtBoundary() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-300), now: now, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(state, .active, "300s ago → active (boundary)")
}

func testErrorOverridesThinking() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-5), now: now,
        errorExpiry: now.addingTimeInterval(25), thresholds: defaultThresholds
    )
    assertEqual(state, .error, "error overrides thinking")
}

func testErrorOverridesActive() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-60), now: now,
        errorExpiry: now.addingTimeInterval(10), thresholds: defaultThresholds
    )
    assertEqual(state, .error, "error overrides active")
}

func testErrorOverridesIdle() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-600), now: now,
        errorExpiry: now.addingTimeInterval(5), thresholds: defaultThresholds
    )
    assertEqual(state, .error, "error overrides idle")
}

func testExpiredErrorFallsBackToActive() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-60), now: now,
        errorExpiry: now.addingTimeInterval(-1), thresholds: defaultThresholds
    )
    assertEqual(state, .active, "expired error → active")
}

func testExpiredErrorFallsBackToIdle() {
    let now = Date()
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-600), now: now,
        errorExpiry: now.addingTimeInterval(-1), thresholds: defaultThresholds
    )
    assertEqual(state, .idle, "expired error → idle")
}

// MARK: - Custom Thresholds

func testCustomThinkingThreshold() {
    let now = Date()
    let custom = SessionActivityMonitor.Thresholds(
        thinkingInterval: 5, activeInterval: 300, errorTimeout: 30, scanInterval: 5
    )
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-10), now: now, errorExpiry: nil, thresholds: custom
    )
    assertEqual(state, .active, "10s ago with 5s thinking → active")
}

func testCustomActiveThreshold() {
    let now = Date()
    let custom = SessionActivityMonitor.Thresholds(
        thinkingInterval: 30, activeInterval: 60, errorTimeout: 30, scanInterval: 5
    )
    let state = SessionActivityMonitor.evaluateState(
        latestMtime: now.addingTimeInterval(-120), now: now, errorExpiry: nil, thresholds: custom
    )
    assertEqual(state, .idle, "120s ago with 60s active → idle")
}

// MARK: - Transition Sequences

func testTransitionThinkingToActiveToIdle() {
    let base = Date()

    let s1 = SessionActivityMonitor.evaluateState(
        latestMtime: base, now: base, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(s1, .thinking, "t=0 → thinking")

    let s2 = SessionActivityMonitor.evaluateState(
        latestMtime: base, now: base.addingTimeInterval(31), errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(s2, .active, "t=31 → active")

    let s3 = SessionActivityMonitor.evaluateState(
        latestMtime: base, now: base.addingTimeInterval(301), errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(s3, .idle, "t=301 → idle")
}

func testErrorClearedReturnsToUnderlying() {
    let now = Date()
    let mtime = now.addingTimeInterval(-10)

    let s1 = SessionActivityMonitor.evaluateState(
        latestMtime: mtime, now: now,
        errorExpiry: now.addingTimeInterval(5), thresholds: defaultThresholds
    )
    assertEqual(s1, .error, "with error → error")

    let s2 = SessionActivityMonitor.evaluateState(
        latestMtime: mtime, now: now, errorExpiry: nil, thresholds: defaultThresholds
    )
    assertEqual(s2, .thinking, "error cleared → thinking")
}

// MARK: - Monitor Instance Tests

func testInitialStateIsIdle() {
    let monitor = SessionActivityMonitor(monitoredPath: "/tmp/nonexistent_test_path")
    assertEqual(monitor.currentState, .idle, "initial state = idle")
}

func testReportErrorSetsState() {
    let monitor = SessionActivityMonitor(monitoredPath: "/tmp/nonexistent_test_path")
    monitor.reportError(duration: 10)
    assertEqual(monitor.currentState, .error, "reportError → error")
}

func testClearErrorResetsState() {
    let monitor = SessionActivityMonitor(monitoredPath: "/tmp/nonexistent_test_path")
    monitor.reportError(duration: 10)
    assertEqual(monitor.currentState, .error)
    monitor.clearError()
    assertEqual(monitor.currentState, .idle, "clearError → idle")
}

func testStateChangeCallback() {
    let monitor = SessionActivityMonitor(monitoredPath: "/tmp/nonexistent_test_path")
    var received: [SessionActivityState] = []
    monitor.onStateChange = { received.append($0) }

    monitor.reportError(duration: 10)
    assertEqual(received.count, 1, "callback fired once")
    assertEqual(received.first ?? .idle, .error, "callback got error")

    monitor.clearError()
    assertEqual(received.count, 2, "callback fired twice")
    assertEqual(received.last ?? .error, .idle, "callback got idle")
}

func testInjectedMtimeAffectsState() {
    let monitor = SessionActivityMonitor(monitoredPath: "/tmp/nonexistent_test_path")

    monitor._testSetLatestMtime(Date().addingTimeInterval(-5))
    monitor.reevaluateState()
    assertEqual(monitor.currentState, .thinking, "injected 5s → thinking")

    monitor._testSetLatestMtime(Date().addingTimeInterval(-60))
    monitor.reevaluateState()
    assertEqual(monitor.currentState, .active, "injected 60s → active")

    monitor._testSetLatestMtime(Date().addingTimeInterval(-600))
    monitor.reevaluateState()
    assertEqual(monitor.currentState, .idle, "injected 600s → idle")
}

func testNoCallbackWhenUnchanged() {
    let monitor = SessionActivityMonitor(monitoredPath: "/tmp/nonexistent_test_path")
    var count = 0
    monitor.onStateChange = { _ in count += 1 }

    monitor.reevaluateState()  // still idle
    assertEqual(count, 0, "no callback when unchanged")

    monitor._testSetLatestMtime(Date().addingTimeInterval(-600))
    monitor.reevaluateState()  // still idle
    assertEqual(count, 0, "no callback when still idle")
}

func testCustomThresholdsArePersisted() {
    let custom = SessionActivityMonitor.Thresholds(
        thinkingInterval: 10, activeInterval: 120, errorTimeout: 60, scanInterval: 2
    )
    let monitor = SessionActivityMonitor(monitoredPath: "/tmp/test", thresholds: custom)
    assertEqual(monitor.thresholds.thinkingInterval, 10)
    assertEqual(monitor.thresholds.activeInterval, 120)
    assertEqual(monitor.thresholds.errorTimeout, 60)
    assertEqual(monitor.thresholds.scanInterval, 2)
}

// MARK: - Animation Config Tests

func testAllStatesHaveFrames() {
    for state in [SessionActivityState.idle, .active, .thinking, .error] {
        assertTrue(
            StatusBarController.animationFrames[state] != nil,
            "frames defined for \(state)"
        )
        assertFalse(
            StatusBarController.animationFrames[state]!.isEmpty,
            "frames non-empty for \(state)"
        )
    }
}

func testIdleHasSingleFrame() {
    assertEqual(StatusBarController.animationFrames[.idle]!.count, 1, "idle = 1 frame")
}

func testAnimatedStatesHaveMultipleFrames() {
    assertTrue(StatusBarController.animationFrames[.active]!.count > 1, "active animates")
    assertTrue(StatusBarController.animationFrames[.thinking]!.count > 1, "thinking animates")
}

func testErrorHasSingleFrame() {
    assertEqual(StatusBarController.animationFrames[.error]!.count, 1, "error = 1 frame")
}

func testStaticStatesHaveZeroInterval() {
    assertEqual(StatusBarController.frameIntervals[.idle], 0, "idle interval = 0")
    assertEqual(StatusBarController.frameIntervals[.error], 0, "error interval = 0")
}

func testAnimatedStatesHaveReasonableInterval() {
    let active = StatusBarController.frameIntervals[.active]!
    assertTrue(active >= 0.25 && active <= 0.5, "active interval in [0.25, 0.5]")
    let thinking = StatusBarController.frameIntervals[.thinking]!
    assertTrue(thinking >= 0.25 && thinking <= 0.5, "thinking interval in [0.25, 0.5]")
}

// MARK: - Runner

func runAllTests() {
    let tests: [(String, () -> Void)] = [
        // State enum
        ("testPriorityOrder", testPriorityOrder),
        ("testRawValues", testRawValues),
        ("testEquality", testEquality),
        // Evaluate: idle
        ("testIdleWhenNoRecentActivity", testIdleWhenNoRecentActivity),
        ("testIdleWhenPastActiveThreshold", testIdleWhenPastActiveThreshold),
        ("testIdleWithDistantPast", testIdleWithDistantPast),
        // Evaluate: thinking
        ("testThinkingWhenVeryRecent", testThinkingWhenVeryRecent),
        ("testThinkingAtExactThreshold", testThinkingAtExactThreshold),
        ("testThinkingWhenMtimeIsNow", testThinkingWhenMtimeIsNow),
        // Evaluate: active
        ("testActiveWhenRecentButNotImmediate", testActiveWhenRecentButNotImmediate),
        ("testActiveJustAfterThinkingThreshold", testActiveJustAfterThinkingThreshold),
        ("testActiveAtBoundary", testActiveAtBoundary),
        // Evaluate: error
        ("testErrorOverridesThinking", testErrorOverridesThinking),
        ("testErrorOverridesActive", testErrorOverridesActive),
        ("testErrorOverridesIdle", testErrorOverridesIdle),
        ("testExpiredErrorFallsBackToActive", testExpiredErrorFallsBackToActive),
        ("testExpiredErrorFallsBackToIdle", testExpiredErrorFallsBackToIdle),
        // Custom thresholds
        ("testCustomThinkingThreshold", testCustomThinkingThreshold),
        ("testCustomActiveThreshold", testCustomActiveThreshold),
        // Transitions
        ("testTransitionThinkingToActiveToIdle", testTransitionThinkingToActiveToIdle),
        ("testErrorClearedReturnsToUnderlying", testErrorClearedReturnsToUnderlying),
        // Monitor instance
        ("testInitialStateIsIdle", testInitialStateIsIdle),
        ("testReportErrorSetsState", testReportErrorSetsState),
        ("testClearErrorResetsState", testClearErrorResetsState),
        ("testStateChangeCallback", testStateChangeCallback),
        ("testInjectedMtimeAffectsState", testInjectedMtimeAffectsState),
        ("testNoCallbackWhenUnchanged", testNoCallbackWhenUnchanged),
        ("testCustomThresholdsArePersisted", testCustomThresholdsArePersisted),
        // Animation config
        ("testAllStatesHaveFrames", testAllStatesHaveFrames),
        ("testIdleHasSingleFrame", testIdleHasSingleFrame),
        ("testAnimatedStatesHaveMultipleFrames", testAnimatedStatesHaveMultipleFrames),
        ("testErrorHasSingleFrame", testErrorHasSingleFrame),
        ("testStaticStatesHaveZeroInterval", testStaticStatesHaveZeroInterval),
        ("testAnimatedStatesHaveReasonableInterval", testAnimatedStatesHaveReasonableInterval),
    ]

    print("Running \(tests.count) tests...\n")

    for (name, fn) in tests {
        let beforeFailed = failedTests.count
        fn()
        let status = failedTests.count == beforeFailed ? "PASS" : "FAIL"
        print("  [\(status)] \(name)")
    }

    print("\n\(passedTests)/\(totalTests) assertions passed.")
    if !failedTests.isEmpty {
        print("\nFailed:")
        for (loc, msg) in failedTests {
            print("  \(loc): \(msg)")
        }
        exit(1)
    } else {
        print("\nAll tests passed!")
        exit(0)
    }
}
