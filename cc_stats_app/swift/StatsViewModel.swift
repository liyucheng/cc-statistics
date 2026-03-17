import Foundation
import SwiftUI
import Combine

// MARK: - TimeFilter

enum TimeFilter: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return L10n.today
        case .week: return L10n.week
        case .month: return L10n.month
        case .all: return L10n.allTime
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .all:
            return nil
        }
    }
}

// MARK: - StatsViewModel

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var projects: [ProjectInfo] = []
    @Published var selectedProject: ProjectInfo?
    @Published var timeFilter: TimeFilter = .today
    @Published var stats: SessionStats?
    @Published var isLoading = false
    @Published var lastRefreshed: Date?
    @Published var recentSessions: [Session] = []
    @Published var showConversationPanel: Bool = false
    @Published var cursorStats: CursorStats?
    @Published var activeTab: StatsTab = .claudeCode
    @Published var todayTokens: Int = 0

    enum StatsTab: String, CaseIterable {
        case claudeCode = "Claude Code"
        case cursor = "Cursor"
    }

    private var refreshTimer: Timer?

    init() {
        startAutoRefresh()
        Task {
            await performRefresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Public Methods

    func refresh() {
        Task {
            await performRefresh()
        }
    }

    struct RefreshResult {
        let projects: [ProjectInfo]
        let stats: SessionStats
        let recentSessions: [Session]
        let todayTokens: Int
    }

    func performRefresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let currentFilter = timeFilter
        let currentProject = selectedProject

        let result: RefreshResult = await Task.detached(priority: .userInitiated) {
            let parser = SessionParser()
            let loadedProjects = parser.findAllProjects()

            // 获取全部会话（用于 todayTokens 计算）
            let allSessions: [Session]
            if let project = currentProject {
                allSessions = parser.parseSessions(forProject: project.path)
            } else {
                allSessions = parser.parseAllSessions()
            }

            // 按时间范围过滤（用于面板展示）
            var filteredSessions = allSessions
            if let startDate = currentFilter.startDate {
                filteredSessions = allSessions.filter { session in
                    session.messages.contains { message in
                        if let ts = message.timestamp {
                            return ts >= startDate
                        }
                        return false
                    }
                }
            }

            let stats = SessionAnalyzer.analyze(sessions: filteredSessions)
            let recent = filteredSessions
                .sorted(by: { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) })
                .prefix(20).map { $0 }

            // 计算当天 token（从同一批数据中过滤，保证同步）
            let todayStart = Calendar.current.startOfDay(for: Date())
            let todaySessions = allSessions.filter { session in
                session.messages.contains { $0.timestamp.map { $0 >= todayStart } ?? false }
            }
            let todayStats = SessionAnalyzer.analyze(sessions: todaySessions)

            return RefreshResult(
                projects: loadedProjects,
                stats: stats,
                recentSessions: recent,
                todayTokens: todayStats.totalTokens
            )
        }.value

        self.projects = result.projects
        self.stats = result.stats
        self.recentSessions = result.recentSessions
        self.todayTokens = result.todayTokens

        // Also parse Cursor stats
        let cursorSince = currentFilter.startDate
        let cursorResult: CursorStats = await Task.detached(priority: .userInitiated) {
            CursorParser.parse(since: cursorSince)
        }.value
        self.cursorStats = cursorResult

        self.lastRefreshed = Date()
    }

    func selectProject(_ project: ProjectInfo?) {
        selectedProject = project
        Task {
            await performRefresh()
        }
    }

    func setTimeFilter(_ filter: TimeFilter) {
        timeFilter = filter
        Task {
            await performRefresh()
        }
    }

    func toggleConversationPanel() {
        showConversationPanel.toggle()
    }

    // MARK: - Private Methods

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
    }
}
