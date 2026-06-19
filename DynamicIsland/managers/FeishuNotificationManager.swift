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
import SwiftUI

@MainActor
final class FeishuNotificationManager: ObservableObject {
    static let shared = FeishuNotificationManager()

    @Published private(set) var status = FeishuNotificationStatus()

    private var monitorTask: Task<Void, Never>?
    private var seenIDs = Set<String>()
    private let scanner = LocalNotificationScanner()
    private let coordinator = DynamicIslandViewCoordinator.shared

    private init() {}

    func start() {
        guard Defaults[.enableFeishuNotifications] else {
            stop()
            return
        }
        guard monitorTask == nil else { return }

        FeishuDebugLogger.log("飞书通知监听启动 interval=\(Defaults[.feishuPollInterval]) bundle=\(Bundle.main.bundleIdentifier ?? "unknown") path=\(Bundle.main.bundlePath)")
        status.availability = .available
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshOnce()
                try? await Task.sleep(for: .seconds(self.nextPollInterval()))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        seenIDs.removeAll()
        status = FeishuNotificationStatus()
        FeishuDebugLogger.log("飞书通知监听停止")
    }

    func refreshOnce() async {
        guard Defaults[.enableFeishuNotifications] else { return }

        do {
            let records = try await Task.detached(priority: .utility) {
                try self.scanner.recentNotifications(limit: 30)
            }.value
            status.availability = .available
            status.lastCheckedAt = Date()

            guard let event = classify(records: records) else { return }
            apply(event)
        } catch LocalNotificationScanner.ScannerError.permissionDenied {
            status.availability = .permissionRequired
            status.lastCheckedAt = Date()
            FeishuDebugLogger.log("读取本机通知失败 reason=permissionDenied")
        } catch {
            status.availability = .error(error.localizedDescription)
            status.lastCheckedAt = Date()
            FeishuDebugLogger.log("读取本机通知失败 message=\(error.localizedDescription)")
        }
    }

    func markAllRead() {
        status.hasMention = false
        status.unreadCount = 0
        FeishuDebugLogger.log("用户清空飞书提醒")
    }

    private func nextPollInterval() -> TimeInterval {
        let configured = Defaults[.feishuPollInterval]
        let minimum = Defaults[.lowResourceMode] ? 8.0 : 1.0
        switch status.availability {
        case .permissionRequired, .error:
            return max(30.0, configured)
        case .idle:
            return max(15.0, configured)
        case .available:
            return max(minimum, configured)
        }
    }

    private func classify(records: [LocalNotificationRecord]) -> FeishuNotificationEvent? {
        let mentionKeywords = keywords(from: Defaults[.feishuMentionKeywords])
        let directKeywords = keywords(from: Defaults[.feishuDirectMessageKeywords])
        let allowedSenders = keywords(from: Defaults[.feishuAllowedSenderKeywords])
        let allowedConversations = keywords(from: Defaults[.feishuAllowedConversationKeywords])
        let blockedKeywords = keywords(from: Defaults[.feishuBlockedKeywords])

        for record in records.sorted(by: { $0.receivedAt > $1.receivedAt }) {
            guard !seenIDs.contains(record.id), record.isFeishuLike else { continue }

            let text = "\(record.title)\n\(record.subtitle)\n\(record.body)".lowercased()
            let identity = FeishuNotificationIdentity(record: record)
            let filterText = "\(identity.sender)\n\(identity.conversation)\n\(text)"
            let kind: FeishuNotificationKind?
            if mentionKeywords.contains(where: { text.contains($0.lowercased()) }) {
                kind = .mention
            } else if directKeywords.contains(where: { text.contains($0.lowercased()) }) || record.isLikelyDirectMessage {
                kind = .directMessage
            } else {
                kind = nil
            }

            seenIDs.insert(record.id)
            trimSeenIDs()

            if let blocked = firstMatch(in: blockedKeywords, text: filterText) {
                FeishuDebugLogger.log("忽略飞书通知 reason=blocked keyword=\(blocked) title=\(record.title)")
                continue
            }

            guard let kind else {
                FeishuDebugLogger.log("忽略飞书通知 reason=no-keyword title=\(record.title)")
                continue
            }

            guard let matchReason = filterMatchReason(
                identity: identity,
                text: filterText,
                allowedSenders: allowedSenders,
                allowedConversations: allowedConversations
            ) else {
                FeishuDebugLogger.log("忽略飞书通知 reason=not-allowed sender=\(identity.sender) conversation=\(identity.conversation)")
                continue
            }

            return FeishuNotificationEvent(
                id: record.id,
                title: record.title.isEmpty ? record.subtitle : record.title,
                body: record.body,
                source: record.bundleIdentifier,
                kind: kind,
                receivedAt: record.receivedAt,
                sender: identity.sender,
                conversation: identity.conversation,
                matchReason: matchReason
            )
        }

        return nil
    }

    private func apply(_ event: FeishuNotificationEvent) {
        status.hasMention = true
        status.unreadCount += 1
        status.latestEvent = event
        status.recentEvents = ([event] + status.recentEvents.filter { $0.id != event.id })
            .prefix(clampedPriorityQueueLimit())
            .map { $0 }
        FeishuDebugLogger.log("命中飞书提醒 kind=\(event.kind.rawValue) title=\(event.displayTitle) reason=\(event.matchReason)")

        coordinator.toggleSneakPeek(
            status: true,
            type: .feishu,
            duration: status.recentEvents.count > 1 ? 8 : 6,
            icon: event.kind.systemImage,
            title: event.displayTitle,
            subtitle: event.displayBody(showPreview: Defaults[.feishuShowMessagePreview]),
            accentColor: .cyan,
            styleOverride: .standard
        )
    }

    private func filterMatchReason(
        identity: FeishuNotificationIdentity,
        text: String,
        allowedSenders: [String],
        allowedConversations: [String]
    ) -> String? {
        if let sender = firstMatch(in: allowedSenders, text: identity.sender) ?? firstMatch(in: allowedSenders, text: text) {
            return "联系人：\(sender)"
        }
        if let conversation = firstMatch(in: allowedConversations, text: identity.conversation) ?? firstMatch(in: allowedConversations, text: text) {
            return "群聊：\(conversation)"
        }
        if allowedSenders.isEmpty && allowedConversations.isEmpty {
            return "默认提醒"
        }
        return nil
    }

    private func firstMatch(in keywords: [String], text: String) -> String? {
        let loweredText = text.lowercased()
        return keywords.first { keyword in
            loweredText.contains(keyword.lowercased())
        }
    }

    private func clampedPriorityQueueLimit() -> Int {
        min(max(Defaults[.feishuPriorityQueueLimit], 1), 6)
    }

    private func keywords(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func trimSeenIDs() {
        guard seenIDs.count > 200 else { return }
        seenIDs = Set(seenIDs.suffix(120))
    }
}

enum FeishuDebugLogger {
    static let logFileURL: URL = {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Atoll", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("feishu-debug.log")
    }()

    static func log(_ message: String) {
        guard Defaults[.feishuDebugLoggingEnabled] else { return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logFileURL.path),
           let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }
}

private struct LocalNotificationScanner {
    enum ScannerError: LocalizedError {
        case databaseNotFound
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .databaseNotFound:
                return String(localized: "没有找到 macOS 本机通知数据库。")
            case .permissionDenied:
                return String(localized: "无法读取 macOS 本机通知数据库。")
            }
        }
    }

    func recentNotifications(limit: Int) throws -> [LocalNotificationRecord] {
        let databasePath = try copiedNotificationDatabasePath()
        return try notificationRecords(databasePath: databasePath, limit: limit)
    }

    private func copiedNotificationDatabasePath() throws -> String {
        let sourcePath = try notificationDatabasePath()
        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ScannerError.databaseNotFound
        }
        let targetDirectory = applicationSupportURL
            .appendingPathComponent("Atoll", isDirectory: true)
            .appendingPathComponent("FeishuNotifications", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        } catch {
            throw ScannerError.databaseNotFound
        }

        let targetURL = targetDirectory.appendingPathComponent("notifications.sqlite")
        FeishuDebugLogger.log("准备复制本机通知库 source=\(sourceURL.path) target=\(targetURL.path)")
        try copySQLiteFile(from: sourceURL, to: targetURL)
        try copySQLiteSidecarIfPresent(from: sourceURL, to: targetURL, suffix: "-wal")
        try copySQLiteSidecarIfPresent(from: sourceURL, to: targetURL, suffix: "-shm")
        return targetURL.path
    }

    private func copySQLiteSidecarIfPresent(from sourceURL: URL, to targetURL: URL, suffix: String) throws {
        let sourceSidecar = URL(fileURLWithPath: sourceURL.path + suffix)
        guard FileManager.default.fileExists(atPath: sourceSidecar.path) else { return }
        let targetSidecar = URL(fileURLWithPath: targetURL.path + suffix)
        try copySQLiteFile(from: sourceSidecar, to: targetSidecar)
    }

    private func copySQLiteFile(from sourceURL: URL, to targetURL: URL) throws {
        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        } catch {
            let nsError = error as NSError
            let message = nsError.localizedDescription
            FeishuDebugLogger.log("复制本机通知库失败 domain=\(nsError.domain) code=\(nsError.code) source=\(sourceURL.path) target=\(targetURL.path) message=\(message)")
            if message.localizedCaseInsensitiveContains("operation not permitted")
                || message.localizedCaseInsensitiveContains("permission")
                || message.localizedCaseInsensitiveContains("没有访问")
                || message.localizedCaseInsensitiveContains("许可") {
                throw ScannerError.permissionDenied
            }
            throw error
        }
    }

    private func notificationDatabasePath() throws -> String {
        let base = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted"
        let candidates = [
            "\(base)/db2/db",
            "\(base)/db/db",
            "\(base)/db2/db.sqlite",
            "\(base)/db/db.sqlite"
        ]

        if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return path
        }

        throw ScannerError.databaseNotFound
    }

    private func notificationRecords(databasePath: String, limit: Int) throws -> [LocalNotificationRecord] {
        let sql = """
        SELECT r.rec_id, a.identifier, hex(r.uuid), hex(r.data), coalesce(r.delivered_date, r.request_date, 0)
        FROM record r
        LEFT JOIN app a ON a.app_id = r.app_id
        ORDER BY r.rec_id DESC
        LIMIT \(max(limit * 6, 80));
        """
        let output = try runSQLite(databasePath: databasePath, sql: sql)
        let records = output
            .split(whereSeparator: \.isNewline)
            .compactMap(parseNotificationRecord)
            .filter(\.isFeishuLike)

        FeishuDebugLogger.log("本机通知库解析完成 records=\(records.count)")
        return Array(records.sorted(by: { $0.receivedAt > $1.receivedAt }).prefix(limit))
    }

    private func parseNotificationRecord(_ row: Substring) -> LocalNotificationRecord? {
        let fields = String(row).components(separatedBy: "\u{1f}")
        guard fields.count >= 5 else { return nil }

        let recordID = fields[0]
        let bundleIdentifier = fields[1]
        let uuidHex = fields[2]
        let dataHex = fields[3]
        let deliveredAt = Double(fields[4]).map(Date.init(timeIntervalSinceReferenceDate:)) ?? Date()

        guard let payload = decodedNotificationPayload(fromHex: dataHex) else { return nil }
        let request = payload["req"] as? [String: Any]
        let payloadApp = payload["app"] as? String
        let title = stringValue(request?["titl"]) ?? stringValue(payload["titl"]) ?? payloadApp ?? bundleIdentifier
        let subtitle = stringValue(request?["subt"]) ?? stringValue(payload["subt"]) ?? ""
        let body = stringValue(request?["body"]) ?? stringValue(payload["body"]) ?? ""
        let notificationID = stringValue(request?["iden"]) ?? stringValue(payload["iden"]) ?? uuidHex
        let source = payloadApp ?? bundleIdentifier

        return LocalNotificationRecord(
            id: notificationID.isEmpty ? recordID : notificationID,
            bundleIdentifier: source,
            title: normalized(title, limit: 90),
            subtitle: normalized(subtitle, limit: 90),
            body: normalized(body, limit: 300),
            receivedAt: deliveredAt
        )
    }

    private func decodedNotificationPayload(fromHex hex: String) -> [String: Any]? {
        guard let data = data(fromHex: hex) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private func data(fromHex hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        return string.isEmpty ? nil : string
    }

    private func normalized(_ value: String, limit: Int) -> String {
        let clean = value
            .replacingOccurrences(of: "\0", with: " ")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit)) + "..."
    }

    private func quoteIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func runSQLite(databasePath: String, sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\u{1f}", databasePath, sql]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            if (error as NSError).localizedDescription.localizedCaseInsensitiveContains("operation not permitted") {
                throw ScannerError.permissionDenied
            }
            throw error
        }
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if errorOutput.localizedCaseInsensitiveContains("authorization denied")
                || errorOutput.localizedCaseInsensitiveContains("operation not permitted") {
                throw ScannerError.permissionDenied
            }
            throw ScannerError.databaseNotFound
        }
        return output
    }
}

private struct FeishuNotificationIdentity {
    let sender: String
    let conversation: String

    init(record: LocalNotificationRecord) {
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = record.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = record.body.trimmingCharacters(in: .whitespacesAndNewlines)

        let parsed = Self.parseTitle(title)
        sender = parsed.sender ?? Self.bestFallback(from: [subtitle, title, body])
        conversation = parsed.conversation ?? subtitle
    }

    private static func parseTitle(_ title: String) -> (sender: String?, conversation: String?) {
        let separators = [" | ", "｜", " - ", " — ", " – ", "：", ": "]
        for separator in separators {
            let parts = title.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            return (parts.last, parts.dropLast().joined(separator: " "))
        }
        return (title.isEmpty ? nil : title, nil)
    }

    private static func bestFallback(from values: [String]) -> String {
        values.first { !$0.isEmpty } ?? String(localized: "飞书")
    }
}

private struct LocalNotificationRecord {
    let id: String
    let bundleIdentifier: String
    let title: String
    let subtitle: String
    let body: String
    let receivedAt: Date

    var isFeishuLike: Bool {
        let value = "\(bundleIdentifier)\n\(title)\n\(subtitle)\n\(body)"
        return value.localizedCaseInsensitiveContains("feishu")
            || value.localizedCaseInsensitiveContains("lark")
            || value.localizedCaseInsensitiveContains("飞书")
    }

    var isLikelyDirectMessage: Bool {
        let text = "\(title)\n\(body)"
        return !text.contains("@") && body.count > 0
    }
}
