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

enum CodexDiagnosticsExporter {
    static func export(status: CodexThreadStatus) throws -> URL {
        let fileManager = FileManager.default
        let timestamp = Self.timestampFormatter.string(from: Date())
        let folderURL = fileManager.temporaryDirectory
            .appendingPathComponent("AtollCodexDiagnostics-\(timestamp)", isDirectory: true)
        let zipURL = fileManager.temporaryDirectory
            .appendingPathComponent("AtollCodexDiagnostics-\(timestamp).zip")

        if fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.removeItem(at: folderURL)
        }
        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try writeStatus(status, to: folderURL.appendingPathComponent("codex-status.json"))
        try writeEnvironment(status, to: folderURL.appendingPathComponent("environment.txt"))
        try copyDebugLog(to: folderURL)

        try zip(folderURL: folderURL, zipURL: zipURL)
        CodexDebugLogger.log("已导出 Codex 诊断包 path=\(zipURL.path)")
        return zipURL
    }

    private static func writeStatus(_ status: CodexThreadStatus, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)
        try data.write(to: url)
    }

    private static func writeEnvironment(_ status: CodexThreadStatus, to url: URL) throws {
        let health = status.healthReport
        let lines = [
            "createdAt=\(ISO8601DateFormatter().string(from: Date()))",
            "threadId=\(status.threadId ?? "")",
            "state=\(status.state.rawValue)",
            "taskStage=\(status.taskStage.rawValue)",
            "taskReport=\(status.taskReport?.bullets.joined(separator: " | ") ?? "")",
            "source=\(status.sourceAvailability.label)",
            "health=\(health.title)",
            "healthDetail=\(health.detail)",
            "lastUpdatedAt=\(status.lastUpdatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "")",
            "debugLoggingEnabled=\(Defaults[.codexDebugLoggingEnabled])",
            "activeRefreshInterval=\(Defaults[.codexActiveRefreshInterval])",
            "idleRefreshInterval=\(Defaults[.codexIdleRefreshInterval])",
            "privacyMode=\(Defaults[.codexPrivacyMode].rawValue)",
            "debugLogPath=\(CodexDebugLogger.logFileURL.path)"
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func copyDebugLog(to folderURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: CodexDebugLogger.logFileURL.path) else { return }
        try fileManager.copyItem(
            at: CodexDebugLogger.logFileURL,
            to: folderURL.appendingPathComponent("codex-debug.log")
        )
    }

    private static func zip(folderURL: URL, zipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folderURL.path, zipURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "CodexDiagnosticsExporter",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "诊断包压缩失败。" : message]
            )
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
