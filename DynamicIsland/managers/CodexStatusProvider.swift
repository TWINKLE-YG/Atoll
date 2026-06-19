/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import Foundation

protocol CodexStatusProvider {
    func currentThreadStatus() async -> CodexThreadStatus
}

struct CodexStatusProviderFactory {
    static func makeDefaultProvider(mockStatusFilePath: String) -> any CodexStatusProvider {
        CodexDesktopStatusProvider()
    }
}

struct FallbackCodexStatusProvider: CodexStatusProvider {
    let primary: any CodexStatusProvider
    let fallback: any CodexStatusProvider

    func currentThreadStatus() async -> CodexThreadStatus {
        let primaryStatus = await primary.currentThreadStatus()
        switch primaryStatus.sourceAvailability {
        case .available:
            return primaryStatus
        case .codexNotRunning, .permissionDenied, .unsupported, .error:
            return await fallback.currentThreadStatus()
        }
    }
}

struct UnsupportedCodexStatusProvider: CodexStatusProvider {
    func currentThreadStatus() async -> CodexThreadStatus {
        CodexThreadStatus.unavailable
    }
}

struct CodexDesktopStatusProvider: CodexStatusProvider {
    private let stateDatabasePath: String
    private let logsDatabasePath: String
    private let now: () -> Date

    init(
        stateDatabasePath: String = "\(NSHomeDirectory())/.codex/state_5.sqlite",
        logsDatabasePath: String = "\(NSHomeDirectory())/.codex/logs_2.sqlite",
        now: @escaping () -> Date = Date.init
    ) {
        self.stateDatabasePath = stateDatabasePath
        self.logsDatabasePath = logsDatabasePath
        self.now = now
    }

    func currentThreadStatus() async -> CodexThreadStatus {
        await Task.detached(priority: .utility) {
            readCurrentThreadStatus()
        }.value
    }

    private func readCurrentThreadStatus() -> CodexThreadStatus {
        guard FileManager.default.fileExists(atPath: stateDatabasePath) else {
            return CodexThreadStatus(
                threadId: nil,
                title: nil,
                state: .unknown,
                summary: nil,
                lastUpdatedAt: now(),
                workingStartedAt: nil,
                sourceAvailability: .codexNotRunning
            )
        }

        do {
            if let activity = try latestRealtimeActivity(),
               let row = try realtimeThreadRow(for: activity.threadId) {
                let snapshot = rolloutSnapshot(at: row.rolloutPath)
                let realtimeAt = Date(timeIntervalSince1970: TimeInterval(activity.timestamp))
                let lastUpdatedAt = maxDate(realtimeAt, snapshot?.lastActivityAt) ?? realtimeAt
                let state: CodexRunState = snapshot?.lastAssistantAt.map { $0 > realtimeAt ? .done : .working } ?? .working
                let summary = statusSummary(
                    state: state,
                    row: row,
                    snapshot: snapshot,
                    fallback: String(localized: "Codex 正在生成回复…")
                )
                CodexDebugLogger.log("状态=\(state.rawValue) reason=\(activity.reason) threadId=\(row.id) ts=\(activity.timestamp) assistantPreview=\(snapshot?.latestAssistantText != nil)")
                let relatedSessions = recentSessionSummaries(
                    primaryThreadId: row.id,
                    primaryState: state,
                    primaryLastUpdatedAt: lastUpdatedAt,
                    primaryWorkingStartedAt: state == .working ? realtimeAt : nil
                )
                return CodexThreadStatus(
                    threadId: row.id,
                    title: row.title,
                    state: state,
                    summary: summary,
                    latestAssistantText: snapshot?.latestAssistantText,
                    latestActivityText: snapshot?.latestActivityText,
                    timelineEvents: snapshot?.timelineEvents ?? [],
                    taskStage: taskStage(state: state, snapshot: snapshot),
                    taskReport: taskReport(state: state, snapshot: snapshot),
                    relatedSessions: relatedSessions,
                    lastUpdatedAt: lastUpdatedAt,
                    workingStartedAt: state == .working ? realtimeAt : nil,
                    sourceAvailability: .available
                )
            }

            guard let row = try latestUserThreadRow() else {
                if let recentAuthError = recentCodexAuthError() {
                    CodexDebugLogger.log("状态=error reason=recent-auth-error-no-thread message=\(recentAuthError)")
                    return CodexThreadStatus(
                        threadId: nil,
                        title: String(localized: "Codex"),
                        state: .error,
                        summary: recentAuthError,
                        lastUpdatedAt: now(),
                        workingStartedAt: nil,
                        sourceAvailability: .error(message: recentAuthError)
                    )
                }
                CodexDebugLogger.log("状态=idle reason=no-user-thread")
                return CodexThreadStatus(
                    threadId: nil,
                    title: String(localized: "Codex"),
                    state: .idle,
                    summary: String(localized: "没有找到最近的 Codex 线程。"),
                    lastUpdatedAt: now(),
                    workingStartedAt: nil,
                    sourceAvailability: .available
                )
            }

            let snapshot = rolloutSnapshot(at: row.rolloutPath)
            let databaseUpdatedAt = Date(timeIntervalSince1970: TimeInterval(row.updatedAtMs) / 1000)
            let lastUpdatedAt = maxDate(databaseUpdatedAt, snapshot?.lastActivityAt) ?? databaseUpdatedAt
            let age = now().timeIntervalSince(lastUpdatedAt)
            let state = stateForIdlePath(row: row, snapshot: snapshot, lastUpdatedAt: lastUpdatedAt)
            let summary = statusSummary(state: state, row: row, snapshot: snapshot, fallback: row.preview)
            if let recentAuthError = recentCodexAuthError() {
                CodexDebugLogger.log("忽略后台认证错误 reason=thread-available state=\(state.rawValue) message=\(recentAuthError)")
            }
            CodexDebugLogger.log("状态=\(state.rawValue) reason=thread-age age=\(Int(age))s threadId=\(row.id) rollout=\(row.rolloutPath != nil)")
            let relatedSessions = recentSessionSummaries(
                primaryThreadId: row.id,
                primaryState: state,
                primaryLastUpdatedAt: lastUpdatedAt,
                primaryWorkingStartedAt: state == .working ? lastUpdatedAt : nil
            )
            return CodexThreadStatus(
                threadId: row.id,
                title: row.title,
                state: state,
                summary: summary,
                latestAssistantText: snapshot?.latestAssistantText,
                latestActivityText: snapshot?.latestActivityText,
                timelineEvents: snapshot?.timelineEvents ?? [],
                taskStage: taskStage(state: state, snapshot: snapshot),
                taskReport: taskReport(state: state, snapshot: snapshot),
                relatedSessions: relatedSessions,
                lastUpdatedAt: lastUpdatedAt,
                workingStartedAt: state == .working ? lastUpdatedAt : nil,
                sourceAvailability: .available
            )
        } catch {
            CodexDebugLogger.log("状态=unknown reason=provider-error message=\(error.localizedDescription)")
            return CodexThreadStatus(
                threadId: nil,
                title: String(localized: "Codex"),
                state: .unknown,
                summary: nil,
                lastUpdatedAt: now(),
                workingStartedAt: nil,
                sourceAvailability: .error(message: error.localizedDescription)
            )
        }
    }

    private func latestRealtimeActivity() throws -> RealtimeActivity? {
        guard FileManager.default.fileExists(atPath: logsDatabasePath) else { return nil }
        let since = Int(now().timeIntervalSince1970) - 20
        let sql = """
        SELECT COALESCE(thread_id, ''), ts, COALESCE(target, ''), COALESCE(feedback_log_body, '')
        FROM logs
        WHERE ts >= \(since)
          AND (
            target LIKE '%codex_api::sse::responses%'
            OR target LIKE '%codex_app_server::outgoing_message%'
            OR feedback_log_body LIKE '%response.output_text.delta%'
            OR feedback_log_body LIKE '%item/agentMessage/delta%'
            OR feedback_log_body LIKE '%response.function_call_arguments.delta%'
            OR feedback_log_body LIKE '%response.output_item.added%'
          )
        ORDER BY ts DESC, ts_nanos DESC
        LIMIT 1;
        """

        let output = try runSQLite(databasePath: logsDatabasePath, sql: sql)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fields = trimmed.components(separatedBy: "\u{1f}")
        guard fields.count >= 4, let timestamp = Int(fields[1]) else {
            throw CodexStatusProviderError.invalidSQLiteOutput
        }

        let target = fields[2]
        let body = fields[3]
        let threadId = fields[0].isEmpty ? extractConversationID(from: body) : fields[0]
        return RealtimeActivity(
            threadId: threadId,
            timestamp: timestamp,
            reason: target.isEmpty ? "recent realtime log" : target
        )
    }

    private func extractConversationID(from text: String) -> String? {
        guard let range = text.range(of: #"conversation\.id=([A-Za-z0-9-]+)"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(text[range])
        return matched.replacingOccurrences(of: "conversation.id=", with: "")
    }

    private func latestUserThreadRow() throws -> ThreadRow? {
        let sql = """
        SELECT id,
               hex(COALESCE(title, '')),
               hex(COALESCE(preview, '')),
               updated_at_ms,
               hex(COALESCE(rollout_path, ''))
        FROM threads
        WHERE archived = 0
          AND preview <> ''
          AND COALESCE(thread_source, '') = 'user'
        ORDER BY recency_at_ms DESC, updated_at_ms DESC
        LIMIT 1;
        """
        let output = try runSQLite(databasePath: stateDatabasePath, sql: sql)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fields = trimmed.components(separatedBy: "\u{1f}")
        guard fields.count >= 4,
              let title = decodeSQLiteHex(fields[1]),
              let preview = decodeSQLiteHex(fields[2]),
              let updatedAtMs = Int64(fields[3]) else {
            throw CodexStatusProviderError.invalidSQLiteOutput
        }

        return ThreadRow(
            id: fields[0],
            title: title,
            preview: preview,
            updatedAtMs: updatedAtMs,
            rolloutPath: fields.count > 4 ? decodeSQLiteHex(fields[4]).flatMap { $0.isEmpty ? nil : $0 } : nil
        )
    }

    private func recentThreadRows(limit: Int = 5) throws -> [ThreadRow] {
        let sql = """
        SELECT id,
               hex(COALESCE(title, '')),
               hex(COALESCE(preview, '')),
               updated_at_ms,
               hex(COALESCE(rollout_path, ''))
        FROM threads
        WHERE archived = 0
          AND preview <> ''
          AND COALESCE(thread_source, '') = 'user'
        ORDER BY recency_at_ms DESC, updated_at_ms DESC
        LIMIT \(limit);
        """
        let output = try runSQLite(databasePath: stateDatabasePath, sql: sql)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return try trimmed.split(separator: "\n").map { line in
            let fields = String(line).components(separatedBy: "\u{1f}")
            guard fields.count >= 4,
                  let title = decodeSQLiteHex(fields[1]),
                  let preview = decodeSQLiteHex(fields[2]),
                  let updatedAtMs = Int64(fields[3]) else {
                CodexDebugLogger.log("解析 Codex 会话队列失败 fields=\(fields.count) linePreview=\(normalizedPreview(String(line), limit: 120))")
                throw CodexStatusProviderError.invalidSQLiteOutput
            }
            return ThreadRow(
                id: fields[0],
                title: title,
                preview: preview,
                updatedAtMs: updatedAtMs,
                rolloutPath: fields.count > 4 ? decodeSQLiteHex(fields[4]).flatMap { $0.isEmpty ? nil : $0 } : nil
            )
        }
    }

    private func realtimeThreadRow(for threadId: String?) throws -> ThreadRow? {
        guard let threadId, !threadId.isEmpty else {
            return try latestUserThreadRow()
        }
        return try threadRow(id: threadId) ?? latestUserThreadRow()
    }

    private func threadRow(id: String) throws -> ThreadRow? {
        let escapedID = id.replacingOccurrences(of: "'", with: "''")
        let sql = """
        SELECT id,
               hex(COALESCE(title, '')),
               hex(COALESCE(preview, '')),
               updated_at_ms,
               hex(COALESCE(rollout_path, ''))
        FROM threads
        WHERE id = '\(escapedID)'
        LIMIT 1;
        """
        let output = try runSQLite(databasePath: stateDatabasePath, sql: sql)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fields = trimmed.components(separatedBy: "\u{1f}")
        guard fields.count >= 4,
              let title = decodeSQLiteHex(fields[1]),
              let preview = decodeSQLiteHex(fields[2]),
              let updatedAtMs = Int64(fields[3]) else {
            throw CodexStatusProviderError.invalidSQLiteOutput
        }

        return ThreadRow(
            id: fields[0],
            title: title,
            preview: preview,
            updatedAtMs: updatedAtMs,
            rolloutPath: fields.count > 4 ? decodeSQLiteHex(fields[4]).flatMap { $0.isEmpty ? nil : $0 } : nil
        )
    }

    private func decodeSQLiteHex(_ value: String) -> String? {
        guard value.count.isMultiple(of: 2) else { return nil }

        var data = Data()
        data.reserveCapacity(value.count / 2)

        var index = value.startIndex
        while index < value.endIndex {
            let nextIndex = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        return String(data: data, encoding: .utf8)
    }

    private func stateForIdlePath(row: ThreadRow, snapshot: RolloutSnapshot?, lastUpdatedAt: Date) -> CodexRunState {
        if let snapshot {
            if let latestUserAt = snapshot.lastUserAt,
               snapshot.lastAssistantAt == nil || latestUserAt > (snapshot.lastAssistantAt ?? .distantPast) {
                return now().timeIntervalSince(latestUserAt) < 20 ? .working : .idle
            }

            if let lastAssistantAt = snapshot.lastAssistantAt,
               lastAssistantAt >= (snapshot.lastUserAt ?? .distantPast),
               now().timeIntervalSince(lastAssistantAt) < 900 {
                return .done
            }
        }

        let age = now().timeIntervalSince(lastUpdatedAt)
        return age < 12 ? .working : .idle
    }

    private func statusSummary(
        state: CodexRunState,
        row: ThreadRow,
        snapshot: RolloutSnapshot?,
        fallback: String
    ) -> String {
        switch state {
        case .working:
            return snapshot?.latestAssistantText ?? snapshot?.latestActivityText ?? fallback
        case .done:
            return snapshot?.latestAssistantText ?? fallback
        case .waiting:
            return snapshot?.latestActivityText ?? fallback
        case .idle, .error, .unknown:
            return snapshot?.latestAssistantText ?? snapshot?.latestActivityText ?? fallback
        }
    }

    private func recentSessionSummaries(
        primaryThreadId: String?,
        primaryState: CodexRunState,
        primaryLastUpdatedAt: Date?,
        primaryWorkingStartedAt: Date?
    ) -> [CodexSessionSummary] {
        let rows: [ThreadRow]
        do {
            rows = try recentThreadRows(limit: clampedSessionListLimit())
        } catch {
            CodexDebugLogger.log("读取 Codex 会话队列失败 message=\(error.localizedDescription)")
            return []
        }
        let primaryID = primaryThreadId ?? rows.first?.id

        return rows.map { row in
            let snapshot = rolloutSnapshot(at: row.rolloutPath)
            let databaseUpdatedAt = Date(timeIntervalSince1970: TimeInterval(row.updatedAtMs) / 1000)
            let inferredLastUpdatedAt = maxDate(databaseUpdatedAt, snapshot?.lastActivityAt) ?? databaseUpdatedAt
            let isPrimary = row.id == primaryID
            let state = isPrimary ? primaryState : stateForIdlePath(row: row, snapshot: snapshot, lastUpdatedAt: inferredLastUpdatedAt)
            let lastUpdatedAt = isPrimary ? (primaryLastUpdatedAt ?? inferredLastUpdatedAt) : inferredLastUpdatedAt
            let workingStartedAt = isPrimary ? primaryWorkingStartedAt : (state == .working ? lastUpdatedAt : nil)

            return CodexSessionSummary(
                id: row.id,
                title: row.title,
                state: state,
                summary: statusSummary(state: state, row: row, snapshot: snapshot, fallback: row.preview),
                taskStage: taskStage(state: state, snapshot: snapshot),
                lastUpdatedAt: lastUpdatedAt,
                workingStartedAt: workingStartedAt,
                isPrimary: isPrimary
            )
        }
    }

    private func clampedSessionListLimit() -> Int {
        min(max(Defaults[.codexSessionListLimit], 1), 6)
    }

    private func rolloutSnapshot(at path: String?) -> RolloutSnapshot? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let data = try recentFileData(path: path, maximumBytes: 700_000)
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return parseRolloutSnapshot(text)
        } catch {
            CodexDebugLogger.log("读取 rollout 失败 path=\(path) message=\(error.localizedDescription)")
            return nil
        }
    }

    private func recentFileData(path: String, maximumBytes: UInt64) throws -> Data {
        let url = URL(fileURLWithPath: path)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let offset = size > maximumBytes ? size - maximumBytes : 0
        try handle.seek(toOffset: offset)
        return try handle.readToEnd() ?? Data()
    }

    private func parseRolloutSnapshot(_ text: String) -> RolloutSnapshot {
        var snapshot = RolloutSnapshot()
        let decoder = ISO8601DateFormatter()
        decoder.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestampText = object["timestamp"] as? String,
                  let timestamp = decoder.date(from: timestampText),
                  let payload = object["payload"] as? [String: Any] else {
                continue
            }

            snapshot.lastActivityAt = maxDate(snapshot.lastActivityAt, timestamp)

            if let message = payload["message"] as? String,
               payload["type"] as? String == "agent_message" {
                snapshot.latestAssistantText = normalizedPreview(message)
                snapshot.latestActivityText = normalizedPreview(message)
                snapshot.lastAssistantAt = timestamp
                snapshot.appendTimelineEvent(
                    kind: .assistant,
                    title: String(localized: "Codex 回复"),
                    detail: normalizedPreview(message, limit: 160),
                    timestamp: timestamp
                )
                continue
            }

            if object["type"] as? String == "response_item",
               payload["type"] as? String == "message" {
                let role = payload["role"] as? String
                let message = messageText(from: payload)
                if role == "assistant", !message.isEmpty {
                    snapshot.latestAssistantText = normalizedPreview(message)
                    snapshot.latestActivityText = snapshot.latestAssistantText
                    snapshot.lastAssistantAt = timestamp
                    snapshot.appendTimelineEvent(
                        kind: .assistant,
                        title: String(localized: "Codex 回复"),
                        detail: normalizedPreview(message, limit: 160),
                        timestamp: timestamp
                    )
                } else if role == "user" {
                    snapshot.lastUserAt = timestamp
                    snapshot.latestActivityText = String(localized: "你刚刚发送了新的 Codex 请求。")
                    snapshot.appendTimelineEvent(
                        kind: .user,
                        title: String(localized: "你发送了请求"),
                        detail: normalizedPreview(message, limit: 120),
                        timestamp: timestamp
                    )
                }
                continue
            }

            if object["type"] as? String == "response_item",
               payload["type"] as? String == "function_call",
               let toolName = payload["name"] as? String {
                snapshot.latestActivityText = String(localized: "正在调用工具：\(toolName)")
                snapshot.latestToolName = toolName
                snapshot.appendTimelineEvent(
                    kind: .tool,
                    title: String(localized: "调用工具"),
                    detail: toolName,
                    timestamp: timestamp
                )
                continue
            }

            if payload["type"] as? String == "user_message" {
                snapshot.lastUserAt = timestamp
                snapshot.latestActivityText = String(localized: "你刚刚发送了新的 Codex 请求。")
                snapshot.appendTimelineEvent(
                    kind: .user,
                    title: String(localized: "你发送了请求"),
                    detail: messageText(from: payload),
                    timestamp: timestamp
                )
            }
        }

        return snapshot
    }

    private func taskStage(state: CodexRunState, snapshot: RolloutSnapshot?) -> CodexTaskStage {
        switch state {
        case .waiting:
            return .waiting
        case .done:
            return .completed
        case .idle:
            return .idle
        case .error, .unknown:
            return .unknown
        case .working:
            break
        }

        guard let snapshot else { return .understanding }
        if let toolName = snapshot.latestToolName?.lowercased() {
            if toolName.contains("apply_patch") || toolName.contains("write") || toolName.contains("edit") {
                return .editing
            }
            if toolName.contains("xcodebuild") || toolName.contains("test") || toolName.contains("build") || toolName.contains("swift") {
                return .testing
            }
            if toolName.contains("rg") || toolName.contains("sed") || toolName.contains("cat") || toolName.contains("ls") || toolName.contains("find") {
                return .reading
            }
            return .reading
        }

        if let lastAssistantAt = snapshot.lastAssistantAt,
           let lastUserAt = snapshot.lastUserAt,
           lastAssistantAt > lastUserAt {
            return .summarizing
        }

        return .understanding
    }

    private func taskReport(state: CodexRunState, snapshot: RolloutSnapshot?) -> CodexTaskReport? {
        guard state == .done, let snapshot else { return nil }

        var bullets: [String] = []
        let toolCount = snapshot.timelineEvents.filter { $0.kind == .tool }.count
        let assistantCount = snapshot.timelineEvents.filter { $0.kind == .assistant }.count
        let userCount = snapshot.timelineEvents.filter { $0.kind == .user }.count

        if userCount > 0 {
            bullets.append(String(localized: "收到 \(userCount) 条用户请求"))
        }
        if toolCount > 0 {
            bullets.append(String(localized: "执行 \(toolCount) 次工具操作"))
        }
        if assistantCount > 0 {
            bullets.append(String(localized: "生成 \(assistantCount) 条 Codex 回复"))
        }
        if snapshot.latestAssistantText != nil {
            bullets.append(String(localized: "最新回复已可在灵动岛预览"))
        }
        if bullets.isEmpty {
            bullets.append(String(localized: "Codex 已完成最近一次任务"))
        }

        return CodexTaskReport(
            title: String(localized: "完成战报"),
            bullets: Array(bullets.prefix(4))
        )
    }

    private func messageText(from payload: [String: Any]) -> String {
        guard let content = payload["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private func normalizedPreview(_ text: String, limit: Int = 900) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard collapsed.count > limit else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<end]) + "…"
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.some(let lhs), .some(let rhs)):
            return max(lhs, rhs)
        case (.some(let lhs), .none):
            return lhs
        case (.none, .some(let rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }

    private func recentCodexAuthError() -> String? {
        guard FileManager.default.fileExists(atPath: logsDatabasePath) else { return nil }
        let since = Int(now().timeIntervalSince1970) - 300
        let sql = """
        SELECT feedback_log_body
        FROM logs
        WHERE ts >= \(since)
          AND level IN ('ERROR', 'WARN')
          AND (
            feedback_log_body LIKE '%invalid_refresh_token%'
            OR feedback_log_body LIKE '%Failed to refresh token%'
          )
        ORDER BY ts DESC, ts_nanos DESC
        LIMIT 1;
        """

        guard let output = try? runSQLite(databasePath: logsDatabasePath, sql: sql) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(localized: "Codex 登录状态需要处理。")
    }

    private func runSQLite(databasePath: String, sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\u{1f}", databasePath, sql]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CodexStatusProviderError.sqliteFailed(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private struct ThreadRow {
        let id: String
        let title: String
        let preview: String
        let updatedAtMs: Int64
        let rolloutPath: String?
    }

    private struct RealtimeActivity {
        let threadId: String?
        let timestamp: Int
        let reason: String
    }

    private struct RolloutSnapshot {
        var latestAssistantText: String?
        var latestActivityText: String?
        var lastAssistantAt: Date?
        var lastUserAt: Date?
        var lastActivityAt: Date?
        var latestToolName: String?
        var timelineEvents: [CodexTimelineEvent] = []

        mutating func appendTimelineEvent(
            kind: CodexTimelineEventKind,
            title: String,
            detail: String?,
            timestamp: Date
        ) {
            let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
            let event = CodexTimelineEvent(
                id: "\(timestamp.timeIntervalSince1970)-\(kind.rawValue)-\(title)-\(timelineEvents.count)",
                kind: kind,
                title: title,
                detail: trimmedDetail?.isEmpty == true ? nil : trimmedDetail,
                timestamp: timestamp
            )
            timelineEvents.append(event)
            timelineEvents = Array(timelineEvents.suffix(5))
        }
    }
}

enum CodexStatusProviderError: LocalizedError {
    case invalidSQLiteOutput
    case sqliteFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSQLiteOutput:
            return String(localized: "Codex 本机数据库返回了无法识别的线程数据。")
        case .sqliteFailed(let message):
            return message.isEmpty
                ? String(localized: "Codex 本机数据库查询失败。")
                : message
        }
    }
}

struct MockFileCodexStatusProvider: CodexStatusProvider {
    let filePath: String

    func currentThreadStatus() async -> CodexThreadStatus {
        let trimmedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return CodexThreadStatus.unavailable
        }

        let url = URL(fileURLWithPath: trimmedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CodexThreadStatus(
                threadId: nil,
                title: nil,
                state: .unknown,
                summary: nil,
                lastUpdatedAt: Date(),
                workingStartedAt: nil,
                sourceAvailability: .error(message: String(localized: "备用 mock 状态文件不存在。"))
            )
        }

        do {
            let data = try Data(contentsOf: url)
            var status = try JSONDecoder.codexStatusDecoder.decode(CodexThreadStatus.self, from: data)
            if status.sourceAvailability != .available {
                status.sourceAvailability = .available
            }
            return status
        } catch {
            return CodexThreadStatus(
                threadId: nil,
                title: nil,
                state: .unknown,
                summary: nil,
                lastUpdatedAt: Date(),
                workingStartedAt: nil,
                sourceAvailability: .error(message: error.localizedDescription)
            )
        }
    }
}

extension JSONDecoder {
    static var codexStatusDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
