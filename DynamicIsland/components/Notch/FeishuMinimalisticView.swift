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
import SwiftUI

struct FeishuMinimalisticView: View {
    let status: FeishuNotificationStatus
    var compact = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 0 : 5) {
                Image(systemName: status.latestEvent?.kind.systemImage ?? "message.badge")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(status.accentColor)

                if !compact {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .frame(width: compact ? 22 : nil, height: compact ? 22 : 24)
            .padding(.horizontal, compact ? 0 : 7)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(
                Capsule().stroke(status.accentColor.opacity(0.26), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("查看飞书提醒")
    }

    private var label: String {
        if status.recentEvents.count > 1 {
            return "\(status.recentEvents.count) 条"
        }
        if let sender = status.latestEvent?.displayTitle, !sender.isEmpty {
            return sender
        }
        return status.unreadCount > 0 ? "\(status.unreadCount)" : "飞书"
    }
}
