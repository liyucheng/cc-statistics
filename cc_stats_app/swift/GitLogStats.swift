import Foundation

// MARK: - Git Log Entry

struct GitLogEntry: Identifiable {
    let id = UUID()
    let commitHash: String
    let author: String
    let timestamp: Date
    let message: String
    let additions: Int
    let deletions: Int
    let tokens: Int
    let duration: TimeInterval

    var netCodeChange: Int {
        additions - deletions
    }
}

// MARK: - Author Stats

struct AuthorStats: Identifiable, Codable {
    let id = UUID()
    let author: String
    var stats: [PeriodStats]

    enum CodingKeys: String, CodingKey {
        case author, stats
    }

    init(author: String, stats: [PeriodStats]) {
        self.author = author
        self.stats = stats
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decode(String.self, forKey: .author)
        stats = try container.decode([PeriodStats].self, forKey: .stats)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(author, forKey: .author)
        try container.encode(stats, forKey: .stats)
    }
}

// MARK: - Period Stats

struct PeriodStats: Identifiable, Codable {
    let id = UUID()
    let period: String
    var commitCount: Int
    var sessions: Int
    var durationSeconds: TimeInterval
    var tokens: Int
    var cost: Double
    var codeAdded: Int
    var codeRemoved: Int

    enum CodingKeys: String, CodingKey {
        case period, commitCount, sessions, durationSeconds, tokens, cost, codeAdded, codeRemoved
    }

    var codeNet: Int {
        codeAdded - codeRemoved
    }

    init(period: String) {
        self.period = period
        self.commitCount = 0
        self.sessions = 0
        self.durationSeconds = 0
        self.tokens = 0
        self.cost = 0.0
        self.codeAdded = 0
        self.codeRemoved = 0
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        period = try container.decode(String.self, forKey: .period)
        commitCount = try container.decode(Int.self, forKey: .commitCount)
        sessions = try container.decode(Int.self, forKey: .sessions)
        durationSeconds = try container.decode(TimeInterval.self, forKey: .durationSeconds)
        tokens = try container.decode(Int.self, forKey: .tokens)
        cost = try container.decode(Double.self, forKey: .cost)
        codeAdded = try container.decode(Int.self, forKey: .codeAdded)
        codeRemoved = try container.decode(Int.self, forKey: .codeRemoved)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(period, forKey: .period)
        try container.encode(commitCount, forKey: .commitCount)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(cost, forKey: .cost)
        try container.encode(codeAdded, forKey: .codeAdded)
        try container.encode(codeRemoved, forKey: .codeRemoved)
    }
}

// MARK: - Git Log Stats Response

struct GitLogStatsResponse: Codable {
    let logFile: String
    let totalAuthors: Int
    let authors: [AuthorStats]
    let error: String?

    init(logFile: String, totalAuthors: Int, authors: [AuthorStats], error: String? = nil) {
        self.logFile = logFile
        self.totalAuthors = totalAuthors
        self.authors = authors
        self.error = error
    }

    static let empty = GitLogStatsResponse(
        logFile: "",
        totalAuthors: 0,
        authors: [],
        error: nil
    )
}

// MARK: - Git Log Stats Collector

enum GitLogStatsCollector {

    /// 从 Git 使用日志文件中读取所有条目
    static func parseLogFile(at path: String) -> [GitLogEntry] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        var entries: [GitLogEntry] = []

        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            if let entry = parseLogLine(line) {
                entries.append(entry)
            }
        }

        return entries
    }

    /// 解析单行日志
    private static func parseLogLine(_ line: String) -> GitLogEntry? {
        // 日志格式: timestamp|author|commit_hash|additions|deletions|tokens|duration|message
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)

        guard parts.count >= 8 else { return nil }

        let timestampStr = parts[0].trimmingCharacters(in: .whitespaces)
        let author = parts[1].trimmingCharacters(in: .whitespaces)
        let commitHash = parts[2].trimmingCharacters(in: .whitespaces)
        let additions = Int(parts[3].trimmingCharacters(in: .whitespaces)) ?? 0
        let deletions = Int(parts[4].trimmingCharacters(in: .whitespaces)) ?? 0
        let tokens = Int(parts[5].trimmingCharacters(in: .whitespaces)) ?? 0
        let duration = TimeInterval(parts[6].trimmingCharacters(in: .whitespaces)) ?? 0
        let message = parts.count > 7 ? parts[7...].joined(separator: "|").trimmingCharacters(in: .whitespaces) : ""

        let dateFormatter = ISO8601DateFormatter()
        guard let timestamp = dateFormatter.date(from: timestampStr) else { return nil }

        return GitLogEntry(
            commitHash: commitHash,
            author: author,
            timestamp: timestamp,
            message: message,
            additions: additions,
            deletions: deletions,
            tokens: tokens,
            duration: duration
        )
    }

    /// 按时间段聚合统计
    static func aggregateByPeriod(
        entries: [GitLogEntry],
        dimension: Dimension
    ) -> [AuthorStats] {
        let calendar = Calendar.current

        var authorMap: [String: [String: PeriodStats]] = [:]

        for entry in entries {
            let period: String
            switch dimension {
            case .day:
                let day = calendar.startOfDay(for: entry.timestamp)
                period = formatDate(day, format: "MM-dd")
            case .week:
                let weekStart = getWeekStart(for: entry.timestamp)
                period = formatDate(weekStart, format: "yyyy-'W'ww")
            case .month:
                let month = calendar.startOfMonth(for: entry.timestamp)
                period = formatDate(month, format: "yyyy-MM")
            }

            var authorPeriodMap = authorMap[entry.author, default: [:]]

            var periodStats = authorPeriodMap[period, default: PeriodStats(period: period)]
            periodStats.commitCount += 1
            periodStats.sessions += 1
            periodStats.durationSeconds += entry.duration
            periodStats.tokens += entry.tokens
            periodStats.codeAdded += entry.additions
            periodStats.codeRemoved += entry.deletions
            periodStats.cost += estimateCost(tokens: entry.tokens)

            authorPeriodMap[period] = periodStats
            authorMap[entry.author] = authorPeriodMap
        }

        let authors: [AuthorStats] = authorMap.map { (author, periodMap) in
            let sortedStats = periodMap.values.sorted { $0.period > $1.period }
            return AuthorStats(author: author, stats: sortedStats)
        }.sorted { $0.author < $1.author }

        return authors
    }

    /// 获取周的开始日期（周一）
    private static func getWeekStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components)!
    }

    /// 格式化日期
    private static func formatDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// 简单估算成本（基于每 1000 tokens $0.003）
    private static func estimateCost(tokens: Int) -> Double {
        Double(tokens) / 1000.0 * 0.003
    }

    enum Dimension: String, CaseIterable {
        case day = "day"
        case week = "week"
        case month = "month"

        var displayName: String {
            switch self {
            case .day: return "Daily"
            case .week: return "Weekly"
            case .month: return "Monthly"
            }
        }
    }
}

// MARK: - Calendar Extensions

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components)!
    }
}
