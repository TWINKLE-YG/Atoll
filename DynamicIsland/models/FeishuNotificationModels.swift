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

import Foundation
import SwiftUI

enum FeishuNotificationAvailability: Equatable {
    case idle
    case available
    case permissionRequired
    case error(String)

    var label: String {
        switch self {
        case .idle: return String(localized: "未启用")
        case .available: return String(localized: "监听中")
        case .permissionRequired: return String(localized: "需要授权")
        case .error: return String(localized: "异常")
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return String(localized: "飞书本地通知监听未启用。")
        case .available:
            return String(localized: "正在读取本机通知记录，识别飞书 @你 和私聊。")
        case .permissionRequired:
            return String(localized: "macOS 不允许读取通知数据库。请给 Atoll 开启完全磁盘访问权限。")
        case .error(let message):
            return message
        }
    }

    var accentColor: Color {
        switch self {
        case .idle: return .secondary
        case .available: return .green
        case .permissionRequired: return .orange
        case .error: return .red
        }
    }
}

enum FeishuNotificationKind: String, Codable {
    case mention
    case directMessage

    var label: String {
        switch self {
        case .mention: return String(localized: "@你")
        case .directMessage: return String(localized: "私聊")
        }
    }

    var systemImage: String {
        switch self {
        case .mention: return "at"
        case .directMessage: return "bubble.left.and.bubble.right"
        }
    }
}

struct FeishuNotificationEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let source: String
    let kind: FeishuNotificationKind
    let receivedAt: Date
    let sender: String
    let conversation: String
    let matchReason: String

    var displayTitle: String {
        let senderText = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleText = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !senderText.isEmpty { return senderText }
        if !titleText.isEmpty { return titleText }
        return String(localized: "飞书")
    }

    func displayBody(showPreview: Bool) -> String {
        guard showPreview else {
            return String(localized: "有一条飞书消息需要你关注。")
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.label : trimmed
    }

    var contextLine: String {
        let conversationText = conversation.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonText = matchReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !conversationText.isEmpty && !reasonText.isEmpty {
            return "\(conversationText) · \(reasonText)"
        }
        if !conversationText.isEmpty { return conversationText }
        if !reasonText.isEmpty { return reasonText }
        return kind.label
    }
}

struct FeishuNotificationStatus: Equatable {
    var hasMention: Bool = false
    var unreadCount: Int = 0
    var latestEvent: FeishuNotificationEvent?
    var recentEvents: [FeishuNotificationEvent] = []
    var lastCheckedAt: Date?
    var availability: FeishuNotificationAvailability = .idle

    var accentColor: Color {
        if hasMention { return .cyan }
        return availability.accentColor
    }

    var title: String {
        if let latestEvent {
            return latestEvent.kind.label
        }
        return String(localized: "飞书")
    }

    func summary(showPreview: Bool) -> String {
        guard let latestEvent else {
            return availability.detail
        }
        return latestEvent.displayBody(showPreview: showPreview)
    }
}
