import Foundation
import CoreServices

// MARK: - Session Activity State

enum SessionActivityState: String, Equatable {
    case idle
    case active
    case thinking
    case error

    /// Priority for state resolution (higher wins).
    var priority: Int {
        switch self {
        case .idle: return 0
        case .active: return 1
        case .thinking: return 2
        case .error: return 3
        }
    }
}

// MARK: - Session Activity Monitor

/// Monitors `~/.claude/projects/` for JSONL file changes and derives
/// the current `SessionActivityState` based on file modification times.
///
/// State logic:
/// - error: set externally via `reportError()`, clears after timeout
/// - thinking: most recent JSONL mtime within 30 seconds
/// - active: most recent JSONL mtime within 30s–5min
/// - idle: no recent updates (>5 min)
///
/// Priority: error > thinking > active > idle
final class SessionActivityMonitor {

    // MARK: - Configuration

    struct Thresholds {
        var thinkingInterval: TimeInterval = 30
        var activeInterval: TimeInterval = 300
        var errorTimeout: TimeInterval = 30
        var scanInterval: TimeInterval = 5
    }

    // MARK: - Public

    let thresholds: Thresholds
    private(set) var currentState: SessionActivityState = .idle
    var onStateChange: ((SessionActivityState) -> Void)?

    // MARK: - Internal State

    private let monitoredPath: String
    private var fsEventStream: FSEventStreamRef?
    private var scanTimer: Timer?
    private var errorExpiry: Date?

    /// Last known mtime of any JSONL file under the monitored path.
    /// Updated by FSEvents callback + periodic scan.
    private var latestJSONLMtime: Date = .distantPast

    // MARK: - Init

    init(
        monitoredPath: String? = nil,
        thresholds: Thresholds = Thresholds()
    ) {
        if let custom = monitoredPath {
            self.monitoredPath = custom
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.monitoredPath = (home as NSString).appendingPathComponent(".claude/projects")
        }
        self.thresholds = thresholds
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        startFSEventStream()
        startScanTimer()
        // Initial scan
        scanForLatestMtime()
        reevaluateState()
    }

    func stop() {
        stopFSEventStream()
        stopScanTimer()
    }

    // MARK: - External Error Reporting

    /// Report an error state. The error will auto-clear after `thresholds.errorTimeout`.
    func reportError(duration: TimeInterval? = nil) {
        let timeout = duration ?? thresholds.errorTimeout
        errorExpiry = Date().addingTimeInterval(timeout)
        reevaluateState()
    }

    /// Clear error state immediately.
    func clearError() {
        errorExpiry = nil
        reevaluateState()
    }

    // MARK: - State Evaluation (pure logic, testable)

    /// Determine state from inputs. This is a pure function for testability.
    static func evaluateState(
        latestMtime: Date,
        now: Date,
        errorExpiry: Date?,
        thresholds: Thresholds
    ) -> SessionActivityState {
        // Error takes highest priority
        if let expiry = errorExpiry, now < expiry {
            return .error
        }

        let elapsed = now.timeIntervalSince(latestMtime)

        if elapsed <= thresholds.thinkingInterval {
            return .thinking
        } else if elapsed <= thresholds.activeInterval {
            return .active
        } else {
            return .idle
        }
    }

    /// Re-evaluate and publish state if changed.
    func reevaluateState() {
        let newState = Self.evaluateState(
            latestMtime: latestJSONLMtime,
            now: Date(),
            errorExpiry: errorExpiry,
            thresholds: thresholds
        )
        if newState != currentState {
            currentState = newState
            onStateChange?(newState)
        }
    }

    // MARK: - FSEvents

    private func startFSEventStream() {
        guard fsEventStream == nil else { return }

        let pathsToWatch = [monitoredPath] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info = info else { return }
            let monitor = Unmanaged<SessionActivityMonitor>.fromOpaque(info).takeUnretainedValue()

            // Check if any event involves a .jsonl file
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let flags = UnsafeBufferPointer(start: eventFlags, count: numEvents)

            var hasJSONLChange = false
            for i in 0..<numEvents {
                let path = paths[i]
                // Skip item-removed events
                let itemRemoved = UInt32(kFSEventStreamEventFlagItemRemoved)
                if flags[i] & itemRemoved != 0 { continue }
                if path.hasSuffix(".jsonl") {
                    hasJSONLChange = true
                    break
                }
            }

            if hasJSONLChange {
                monitor.latestJSONLMtime = Date()
                DispatchQueue.main.async {
                    monitor.reevaluateState()
                }
            }
        }

        let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // latency: 1 second batch
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
            )
        )

        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
            self.fsEventStream = stream
        }
    }

    private func stopFSEventStream() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }

    // MARK: - Periodic Scan Timer

    private func startScanTimer() {
        guard scanTimer == nil else { return }
        scanTimer = Timer.scheduledTimer(
            withTimeInterval: thresholds.scanInterval,
            repeats: true
        ) { [weak self] _ in
            self?.reevaluateState()
        }
    }

    private func stopScanTimer() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - File System Scan

    /// Scan for the most recent .jsonl mtime under monitored path.
    /// Called once at startup to seed the initial state.
    private func scanForLatestMtime() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: monitoredPath) else { return }

        var latest: Date = .distantPast
        while let element = enumerator.nextObject() as? String {
            guard element.hasSuffix(".jsonl") else { continue }
            let fullPath = (monitoredPath as NSString).appendingPathComponent(element)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let mtime = attrs[.modificationDate] as? Date,
               mtime > latest {
                latest = mtime
            }
        }
        latestJSONLMtime = latest
    }

    // MARK: - Testing Support

    /// Inject a custom mtime for testing without file system.
    func _testSetLatestMtime(_ date: Date) {
        latestJSONLMtime = date
    }
}
