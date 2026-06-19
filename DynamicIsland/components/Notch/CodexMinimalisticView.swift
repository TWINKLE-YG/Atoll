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

import SwiftUI

struct CodexMinimalisticView: View {
    let status: CodexThreadStatus
    var compact: Bool = false
    var action: () -> Void = { CodexAppLauncher.openCodex() }
    @State private var pulse = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: compact ? 0 : 6) {
                Image(systemName: status.state.systemImage)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(status.state.accentColor)
                    .scaleEffect(shouldPulse ? (pulse ? 1.16 : 0.96) : 1)
                    .opacity(shouldPulse ? (pulse ? 1 : 0.72) : 1)
                if !compact {
                    Text("Codex")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    if status.hasMultipleSessions {
                        Text(sessionBadgeText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(status.activeSessionCount > 1 ? .orange : status.state.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background((status.activeSessionCount > 1 ? Color.orange : status.state.accentColor).opacity(0.16), in: Capsule())
                    }
                    Text(shortStatusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(status.state == .error ? .red : .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 62, alignment: .leading)
                        .truncationMode(.tail)
                }
            }
        }
        .buttonStyle(.plain)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(compact ? 5 : 0)
        .background {
            if compact {
                Circle()
                    .fill(Color.black.opacity(0.72))
                    .overlay(Circle().stroke(status.state.accentColor.opacity(0.35), lineWidth: 1))
            }
        }
        .accessibilityLabel("Codex \(status.state.label)")
        .help(compact ? "查看 Codex" : "打开 Codex")
        .onAppear {
            pulse = shouldPulse
        }
        .onChange(of: status.state) { _, _ in
            pulse = shouldPulse
        }
        .animation(
            shouldPulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
            value: pulse
        )
    }

    private var shouldPulse: Bool {
        status.state == .waiting || status.state == .error
    }

    private var shortStatusText: String {
        switch status.state {
        case .working:
            return status.activeSessionCount > 1 ? "多线回复" : "回复中"
        case .waiting:
            return "等你处理"
        case .done:
            return "已完成"
        case .error:
            return "需关注"
        case .idle:
            return "空闲"
        case .unknown:
            return "检测中"
        }
    }

    private var sessionBadgeText: String {
        let activeCount = status.activeSessionCount
        if activeCount > 1 {
            return "\(activeCount)活跃"
        }
        return "+\(max(0, status.relatedSessions.count - 1))"
    }
}
