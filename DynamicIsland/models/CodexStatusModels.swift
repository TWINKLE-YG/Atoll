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

enum CodexRunState: String, Codable, CaseIterable, Defaults.Serializable {
    case idle
    case working
    case waiting
    case done
    case error
    case unknown

    var label: String {
        switch self {
        case .idle: return String(localized: "空闲")
        case .working: return String(localized: "工作中")
        case .waiting: return String(localized: "等待你处理")
        case .done: return String(localized: "已完成")
        case .error: return String(localized: "异常")
        case .unknown: return String(localized: "未知")
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "circle"
        case .working: return "sparkles"
        case .waiting: return "person.crop.circle.badge.questionmark"
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var accentColor: Color {
        switch self {
        case .idle: return .secondary
        case .working: return .cyan
        case .waiting: return .orange
        case .done: return .green
        case .error: return .red
        case .unknown: return .gray
        }
    }

    var isActive: Bool {
        self == .working || self == .waiting
    }
}

enum CodexSourceAvailability: Equatable, Codable {
    case available
    case codexNotRunning
    case permissionDenied
    case unsupported
    case error(message: String)

    var label: String {
        switch self {
        case .available: return String(localized: "可用")
        case .codexNotRunning: return String(localized: "Codex 未运行")
        case .permissionDenied: return String(localized: "需要权限")
        case .unsupported: return String(localized: "暂不支持")
        case .error: return String(localized: "异常")
        }
    }

    var detail: String {
        switch self {
        case .available:
            return String(localized: "Codex 状态来源可用。")
        case .codexNotRunning:
            return String(localized: "打开 Codex 桌面 App 后即可显示当前线程状态。")
        case .permissionDenied:
            return String(localized: "Atoll 当前权限不足，无法读取 Codex 状态。")
        case .unsupported:
            return String(localized: "尚未配置稳定的 Codex 本机状态来源。")
        case .error(let message):
            return message
        }
    }
}

enum CodexPrivacyMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case minimal
    case summary
    case detailed

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .minimal: return String(localized: "极简")
        case .summary: return String(localized: "摘要")
        case .detailed: return String(localized: "详细")
        }
    }

    var allowsSummary: Bool {
        self == .summary || self == .detailed
    }
}

enum CodexTimelineEventKind: String, Codable {
    case user
    case assistant
    case tool
    case status
}

struct CodexTimelineEvent: Equatable, Codable, Identifiable {
    var id: String
    var kind: CodexTimelineEventKind
    var title: String
    var detail: String?
    var timestamp: Date

    var systemImage: String {
        switch kind {
        case .user: return "person.crop.circle"
        case .assistant: return "sparkles"
        case .tool: return "terminal"
        case .status: return "waveform.path"
        }
    }

    var accentColor: Color {
        switch kind {
        case .user: return .blue
        case .assistant: return .cyan
        case .tool: return .purple
        case .status: return .secondary
        }
    }
}

enum CodexHealthLevel {
    case good
    case warning
    case broken

    var accentColor: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .broken: return .red
        }
    }
}

struct CodexHealthReport {
    var level: CodexHealthLevel
    var title: String
    var detail: String
}

enum CodexTaskStage: String, Codable {
    case understanding
    case reading
    case editing
    case testing
    case waiting
    case summarizing
    case completed
    case idle
    case unknown

    var label: String {
        switch self {
        case .understanding: return String(localized: "理解需求")
        case .reading: return String(localized: "读取代码")
        case .editing: return String(localized: "修改文件")
        case .testing: return String(localized: "运行验证")
        case .waiting: return String(localized: "等待确认")
        case .summarizing: return String(localized: "总结结果")
        case .completed: return String(localized: "任务完成")
        case .idle: return String(localized: "空闲")
        case .unknown: return String(localized: "判断中")
        }
    }

    var systemImage: String {
        switch self {
        case .understanding: return "brain.head.profile"
        case .reading: return "doc.text.magnifyingglass"
        case .editing: return "pencil.and.outline"
        case .testing: return "checklist.checked"
        case .waiting: return "person.crop.circle.badge.questionmark"
        case .summarizing: return "text.alignleft"
        case .completed: return "checkmark.seal.fill"
        case .idle: return "circle"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct CodexTaskReport: Equatable, Codable {
    var title: String
    var bullets: [String]
}

struct CodexSessionSummary: Equatable, Codable, Identifiable {
    var id: String
    var title: String?
    var state: CodexRunState
    var summary: String?
    var taskStage: CodexTaskStage
    var lastUpdatedAt: Date?
    var workingStartedAt: Date?
    var isPrimary: Bool

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized: "Codex 会话") : trimmed
    }

    func displaySummary(privacyMode: CodexPrivacyMode) -> String? {
        guard privacyMode.allowsSummary else { return nil }
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var elapsedWorkingTime: TimeInterval? {
        guard let workingStartedAt, state.isActive else { return nil }
        return max(0, Date().timeIntervalSince(workingStartedAt))
    }
}

struct CodexThreadStatus: Equatable, Codable {
    var threadId: String?
    var title: String?
    var state: CodexRunState
    var summary: String?
    var latestAssistantText: String? = nil
    var latestActivityText: String? = nil
    var timelineEvents: [CodexTimelineEvent] = []
    var taskStage: CodexTaskStage = .unknown
    var taskReport: CodexTaskReport? = nil
    var relatedSessions: [CodexSessionSummary] = []
    var lastUpdatedAt: Date?
    var workingStartedAt: Date?
    var sourceAvailability: CodexSourceAvailability

    static let unavailable = CodexThreadStatus(
        threadId: nil,
        title: nil,
        state: .unknown,
        summary: nil,
        lastUpdatedAt: nil,
        workingStartedAt: nil,
        sourceAvailability: .unsupported
    )

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized: "Codex") : trimmed
    }

    func displaySummary(privacyMode: CodexPrivacyMode) -> String? {
        guard privacyMode.allowsSummary else { return nil }
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func displayAssistantText(privacyMode: CodexPrivacyMode) -> String? {
        guard privacyMode == .detailed else { return nil }
        let trimmed = latestAssistantText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func displayActivityText(privacyMode: CodexPrivacyMode) -> String? {
        guard privacyMode.allowsSummary else { return nil }
        let trimmed = latestActivityText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func displayTimelineEvents(privacyMode: CodexPrivacyMode) -> [CodexTimelineEvent] {
        guard privacyMode.allowsSummary else { return [] }
        return timelineEvents
    }

    var activeSessionCount: Int {
        relatedSessions.filter { $0.state.isActive }.count
    }

    var hasMultipleSessions: Bool {
        relatedSessions.count > 1
    }

    var elapsedWorkingTime: TimeInterval? {
        guard let workingStartedAt, state.isActive else { return nil }
        return max(0, Date().timeIntervalSince(workingStartedAt))
    }

    var healthReport: CodexHealthReport {
        switch sourceAvailability {
        case .available:
            break
        case .codexNotRunning:
            return CodexHealthReport(
                level: .warning,
                title: String(localized: "Codex 未运行"),
                detail: String(localized: "启动 Codex 后，Atoll 才能读取当前线程。")
            )
        case .permissionDenied:
            return CodexHealthReport(
                level: .broken,
                title: String(localized: "读取权限不足"),
                detail: String(localized: "Atoll 当前无法读取 Codex 本机状态。")
            )
        case .unsupported:
            return CodexHealthReport(
                level: .warning,
                title: String(localized: "状态源未就绪"),
                detail: String(localized: "还没有可用的 Codex 状态来源。")
            )
        case .error(let message):
            return CodexHealthReport(
                level: .broken,
                title: String(localized: "状态读取异常"),
                detail: message
            )
        }

        guard let lastUpdatedAt else {
            return CodexHealthReport(
                level: .warning,
                title: String(localized: "等待首次数据"),
                detail: String(localized: "Atoll 正在等待 Codex 写入本机状态。")
            )
        }

        let age = Date().timeIntervalSince(lastUpdatedAt)
        if age > 60 {
            return CodexHealthReport(
                level: .warning,
                title: String(localized: "状态明显延迟"),
                detail: String(localized: "最近一次 Codex 数据更新已经超过 1 分钟。")
            )
        }

        if state == .unknown {
            return CodexHealthReport(
                level: .warning,
                title: String(localized: "状态仍在判断"),
                detail: String(localized: "Atoll 已读取到数据，但暂时无法确定 Codex 运行阶段。")
            )
        }

        return CodexHealthReport(
            level: .good,
            title: String(localized: "读取正常"),
            detail: String(localized: "Atoll 可以读取 Codex 状态和最近活动。")
        )
    }
}
