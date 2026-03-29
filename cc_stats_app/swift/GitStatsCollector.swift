import Foundation

// MARK: - Git Stats Result

struct GitStatsResult: Equatable {
    let commits: Int
    let additions: Int
    let deletions: Int

    static let zero = GitStatsResult(commits: 0, additions: 0, deletions: 0)
}

// MARK: - Git Stats Collector

/// Lazily collects git commit statistics for sessions by running `git log` in the background.
/// Results are cached by session file path to avoid redundant subprocess calls.
final class GitStatsCollector {

    static let shared = GitStatsCollector()

    private let queue = DispatchQueue(label: "cc-stats.git-collector", attributes: .concurrent)
    private var cache: [String: GitStatsResult] = [:]
    private var inFlight: Set<String> = []
    private let lock = NSLock()

    private init() {}

    // MARK: - Public API

    /// Collect git stats for a session asynchronously.
    /// Calls `completion` on the main queue when done.
    /// Silently returns `.zero` for sessions without a project path, without `.git`, or on error.
    func collect(
        for session: Session,
        completion: @escaping (String, GitStatsResult) -> Void
    ) {
        let key = session.filePath

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            DispatchQueue.main.async { completion(key, cached) }
            return
        }
        if inFlight.contains(key) {
            lock.unlock()
            return
        }
        inFlight.insert(key)
        lock.unlock()

        guard let projectPath = session.projectPath,
              let startTime = session.startTime,
              let endTime = session.endTime else {
            let result = GitStatsResult.zero
            storeAndComplete(key: key, result: result, completion: completion)
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            let result = self.runGitLog(projectPath: projectPath, start: startTime, end: endTime)
            self.storeAndComplete(key: key, result: result, completion: completion)
        }
    }

    /// Returns cached result for a session, or nil if not yet collected.
    func cached(for session: Session) -> GitStatsResult? {
        lock.lock()
        defer { lock.unlock() }
        return cache[session.filePath]
    }

    /// Clear all cached results (e.g. on full refresh).
    func clearCache() {
        lock.lock()
        cache.removeAll()
        inFlight.removeAll()
        lock.unlock()
    }

    // MARK: - Internal (visible for testing)

    /// Parse `git log --numstat` output into a GitStatsResult.
    /// Exposed as internal for unit testing.
    static func parseGitLogOutput(_ output: String) -> GitStatsResult {
        var commits = 0
        var totalAdded = 0
        var totalRemoved = 0

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Commit separator line: \x00<40-char hash>\n...\x00
            if trimmed.contains("\0") {
                let clean = trimmed.replacingOccurrences(of: "\0", with: "")
                // A hash line has >= 40 hex chars
                if clean.count >= 40 {
                    commits += 1
                }
                continue
            }

            // numstat line: <added>\t<removed>\t<filepath>
            let parts = trimmed.components(separatedBy: "\t")
            if parts.count == 3 {
                guard let added = Int(parts[0]), let removed = Int(parts[1]) else { continue }
                totalAdded += added
                totalRemoved += removed
            }
        }

        return GitStatsResult(commits: commits, additions: totalAdded, deletions: totalRemoved)
    }

    // MARK: - Private

    private func storeAndComplete(
        key: String,
        result: GitStatsResult,
        completion: @escaping (String, GitStatsResult) -> Void
    ) {
        lock.lock()
        cache[key] = result
        inFlight.remove(key)
        lock.unlock()
        DispatchQueue.main.async { completion(key, result) }
    }

    private func runGitLog(projectPath: String, start: Date, end: Date) -> GitStatsResult {
        // Check .git exists (regular dir or gitlink file for worktrees)
        let gitPath = (projectPath as NSString).appendingPathComponent(".git")
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: gitPath, isDirectory: &isDir)
        guard exists else { return .zero }

        // Expand time window by 1 minute on each side to avoid boundary misses
        let startExpanded = start.addingTimeInterval(-60)
        let endExpanded = end.addingTimeInterval(60)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let sinceStr = formatter.string(from: startExpanded)
        let untilStr = formatter.string(from: endExpanded)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "log",
            "--numstat",
            "--format=%x00%H%n%B%x00",
            "--since=\(sinceStr)",
            "--until=\(untilStr)",
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.qualityOfService = .background

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .zero
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return .zero
        }

        return Self.parseGitLogOutput(output)
    }
}
