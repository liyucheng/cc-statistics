import SwiftUI

struct GitLogStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logFilePath: String = ""
    @State private var dimension: GitLogStatsCollector.Dimension = .day
    @State private var stats: GitLogStatsResponse = .empty
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Text("Loading Git log statistics...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text(error)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // Summary Card
                        summaryCard

                        // Author Cards
                        ForEach(stats.authors) { author in
                            authorCard(author)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .navigationTitle("Git Log Statistics")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Dashboard")
                    }
                    .font(.caption)
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    loadStats()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            detectDefaultLogPath()
            loadStats()
        }
    }

    private var headerView: some View {
        VStack(spacing: 12) {
            // Log file input
            HStack {
                TextField("Log file path (.ai-usage.log)", text: $logFilePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))

                Button {
                    loadStats()
                } label: {
                    Text("Load")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 16)

            // Dimension selector
            Picker("Time Dimension", selection: $dimension) {
                ForEach(Array(GitLogStatsCollector.Dimension.allCases.enumerated()), id: \.offset) { _, dim in
                    Text(dim.displayName).tag(dim)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .onChange(of: dimension) { _ in
                loadStats()
            }
        }
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
    }

    private var summaryCard: some View {
        let totals = computeTotals()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Summary")
                    .font(.headline)
                Spacer()
                Text("\(stats.totalAuthors) authors")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                SummaryMetric(
                    label: "Total Tokens",
                    value: formatNumber(totals.tokens),
                    subtext: "\(totals.commits) commits",
                    color: .blue
                )

                SummaryMetric(
                    label: "Active Time",
                    value: formatDuration(totals.duration),
                    subtext: "\(totals.sessions) sessions",
                    color: .green
                )

                SummaryMetric(
                    label: "Code Lines",
                    value: formatNumber(totals.codeLines),
                    subtext: "changed",
                    color: .purple
                )

                SummaryMetric(
                    label: "Total Cost",
                    value: formatCost(totals.cost),
                    subtext: "",
                    color: .orange
                )
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func authorCard(_ author: AuthorStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author header
            HStack {
                Text(author.author)
                    .font(.headline)
                Spacer()

                let authorTotal = author.stats.reduce((commits: 0, tokens: 0, cost: 0.0)) { acc, stat in
                    (acc.commits + stat.commitCount,
                     acc.tokens + stat.tokens,
                     acc.cost + stat.cost)
                }

                Text("\(authorTotal.commits) commits • \(formatNumber(authorTotal.tokens)) tokens • \(formatCost(authorTotal.cost))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

            // Period table
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(dimension.displayName.prefix(1).uppercased() + dimension.displayName.dropFirst())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: 80, alignment: .leading)

                    Text("Commits")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 60, alignment: .trailing)

                    Text("Sessions")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 60, alignment: .trailing)

                    Text("Time")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 60, alignment: .trailing)

                    Text("Code")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 60, alignment: .trailing)

                    Text("Tokens")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 70, alignment: .trailing)

                    Text("Cost")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 60, alignment: .trailing)

                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.separatorColor).opacity(0.3))

                // Rows
                ForEach(author.stats) { stat in
                    HStack {
                        Text(stat.period)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: 80, alignment: .leading)

                        Text("\(stat.commitCount)")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)

                        Text("\(stat.sessions)")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)

                        Text(formatDuration(stat.durationSeconds))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)

                        let sign = stat.codeNet >= 0 ? "+" : ""
                        Text(sign + formatNumber(stat.codeNet))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(stat.codeNet >= 0 ? .green : .red)
                            .frame(width: 60, alignment: .trailing)

                        Text(formatNumber(stat.tokens))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 70, alignment: .trailing)

                        Text(formatCost(stat.cost))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    Divider()
                        .padding(.leading, 8)
                        .padding(.trailing, 8)
                }
            }
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private struct SummaryMetric: View {
        let label: String
        let value: String
        let subtext: String
        let color: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(color)

                if !subtext.isEmpty {
                    Text(subtext)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Data Loading
    private func detectDefaultLogPath() {
        // Try to detect common log file locations
        let possiblePaths = [
            ".ai-usage.log",
            "~/.ai-usage.log"
        ]

        for path in possiblePaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                logFilePath = expandedPath
                return
            }
        }
    }

    private func loadStats() {
        guard !logFilePath.isEmpty else {
            errorMessage = "Please specify a log file path"
            stats = .empty
            return
        }

        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let entries = GitLogStatsCollector.parseLogFile(at: self.logFilePath)

            DispatchQueue.main.async {
                if entries.isEmpty {
                    self.isLoading = false
                    self.errorMessage = "No valid log entries found in the file"
                    self.stats = GitLogStatsResponse(
                        logFile: self.logFilePath,
                        totalAuthors: 0,
                        authors: []
                    )
                    return
                }

                let authors = GitLogStatsCollector.aggregateByPeriod(
                    entries: entries,
                    dimension: self.dimension
                )

                self.stats = GitLogStatsResponse(
                    logFile: self.logFilePath,
                    totalAuthors: authors.count,
                    authors: authors
                )

                self.isLoading = false
            }
        }
    }

    // MARK: - Helpers

    private func computeTotals() -> (commits: Int, sessions: Int, duration: TimeInterval, codeLines: Int, tokens: Int, cost: Double) {
        var commits = 0
        var sessions = 0
        var duration: TimeInterval = 0
        var codeLines = 0
        var tokens = 0
        var cost = 0.0

        for author in stats.authors {
            for stat in author.stats {
                commits += stat.commitCount
                sessions += stat.sessions
                duration += stat.durationSeconds
                codeLines += abs(stat.codeNet)
                tokens += stat.tokens
                cost += stat.cost
            }
        }

        return (commits, sessions, duration, codeLines, tokens, cost)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return n.formatted()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatCost(_ cost: Double) -> String {
        if cost >= 100 {
            return String(format: "$%.0f", cost)
        } else if cost >= 1 {
            return String(format: "$%.2f", cost)
        } else if cost >= 0.01 {
            return String(format: "$%.3f", cost)
        }
        return String(format: "$%.4f", cost)
    }
}
