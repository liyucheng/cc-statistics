import SwiftUI
import AppKit
import WebKit

private enum ShareExportPreset: String, CaseIterable, Identifiable {
    case balanced
    case x
    case linkedIn
    case slack
    case telegram

    var id: String { rawValue }

    var cardWidth: CGFloat {
        switch self {
        case .balanced: return 680
        case .x: return 540
        case .linkedIn: return 720
        case .slack: return 760
        case .telegram: return 800
        }
    }

    var scale: CGFloat {
        switch self {
        case .balanced: return 2.5
        case .x, .linkedIn, .slack, .telegram: return 2.0
        }
    }

    var maxPagePixelHeight: Int {
        switch self {
        case .balanced: return 2200
        case .x: return 1350
        case .linkedIn: return 1800
        case .slack: return 2400
        case .telegram: return 3000
        }
    }

    var slug: String { rawValue.lowercased() }

    var label: String {
        switch self {
        case .balanced:
            return L10n.isChinese ? "通用高清" : "Balanced"
        case .x:
            return "X"
        case .linkedIn:
            return "LinkedIn"
        case .slack:
            return "Slack"
        case .telegram:
            return "Telegram"
        }
    }
}

// MARK: - ConversationView

struct ConversationView: View {
    @ObservedObject var viewModel: StatsViewModel
    var onClose: () -> Void

    @State private var selectedSession: Session?
    @State private var toastMessage: String?
    @State private var searchText: String = ""
    @State private var isSelectMode = false
    @State private var selectedMessageIDs: Set<UUID> = []
    @State private var sharePreset: ShareExportPreset = .balanced
    @State private var isExportingShare = false
    private var sessions: [Session] { viewModel.conversationSessions }
    private var isLoading: Bool { viewModel.isConversationLoading }

    private var filteredSessions: [Session] {
        let base: [Session]
        if searchText.isEmpty {
            base = sessions
        } else {
            let query = searchText.lowercased()
            base = sessions.filter { session in
                if session.sessionName.lowercased().contains(query) { return true }
                if let project = session.projectPath, project.lowercased().contains(query) { return true }
                return session.messages.contains { msg in
                    !msg.content.isEmpty && msg.content.lowercased().contains(query)
                }
            }
        }
        return base
    }

    var body: some View {
        ZStack {
            HSplitView {
                // Session list
                sessionList
                    .frame(minWidth: 160, idealWidth: 180)

                // Message detail
                if let session = selectedSession {
                    messageDetail(session: session)
                        .frame(minWidth: 220)
                } else {
                    emptySelection
                        .frame(minWidth: 220)
                }
            }

            // Toast overlay
            if let msg = toastMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.green.opacity(0.9))
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 16)
                }
                .animation(.easeInOut(duration: 0.25), value: toastMessage != nil)
            }
        }
        .frame(minWidth: 420, minHeight: 400)
        .background(Theme.background)
        .onAppear {
            selectedSession = sessions.first
        }
        .onChange(of: sessions.map(\.filePath)) { _ in
            guard let selected = selectedSession else {
                selectedSession = sessions.first
                return
            }
            if let updated = sessions.first(where: { $0.filePath == selected.filePath }) {
                selectedSession = updated
            } else {
                selectedSession = sessions.first
            }
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.sessionList)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
                Spacer()
                Text("\(filteredSessions.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.cardBackground)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                TextField(L10n.search, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            Divider().background(Theme.border)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    ForEach(filteredSessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Theme.background)
    }

    private func sessionRow(_ session: Session) -> some View {
        let isSelected = selectedSession?.id == session.id
        let userMessages = session.messages.filter { $0.role == "human" || $0.role == "user" }
        let preview = userMessages.first(where: { !$0.content.isEmpty }).map { String($0.content.prefix(80)) }
            ?? String(session.sessionName.prefix(80))

        return Button {
            selectedSession = session
            // 切换会话时退出选择模式
            isSelectMode = false
            selectedMessageIDs.removeAll()

            // Copy resume command
            let cmd = "claude --resume \"\(session.sessionName)\""
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)

            withAnimation {
                toastMessage = "\(L10n.copied): claude --resume"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    toastMessage = nil
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let start = session.startTime {
                        HStack(spacing: 4) {
                            Text(start, style: .date)
                            Text(start, style: .time)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? Theme.cyan : Theme.textSecondary)
                    }
                    Spacer()
                    if let dur = formattedDuration(session.duration) {
                        Text(dur)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                    }
                }

                Text(preview)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(session.sessionName.prefix(8) + "...")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textTertiary.opacity(0.6))

                    Spacer()

                    Label("\(userMessages.count)", systemImage: "text.bubble")
                    Label("\(session.messages.count)", systemImage: "message")

                    // Context usage badge
                    let ctxPct = session.contextUsagePercent
                    if ctxPct > 0 {
                        let ctxColor = ctxPct >= 80 ? Theme.red : ctxPct >= 50 ? Theme.amber : Theme.green
                        Text(String(format: "ctx %.0f%%", ctxPct))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(ctxColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(ctxColor.opacity(0.15))
                            )
                    }
                }
                .font(.system(size: 9))
                .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Theme.cyan.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    // MARK: - Message Detail

    private func messageDetail(session: Session) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let start = session.startTime {
                        Text(start, format: .dateTime.month().day().hour().minute())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                    }
                    Text("\(session.messages.count) \(L10n.messagesCount)")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                }
                // Context usage indicator
                let ctxPct = session.contextUsagePercent
                if ctxPct > 0 {
                    let ctxColor = ctxPct >= 80 ? Theme.red : ctxPct >= 50 ? Theme.amber : Theme.green
                    HStack(spacing: 3) {
                        Circle()
                            .fill(ctxColor)
                            .frame(width: 6, height: 6)
                        Text(String(format: "ctx %.0f%%", ctxPct))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(ctxColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(ctxColor.opacity(0.1))
                    )
                }

                Spacer()

                // Select / Share buttons
                if isSelectMode {
                    Menu {
                        ForEach(ShareExportPreset.allCases) { preset in
                            Button {
                                sharePreset = preset
                            } label: {
                                HStack {
                                    Text(preset.label)
                                    if sharePreset == preset {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 9))
                            Text(sharePreset.label)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Theme.cardBackground)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        shareSelectedMessages(session: session)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 9))
                            Text(L10n.isChinese ? "分享(\(selectedMessageIDs.count))" : "Share(\(selectedMessageIDs.count))")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(selectedMessageIDs.isEmpty ? Theme.textTertiary : Theme.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selectedMessageIDs.isEmpty ? Theme.cardBackground : Theme.cyan.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedMessageIDs.isEmpty || isExportingShare)

                    Button {
                        exportSelectedMessagesPDF(session: session)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 9))
                            Text("PDF")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(selectedMessageIDs.isEmpty ? Theme.textTertiary : Theme.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selectedMessageIDs.isEmpty ? Theme.cardBackground : Theme.green.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedMessageIDs.isEmpty || isExportingShare)

                    Button {
                        isSelectMode = false
                        selectedMessageIDs.removeAll()
                    } label: {
                        Text(L10n.isChinese ? "取消" : "Cancel")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        isSelectMode = true
                        selectedMessageIDs.removeAll()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 9))
                            Text(L10n.isChinese ? "选择" : "Select")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Theme.cardBackground)
                        )
                    }
                    .buttonStyle(.plain)

                    if let duration = formattedDuration(session.duration) {
                        Text(duration)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Theme.cardBackground)
                            )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().background(Theme.border)

            // Messages
            ScrollView(.vertical, showsIndicators: true) {
                let visibleMessages = session.messages.filter {
                    !$0.isToolResult
                        && !$0.isMeta
                        && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if visibleMessages.isEmpty {
                    VStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isLoading ? (L10n.isChinese ? "正在加载完整会话..." : "Loading full conversation...")
                             : L10n.noMessages)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                        Text(L10n.isChinese ? "已按需懒加载，打开面板后会逐步填充消息内容"
                             : "Messages are loaded on demand after opening the panel")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .padding(.top, 18)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleMessages) { message in
                            HStack(spacing: 6) {
                                if isSelectMode {
                                    Button {
                                        toggleMessage(message.id)
                                    } label: {
                                        Image(systemName: selectedMessageIDs.contains(message.id)
                                              ? "checkmark.circle.fill"
                                              : "circle")
                                            .font(.system(size: 14))
                                            .foregroundColor(selectedMessageIDs.contains(message.id)
                                                             ? Theme.cyan
                                                             : Theme.textTertiary.opacity(0.4))
                                    }
                                    .buttonStyle(.plain)
                                }

                                messageBubble(message)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Theme.background)
    }

    private func toggleMessage(_ id: UUID) {
        if selectedMessageIDs.contains(id) {
            selectedMessageIDs.remove(id)
        } else {
            selectedMessageIDs.insert(id)
        }
    }

    private func shareSelectedMessages(session: Session) {
        let selected = session.messages.filter { selectedMessageIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        Task { await exportSelectedMessages(session: session, selectedMessages: selected, asPDF: false) }
    }

    private func exportSelectedMessagesPDF(session: Session) {
        let selected = session.messages.filter { selectedMessageIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        Task { await exportSelectedMessages(session: session, selectedMessages: selected, asPDF: true) }
    }

    private func exportSelectedMessages(
        session: Session,
        selectedMessages: [Message],
        asPDF: Bool
    ) async {
        guard !isExportingShare else { return }
        isExportingShare = true
        defer { isExportingShare = false }

        let projectName = session.projectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        let html = buildShareHTML(
            messages: selectedMessages,
            projectName: projectName,
            startTime: session.startTime,
            preset: sharePreset
        )

        let renderer = HTMLShareRenderer(
            viewportWidth: max(360, Int(sharePreset.cardWidth)),
            scale: sharePreset.scale
        )

        do {
            try await renderer.load(html: html)
            let stamp = shareFileStamp()
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

            if asPDF {
                let pdfData = try await renderer.renderPDFData()
                let fileName = "chat-share-\(selectedMessages.count)msgs-\(sharePreset.slug)-\(stamp).pdf"
                let filePath = desktop.appendingPathComponent(fileName)
                try pdfData.write(to: filePath, options: .atomic)
                isSelectMode = false
                selectedMessageIDs.removeAll()
                NSWorkspace.shared.open(filePath)
                showShareToast(L10n.isChinese ? "已导出清晰 PDF" : "Exported PDF")
                return
            }

            let pages = try await renderer.renderPNGPages(maxPageHeight: sharePreset.maxPagePixelHeight)
            guard !pages.isEmpty else {
                showShareToast(L10n.isChinese ? "导出失败，请重试" : "Export failed")
                return
            }

            var outputURLs: [URL] = []
            for (index, pngData) in pages.enumerated() {
                let pageSuffix = pages.count > 1 ? "-p\(index + 1)" : ""
                let fileName = "chat-share-\(selectedMessages.count)msgs-\(sharePreset.slug)-\(stamp)\(pageSuffix).png"
                let filePath = desktop.appendingPathComponent(fileName)
                try pngData.write(to: filePath, options: .atomic)
                outputURLs.append(filePath)
            }

            if let first = pages.first {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(first, forType: .png)
            }

            isSelectMode = false
            selectedMessageIDs.removeAll()

            if let firstURL = outputURLs.first {
                NSWorkspace.shared.open(firstURL)
            }

            let msg = pages.count > 1
                ? (L10n.isChinese ? "已导出 \(pages.count) 张高清图片并复制第一页" : "Exported \(pages.count) HD images")
                : (L10n.isChinese ? "已导出高清图片并复制到剪贴板" : "Exported HD image")
            showShareToast(msg)
        } catch {
            showShareToast(L10n.isChinese ? "导出失败，请重试" : "Export failed")
        }
    }

    private func buildShareHTML(
        messages: [Message],
        projectName: String,
        startTime: Date?,
        preset: ShareExportPreset
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let start = startTime.map { formatter.string(from: $0) } ?? ""

        let messageHTML = messages.map { msg in
            let isUser = msg.role == "human" || msg.role == "user"
            let role = isUser ? "You" : "Claude"
            let roleClass = isUser ? "user" : "assistant"
            let timeText: String
            if let ts = msg.timestamp {
                let t = DateFormatter()
                t.dateFormat = "HH:mm"
                timeText = t.string(from: ts)
            } else {
                timeText = ""
            }
            return """
            <section class="bubble \(roleClass)">
              <header class="meta">
                <span class="role">\(escapeHTML(role))</span>
                <span class="time">\(escapeHTML(timeText))</span>
              </header>
              <article class="content">\(escapeHTML(msg.content))</article>
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            :root {
              --font-main: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
              --canvas: #0a0a0a;
              --text: #f2f5ff;
              --muted: rgba(255,255,255,0.62);
              --card-bg: #16213E;
              --top-bg: #1A1A2E;
              --footer-bg: #0F3460;
              --card-border: rgba(255,255,255,0.08);
              --card-radius: 12px;
              --bubble-radius: 10px;
              --bubble-user-bg: rgba(0,212,170,0.10);
              --bubble-user-border: rgba(0,212,170,0.28);
              --bubble-assist-bg: rgba(123,97,255,0.10);
              --bubble-assist-border: rgba(123,97,255,0.28);
              --role-user: #00D4AA;
              --role-assist: #8F81FF;
              --content: rgba(255,255,255,0.9);
            }
            body {
              margin: 0;
              background: var(--canvas);
              font-family: var(--font-main);
              color: var(--text);
              padding: 12px;
            }
            .card {
              width: \(Int(preset.cardWidth))px;
              border-radius: var(--card-radius);
              overflow: hidden;
              border: 1px solid var(--card-border);
              background: var(--card-bg);
            }
            .top {
              background: var(--top-bg);
              padding: 16px;
              border-bottom: 1px solid var(--card-border);
            }
            .title { font-size: 14px; font-weight: 700; color: var(--text); margin: 0 0 3px 0; }
            .sub { font-size: 10px; color: var(--muted); display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
            .preset {
              font-size: 9px;
              padding: 2px 6px;
              border-radius: 999px;
              border: 1px solid var(--card-border);
              color: var(--muted);
            }
            .msgs { padding: 16px; display: flex; flex-direction: column; gap: 10px; }
            .bubble {
              border-radius: var(--bubble-radius);
              padding: 12px;
              border: 1px solid transparent;
            }
            .bubble.user { background: var(--bubble-user-bg); border-color: var(--bubble-user-border); }
            .bubble.assistant { background: var(--bubble-assist-bg); border-color: var(--bubble-assist-border); }
            .meta { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
            .role { font-size: 11px; font-weight: 700; color: var(--role-assist); }
            .bubble.user .role { color: var(--role-user); }
            .time { font-size: 9px; color: rgba(255,255,255,0.36); font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
            .content {
              font-size: 12px;
              line-height: 1.55;
              color: var(--content);
              white-space: pre-wrap;
              word-break: break-word;
            }
            .footer {
              background: var(--footer-bg);
              padding: 10px 16px;
              display: flex;
              justify-content: space-between;
              font-size: 9px;
              color: rgba(255,255,255,0.3);
              font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
            }

            /* X: 极简黑白，硬边框，报纸感标题 */
            body.theme-x {
              --font-main: "Helvetica Neue", "PingFang SC", Arial, sans-serif;
              --canvas: #0d0d0d;
              --text: #f3f3f3;
              --muted: rgba(243,243,243,0.62);
              --card-bg: #111;
              --top-bg: #000;
              --footer-bg: #000;
              --card-border: rgba(255,255,255,0.22);
              --card-radius: 2px;
              --bubble-radius: 2px;
              --bubble-user-bg: rgba(255,255,255,0.05);
              --bubble-user-border: rgba(255,255,255,0.30);
              --bubble-assist-bg: rgba(255,255,255,0.02);
              --bubble-assist-border: rgba(255,255,255,0.18);
              --role-user: #fff;
              --role-assist: #d8d8d8;
            }
            body.theme-x .title { text-transform: uppercase; letter-spacing: .08em; font-weight: 800; }
            body.theme-x .bubble { box-shadow: inset 0 0 0 1px rgba(255,255,255,0.06); }

            /* LinkedIn: 亮色商务卡片 */
            body.theme-linkedin {
              --font-main: "Avenir Next", "PingFang SC", "Helvetica Neue", sans-serif;
              --canvas: #f3f6fb;
              --text: #0f172a;
              --muted: rgba(15,23,42,0.62);
              --card-bg: #ffffff;
              --top-bg: linear-gradient(135deg, #0a66c2, #005fb8);
              --footer-bg: #eef3fb;
              --card-border: rgba(10,102,194,0.24);
              --card-radius: 16px;
              --bubble-radius: 14px;
              --bubble-user-bg: #e8f3ff;
              --bubble-user-border: #a8cff6;
              --bubble-assist-bg: #f6f8fc;
              --bubble-assist-border: #d9e2f2;
              --role-user: #0a66c2;
              --role-assist: #334155;
              --content: #1f2937;
            }
            body.theme-linkedin .card { box-shadow: 0 14px 32px rgba(15,23,42,0.12); }
            body.theme-linkedin .top { color: #fff; border-bottom: none; }
            body.theme-linkedin .top .title, body.theme-linkedin .top .sub, body.theme-linkedin .top .preset { color: #fff; border-color: rgba(255,255,255,0.35); }
            body.theme-linkedin .time { color: rgba(30,41,59,0.45); }

            /* Slack: 终端频道风，等宽正文，左侧信道条 */
            body.theme-slack {
              --font-main: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
              --canvas: #1d1c1d;
              --text: #f8f8f8;
              --muted: rgba(248,248,248,0.65);
              --card-bg: #252327;
              --top-bg: #2c2a30;
              --footer-bg: #2c2a30;
              --card-border: rgba(255,255,255,0.10);
              --card-radius: 10px;
              --bubble-radius: 8px;
              --bubble-user-bg: rgba(46,182,125,0.10);
              --bubble-user-border: rgba(46,182,125,0.36);
              --bubble-assist-bg: rgba(255,255,255,0.04);
              --bubble-assist-border: rgba(255,255,255,0.14);
              --role-user: #2eb67d;
              --role-assist: #f2c744;
            }
            body.theme-slack .bubble { border-left-width: 4px; }
            body.theme-slack .content { font-size: 11px; letter-spacing: .01em; }

            /* Telegram: 轻快蓝白，更圆润聊天气泡 */
            body.theme-telegram {
              --font-main: "SF Pro Rounded", "PingFang SC", -apple-system, sans-serif;
              --canvas: #dceefb;
              --text: #0b1f33;
              --muted: rgba(11,31,51,0.62);
              --card-bg: #f6fbff;
              --top-bg: #5ca9e6;
              --footer-bg: #eaf5ff;
              --card-border: rgba(20,93,161,0.20);
              --card-radius: 20px;
              --bubble-radius: 18px;
              --bubble-user-bg: #dcf8c6;
              --bubble-user-border: rgba(73,174,79,0.25);
              --bubble-assist-bg: #ffffff;
              --bubble-assist-border: rgba(92,169,230,0.35);
              --role-user: #2d8f2d;
              --role-assist: #1f6cb2;
              --content: #0c2a44;
            }
            body.theme-telegram .msgs { background: linear-gradient(180deg, rgba(92,169,230,0.08), rgba(92,169,230,0.02)); }
            body.theme-telegram .time { color: rgba(11,31,51,0.42); }
          </style>
        </head>
        <body class="theme-\(preset.slug)">
          <main class="card">
            <header class="top">
              <h1 class="title">Claude Code</h1>
              <div class="sub">
                <span class="preset">\(escapeHTML(preset.label))</span>
                <span>\(escapeHTML(projectName))</span>
                <span>\(escapeHTML(start))</span>
              </div>
            </header>
            <section class="msgs">
              \(messageHTML)
            </section>
            <footer class="footer">
              <span>cc-statistics</span>
              <span>github.com/androidZzT/cc-statistics</span>
            </footer>
          </main>
        </body>
        </html>
        """
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func shareFileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func showShareToast(_ message: String) {
        withAnimation {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                toastMessage = nil
            }
        }
    }

    private func messageBubble(_ message: Message) -> some View {
        let isUser = message.role == "human" || message.role == "user"
        let bubbleColor = isUser ? Theme.cyan.opacity(0.1) : Theme.purple.opacity(0.1)
        let borderColor = isUser ? Theme.cyan.opacity(0.2) : Theme.purple.opacity(0.2)
        let roleLabel = isUser ? L10n.you : L10n.assistant
        let roleColor = isUser ? Theme.cyan : Theme.purple

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: isUser ? "person.fill" : "cpu")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(roleColor)
                Text(roleLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(roleColor)
                Spacer()
                if let ts = message.timestamp {
                    Text(ts, style: .time)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            ConversationMarkdownView(text: String(message.content.prefix(800)))

            if !message.toolCalls.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 8))
                    Text("\(message.toolCalls.count) \(L10n.toolCallsCount)")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(Theme.textTertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bubbleColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Empty Selection

    private var emptySelection: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Theme.textTertiary)
            Text(L10n.selectSession)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formattedDuration(_ seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        let totalSeconds = Int(seconds)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else if totalSeconds < 3600 {
            let m = totalSeconds / 60
            let s = totalSeconds % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        } else {
            let h = totalSeconds / 3600
            let m = (totalSeconds % 3600) / 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
    }
}

// MARK: - HTML Share Renderer

@MainActor
private final class HTMLShareRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let viewportWidth: Int
    private let scale: CGFloat
    private var loadContinuation: CheckedContinuation<Void, Error>?

    init(viewportWidth: Int, scale: CGFloat) {
        self.viewportWidth = viewportWidth
        self.scale = scale
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.frame = CGRect(x: 0, y: 0, width: CGFloat(viewportWidth), height: 1)
    }

    func load(html: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        // 等待一次布局稳定，避免刚加载完抓图出现空白/跳动
        try await Task.sleep(nanoseconds: 120_000_000)
    }

    func renderPNGPages(maxPageHeight: Int) async throws -> [Data] {
        let size = try await contentSize()
        let pageHeight = max(600, maxPageHeight)
        var offsetY: CGFloat = 0
        var pages: [Data] = []

        while offsetY < size.height - 0.5 {
            let thisHeight = min(CGFloat(pageHeight), size.height - offsetY)
            let snapshot = try await webView.snapshotImage(
                rect: CGRect(x: 0, y: offsetY, width: size.width, height: thisHeight),
                scale: scale
            )
            guard let tiff = snapshot.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let pngData = rep.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "ccstats.share", code: 2)
            }
            pages.append(pngData)
            offsetY += thisHeight
        }

        return pages
    }

    func renderPDFData() async throws -> Data {
        let size = try await contentSize()
        if #available(macOS 11.0, *) {
            return try await webView.pdfData(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        return webView.dataWithPDF(inside: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }

    private func contentSize() async throws -> CGSize {
        let raw = try await webView.evaluateJS("""
        (() => {
          const d = document.documentElement;
          const b = document.body;
          const w = Math.max(d.scrollWidth, b.scrollWidth, d.clientWidth, \(viewportWidth));
          const h = Math.max(d.scrollHeight, b.scrollHeight, d.clientHeight);
          return JSON.stringify({ width: w, height: h });
        })();
        """)

        guard let str = raw as? String,
              let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let w = obj["width"] as? Double,
              let h = obj["height"] as? Double else {
            throw NSError(domain: "ccstats.share", code: 1)
        }

        let width = max(CGFloat(viewportWidth), CGFloat(w))
        let height = max(1, CGFloat(h))
        webView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return CGSize(width: width, height: height)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }
}

private extension WKWebView {
    func evaluateJS(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            self.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    func snapshotImage(rect: CGRect, scale: CGFloat) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            let config = WKSnapshotConfiguration()
            config.rect = rect
            config.snapshotWidth = NSNumber(value: Double(rect.width * scale))
            self.takeSnapshot(with: config) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image else {
                    continuation.resume(throwing: NSError(domain: "ccstats.share", code: 3))
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    @available(macOS 11.0, *)
    func pdfData(rect: CGRect) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let config = WKPDFConfiguration()
            config.rect = rect
            self.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Share Card (渲染为长图)

struct ShareCardView: View {
    let messages: [Message]
    let projectName: String
    let startTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                // Claude logo circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00D4AA"), Color(hex: "7B61FF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    Text("CC")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        if !projectName.isEmpty {
                            Text(projectName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.6))
                        }
                        if let start = startTime {
                            let formatter: DateFormatter = {
                                let f = DateFormatter()
                                f.dateFormat = "yyyy-MM-dd HH:mm"
                                return f
                            }()
                            Text(formatter.string(from: start))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(Color(hex: "1A1A2E"))

            // Messages
            VStack(alignment: .leading, spacing: 10) {
                ForEach(messages) { msg in
                    shareMessageBubble(msg)
                }
            }
            .padding(16)
            .background(Color(hex: "16213E"))

            // Footer
            HStack {
                Text("cc-statistics")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.3))
                Spacer()
                Text("github.com/androidZzT/cc-statistics")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: "0F3460"))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(8)
        .background(Color(hex: "0A0A0A"))
    }

    private func shareMessageBubble(_ message: Message) -> some View {
        let isUser = message.role == "human" || message.role == "user"
        let bgColor = isUser ? Color(hex: "00D4AA").opacity(0.1) : Color(hex: "7B61FF").opacity(0.1)
        let borderColor = isUser ? Color(hex: "00D4AA").opacity(0.25) : Color(hex: "7B61FF").opacity(0.25)
        let roleLabel = isUser ? "You" : "Claude"
        let roleColor = isUser ? Color(hex: "00D4AA") : Color(hex: "7B61FF")

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: isUser ? "person.fill" : "cpu")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(roleColor)
                Text(roleLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(roleColor)
                Spacer()
                if let ts = message.timestamp {
                    let formatter: DateFormatter = {
                        let f = DateFormatter()
                        f.dateFormat = "HH:mm"
                        return f
                    }()
                    Text(formatter.string(from: ts))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }

            MarkdownContentView(text: message.content)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Markdown Content Renderer

struct MarkdownContentView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseMdSegments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .heading(let level, let title):
                    let fontSize: CGFloat = level == 1 ? 16 : level == 2 ? 14 : 13
                    Text(title)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.92))
                        .padding(.top, level == 1 ? 4 : 2)
                case .code(let lang, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        if !lang.isEmpty {
                            Text(lang)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.4))
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                                .padding(.bottom, 2)
                        }
                        Text(code)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "E0E0E0"))
                            .lineSpacing(2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, lang.isEmpty ? 8 : 4)
                            .padding(.bottom, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                case .table(let headers, let rows):
                    MdTableView(headers: headers, rows: rows, textColor: Color.white.opacity(0.88), headerColor: Color.white.opacity(0.6), borderColor: Color.white.opacity(0.15))
                case .text(let md):
                    let trimmed = md.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if let attr = try? AttributedString(markdown: trimmed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                            Text(attr)
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.88))
                                .lineSpacing(3)
                        } else {
                            Text(trimmed)
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.88))
                                .lineSpacing(3)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Shared Markdown Parser

enum MdSegment {
    case text(String)
    case code(lang: String, code: String)
    case heading(level: Int, text: String)
    case table(headers: [String], rows: [[String]])
}

func parseMdSegments(_ text: String) -> [MdSegment] {
    var segments: [MdSegment] = []
    let lines = text.components(separatedBy: "\n")
    var currentText = ""
    var inCodeBlock = false
    var codeLang = ""
    var codeLines: [String] = []
    var tableHeaders: [String] = []
    var tableRows: [[String]] = []
    var inTable = false

    func flushText() {
        if !currentText.isEmpty {
            segments.append(.text(currentText))
            currentText = ""
        }
    }

    func flushTable() {
        if inTable && !tableHeaders.isEmpty {
            segments.append(.table(headers: tableHeaders, rows: tableRows))
            tableHeaders = []
            tableRows = []
            inTable = false
        }
    }

    func parseTableRow(_ line: String) -> [String] {
        return line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func isSeparatorRow(_ line: String) -> Bool {
        let cleaned = line.replacingOccurrences(of: " ", with: "")
        return cleaned.contains("|") && cleaned.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" }
    }

    for line in lines {
        if line.hasPrefix("```") && !inCodeBlock {
            flushText()
            flushTable()
            inCodeBlock = true
            codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            codeLines = []
        } else if line.hasPrefix("```") && inCodeBlock {
            segments.append(.code(lang: codeLang, code: codeLines.joined(separator: "\n")))
            inCodeBlock = false
        } else if inCodeBlock {
            codeLines.append(line)
        } else if line.contains("|") && !inCodeBlock {
            let cells = parseTableRow(line)
            if isSeparatorRow(line) {
                // 分隔行，跳过
                continue
            } else if !inTable {
                flushText()
                tableHeaders = cells
                tableRows = []
                inTable = true
            } else {
                tableRows.append(cells)
            }
        } else {
            flushTable()
            if line.hasPrefix("#") {
                flushText()
                var level = 0
                for ch in line { if ch == "#" { level += 1 } else { break } }
                let title = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    segments.append(.heading(level: min(level, 4), text: title))
                }
            } else {
                if !currentText.isEmpty { currentText += "\n" }
                currentText += line
            }
        }
    }

    if inCodeBlock {
        segments.append(.code(lang: codeLang, code: codeLines.joined(separator: "\n")))
    }
    flushTable()
    if !currentText.isEmpty {
        segments.append(.text(currentText))
    }
    return segments
}

// MARK: - Conversation Markdown View (面板用，跟随 Theme 颜色)

struct ConversationMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parseMdSegments(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .heading(let level, let title):
                    let fontSize: CGFloat = level == 1 ? 15 : level == 2 ? 13 : 12
                    Text(title)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.top, level == 1 ? 4 : 2)
                case .code(let lang, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        if !lang.isEmpty {
                            Text(lang)
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.top, 5)
                                .padding(.bottom, 1)
                        }
                        Text(code)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                            .lineSpacing(2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, lang.isEmpty ? 6 : 3)
                            .padding(.bottom, 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.background.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.border.opacity(0.3), lineWidth: 0.5)
                    )
                case .table(let headers, let rows):
                    MdTableView(headers: headers, rows: rows, textColor: Theme.textPrimary, headerColor: Theme.textSecondary, borderColor: Theme.border)
                case .text(let md):
                    let trimmed = md.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if let attr = try? AttributedString(markdown: trimmed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                            Text(attr)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textPrimary)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                        } else {
                            Text(trimmed)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textPrimary)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Markdown Table View

struct MdTableView: View {
    let headers: [String]
    let rows: [[String]]
    var textColor: Color = .white
    var headerColor: Color = .gray
    var borderColor: Color = .gray.opacity(0.3)

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                    Text(header)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(headerColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    if i < headers.count - 1 {
                        Rectangle().fill(borderColor).frame(width: 0.5)
                    }
                }
            }
            .background(borderColor.opacity(0.15))

            Rectangle().fill(borderColor).frame(height: 0.5)

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.prefix(headers.count).enumerated()), id: \.offset) { i, cell in
                        Text(cell)
                            .font(.system(size: 10))
                            .foregroundColor(textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        if i < headers.count - 1 {
                            Rectangle().fill(borderColor).frame(width: 0.5)
                        }
                    }
                }
                if ri < rows.count - 1 {
                    Rectangle().fill(borderColor).frame(height: 0.5)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
