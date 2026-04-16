import Foundation

/// Parses Codex CLI sessions from ~/.codex/ rollout JSONL files.
/// Codex stores sessions as JSONL with tagged types: session_meta, event_msg, response_item, turn_context.
/// Respects $CODEX_HOME environment variable for custom session storage paths.
final class CodexParser {

    private let fileManager = FileManager.default
    private let codexHome: String
    private static let toolNameMap: [String: String] = [
        "exec_command": "Bash",
        "write_stdin": "Bash",
        "read_mcp_resource": "Read",
        "list_mcp_resources": "ToolSearch",
        "list_mcp_resource_templates": "ToolSearch",
        "search_query": "WebSearch",
        "image_query": "WebSearch",
        "web.run": "WebSearch",
        "apply_patch": "Edit",
    ]

    init(codexHome: String? = nil) {
        if let custom = codexHome {
            self.codexHome = custom
        } else if let envHome = ProcessInfo.processInfo.environment["CODEX_HOME"] {
            self.codexHome = envHome
        } else {
            let home = fileManager.homeDirectoryForCurrentUser.path
            self.codexHome = (home as NSString).appendingPathComponent(".codex")
        }
    }

    // MARK: - Public API

    func findAllProjects() -> [ProjectInfo] {
        let sessions = parseAllSessions()
        var projectMap: [String: (count: Int, lastActive: Date?)] = [:]

        for session in sessions {
            let projectName = session.projectPath ?? "Unknown"
            let existing = projectMap[projectName] ?? (count: 0, lastActive: nil)
            let sessionEnd = session.endTime
            let latest: Date?
            if let a = existing.lastActive, let b = sessionEnd {
                latest = max(a, b)
            } else {
                latest = existing.lastActive ?? sessionEnd
            }
            projectMap[projectName] = (count: existing.count + 1, lastActive: latest)
        }

        return projectMap.map { key, value in
            ProjectInfo(
                name: (key as NSString).lastPathComponent,
                path: key,
                sessionCount: value.count,
                lastActive: value.lastActive
            )
        }.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
    }

    func parseAllSessions() -> [Session] {
        return allSessionFilePaths().compactMap { parseSessionFile($0) }
    }

    func parseSessions(forProject projectPath: String) -> [Session] {
        return parseAllSessions().filter { $0.projectPath == projectPath }
    }

    /// Returns all JSONL file paths under Codex session directories.
    func allSessionFilePaths() -> [String] {
        // Prefer canonical layout: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
        let sessionsDir = (codexHome as NSString).appendingPathComponent("sessions")
        var files = collectRolloutFiles(in: sessionsDir)

        // Fallback for older layouts.
        if files.isEmpty {
            files = collectRolloutFiles(in: codexHome)
        }

        return files
    }

    /// Parse a single session file at the given path (public entry point for incremental parsing).
    func parseSessionFile(atPath filePath: String) -> Session? {
        return parseSessionFile(filePath)
    }

    // MARK: - JSONL Parsing

    private func parseSessionFile(_ filePath: String) -> Session? {
        guard let data = fileManager.contents(atPath: filePath),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var messages: [Message] = []
        var projectPath: String?
        var latestModel: String?
        var seenUserKeys = Set<String>()
        var seenAssistantKeys = Set<String>()
        var lastTotalTokens: Int?

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let tsString = json["timestamp"] as? String
            let ts = parseTimestamp(tsString)
            let type = json["type"] as? String ?? ""
            let payload = json["payload"] as? [String: Any]

            switch type {
            case "session_meta":
                // Extract cwd as project path
                if let meta = payload ?? json["meta"] as? [String: Any],
                   let cwd = meta["cwd"] as? String {
                    projectPath = cwd
                } else if let cwd = json["cwd"] as? String {
                    projectPath = cwd
                }
                if let model = extractModel(from: payload) {
                    latestModel = model
                }

            case "event_msg":
                guard let eventPayload = payload else { continue }
                let eventType = eventPayload["type"] as? String ?? ""

                if eventType == "token_count" {
                    // Codex writes cumulative totals; if total is unchanged, skip duplicate events.
                    if let info = eventPayload["info"] as? [String: Any],
                       let totalUsage = info["total_token_usage"] as? [String: Any] {
                        let total = intValue(totalUsage["total_tokens"])
                        if let last = lastTotalTokens, total > 0, total == last {
                            continue
                        }
                        if total > 0 {
                            lastTotalTokens = total
                        }
                    }

                    if let usage = extractTokenUsage(fromTokenCountPayload: eventPayload) {
                        if let idx = messages.lastIndex(where: { $0.role == "assistant" }) {
                            let mergedUsage = (messages[idx].tokenUsage ?? TokenDetail()) + usage
                            let original = messages[idx]
                            messages[idx] = Message(
                                role: original.role,
                                content: original.content,
                                model: original.model ?? latestModel ?? "unknown",
                                timestamp: original.timestamp,
                                toolCalls: original.toolCalls,
                                toolResultInfos: original.toolResultInfos,
                                tokenUsage: mergedUsage,
                                isToolResult: original.isToolResult,
                                isMeta: original.isMeta,
                                messageId: original.messageId
                            )
                        } else {
                            messages.append(Message(
                                role: "assistant",
                                content: "",
                                model: latestModel ?? "unknown",
                                timestamp: ts,
                                tokenUsage: usage,
                                isMeta: true
                            ))
                        }
                    }
                } else if eventType == "user_message" {
                    let content = eventPayload["message"] as? String ?? ""
                    guard !content.isEmpty else { continue }
                    let key = "\(tsString ?? "")|u|\(content)"
                    if seenUserKeys.contains(key) { continue }
                    seenUserKeys.insert(key)
                    messages.append(Message(
                        role: "user",
                        content: content,
                        timestamp: ts
                    ))
                } else if eventType == "agent_message" {
                    let content = eventPayload["message"] as? String ?? ""
                    guard !content.isEmpty else { continue }
                    let key = "\(tsString ?? "")|a|\(content)"
                    if seenAssistantKeys.contains(key) { continue }
                    seenAssistantKeys.insert(key)
                    messages.append(Message(
                        role: "assistant",
                        content: content,
                        model: latestModel,
                        timestamp: ts
                    ))
                }

            case "response_item":
                guard let item = payload else { continue }
                let itemType = item["type"] as? String ?? ""

                if itemType == "function_call" {
                    let rawName = item["name"] as? String ?? ""
                    guard !rawName.isEmpty else { continue }

                    var input = parseJSONDictionary(item["arguments"])
                    if rawName == "apply_patch" {
                        input = parseApplyPatchInput(item["arguments"])
                    }
                    let mapped = CodexParser.toolNameMap[rawName] ?? rawName

                    let inputLength: Int
                    if let inputData = try? JSONSerialization.data(withJSONObject: input) {
                        inputLength = inputData.count
                    } else {
                        inputLength = 0
                    }

                    let toolCall = ToolCall(
                        name: mapped,
                        timestamp: ts,
                        inputLength: inputLength,
                        input: input,
                        toolUseId: item["call_id"] as? String
                    )
                    messages.append(Message(
                        role: "assistant",
                        content: "",
                        model: latestModel,
                        timestamp: ts,
                        toolCalls: [toolCall]
                    ))
                    continue
                }

                if itemType == "web_search_call" {
                    let action = item["action"] as? [String: Any] ?? [:]
                    let toolCall = ToolCall(
                        name: "WebSearch",
                        timestamp: ts,
                        input: action
                    )
                    messages.append(Message(
                        role: "assistant",
                        content: "",
                        model: latestModel,
                        timestamp: ts,
                        toolCalls: [toolCall]
                    ))
                    continue
                }

                if itemType == "message" {
                    let role = item["role"] as? String ?? "assistant"
                    let itemModel = item["model"] as? String
                    if let m = itemModel { latestModel = m }

                    let textContent = extractTextContent(item["content"])
                    if role == "user" {
                        if textContent.isEmpty || isMetaUserText(textContent) {
                            continue
                        }
                        let key = "\(tsString ?? "")|u|\(textContent)"
                        if seenUserKeys.contains(key) { continue }
                        seenUserKeys.insert(key)
                        messages.append(Message(
                            role: "user",
                            content: textContent,
                            timestamp: ts
                        ))
                    } else if role == "assistant" {
                        guard !textContent.isEmpty else { continue }
                        let key = "\(tsString ?? "")|a|\(textContent)"
                        if seenAssistantKeys.contains(key) { continue }
                        seenAssistantKeys.insert(key)
                        messages.append(Message(
                            role: "assistant",
                            content: textContent,
                            model: itemModel ?? latestModel,
                            timestamp: ts
                        ))
                    }
                }

            case "turn_context":
                // turn_context has the active model for this turn.
                if let model = extractModel(from: payload) {
                    latestModel = model
                }
                break

            default:
                break
            }
        }

        guard !messages.isEmpty else { return nil }

        return Session(
            filePath: filePath,
            messages: messages,
            projectPath: projectPath
        )
    }

    // MARK: - Helpers

    private func collectRolloutFiles(in rootDir: String) -> [String] {
        guard fileManager.fileExists(atPath: rootDir) else { return [] }
        guard let enumerator = fileManager.enumerator(atPath: rootDir) else { return [] }

        var files: [String] = []
        while let element = enumerator.nextObject() as? String {
            let name = (element as NSString).lastPathComponent
            guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
            files.append((rootDir as NSString).appendingPathComponent(element))
        }

        return Array(Set(files)).sorted()
    }

    private func intValue(_ raw: Any?) -> Int {
        if let v = raw as? Int { return v }
        if let v = raw as? Double { return Int(v) }
        if let v = raw as? NSNumber { return v.intValue }
        if let s = raw as? String, let d = Double(s) { return Int(d) }
        return 0
    }

    private func parseJSONDictionary(_ raw: Any?) -> [String: Any] {
        if let dict = raw as? [String: Any] { return dict }
        guard let text = raw as? String, let data = text.data(using: .utf8) else { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func extractModel(from payload: [String: Any]?) -> String? {
        guard let payload = payload else { return nil }

        if let model = payload["model"] as? String, !model.isEmpty {
            return model
        }

        if let collab = payload["collaboration_mode"] as? [String: Any],
           let settings = collab["settings"] as? [String: Any],
           let model = settings["model"] as? String,
           !model.isEmpty {
            return model
        }

        return nil
    }

    private func extractTokenUsage(fromTokenCountPayload payload: [String: Any]) -> TokenDetail? {
        guard let info = payload["info"] as? [String: Any],
              let lastUsage = info["last_token_usage"] as? [String: Any] else {
            return nil
        }

        let rawInput = intValue(lastUsage["input_tokens"])
        let cached = intValue(lastUsage["cached_input_tokens"])
        let output = intValue(lastUsage["output_tokens"])

        guard rawInput > 0 || cached > 0 || output > 0 else { return nil }

        // Codex last_token_usage.input_tokens includes cached_input_tokens.
        let inputNoCache = max(rawInput - cached, 0)
        return TokenDetail(
            inputTokens: inputNoCache,
            outputTokens: output,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: cached
        )
    }

    private func extractTextContent(_ raw: Any?) -> String {
        if let text = raw as? String { return text }

        let blocks: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            blocks = arr
        } else if let arrAny = raw as? [Any] {
            blocks = arrAny.compactMap { $0 as? [String: Any] }
        } else {
            blocks = []
        }

        var parts: [String] = []
        for block in blocks {
            let blockType = block["type"] as? String ?? ""
            if blockType == "text" || blockType == "input_text" || blockType == "output_text" {
                if let t = block["text"] as? String, !t.isEmpty {
                    parts.append(t)
                }
            }
        }
        return parts.joined(separator: "\n")
    }

    private func isMetaUserText(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("<environment_context>")
            || s.hasPrefix("<permissions instructions>")
            || s.hasPrefix("<app-context>")
    }

    private func parseApplyPatchInput(_ rawArguments: Any?) -> [String: Any] {
        var patchText = ""
        if let s = rawArguments as? String {
            patchText = s
        } else if let dict = rawArguments as? [String: Any] {
            patchText = (dict["patch"] as? String) ?? (dict["input"] as? String) ?? ""
        }

        var filePath = ""
        var added = 0
        var removed = 0

        for line in patchText.components(separatedBy: .newlines) {
            if filePath.isEmpty {
                if line.hasPrefix("*** Update File: ") {
                    filePath = String(line.dropFirst("*** Update File: ".count))
                } else if line.hasPrefix("*** Add File: ") {
                    filePath = String(line.dropFirst("*** Add File: ".count))
                } else if line.hasPrefix("*** Delete File: ") {
                    filePath = String(line.dropFirst("*** Delete File: ".count))
                }
            }

            if line.hasPrefix("+"), !line.hasPrefix("+++") {
                added += 1
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                removed += 1
            }
        }

        return [
            "target_file": filePath,
            "old_string": dummyLines(removed),
            "new_string": dummyLines(added),
        ]
    }

    private func dummyLines(_ count: Int) -> String {
        guard count > 0 else { return "" }
        return Array(repeating: "x", count: count).joined(separator: "\n")
    }

    private lazy var iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private lazy var iso8601Fallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseTimestamp(_ ts: String?) -> Date? {
        guard let ts = ts else { return nil }
        return iso8601Formatter.date(from: ts) ?? iso8601Fallback.date(from: ts)
    }
}
