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
import AppKit
import SwiftUI

private enum CodexPanelTypography {
    static let headerTitle: CGFloat = 13
    static let headerStatus: CGFloat = 10
    static let sectionTitle: CGFloat = 10
    static let body: CGFloat = 11
    static let compact: CGFloat = 9
    static let badge: CGFloat = 8
    static let preview: CGFloat = 12
}

struct NotchCodexView: View {
    @ObservedObject private var manager = CodexManager.shared
    @Default(.codexPrivacyMode) private var privacyMode
    @Default(.codexDebugLoggingEnabled) private var debugLoggingEnabled
    @Default(.codexSessionListLimit) private var sessionListLimit
    @State private var isRefreshing = false
    @State private var copiedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            ScrollView(.vertical, showsIndicators: true) {
                statusBody
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            manager.start()
            await manager.refreshOnce()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await manager.refreshOnce()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            statusGlyph

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex")
                    .font(.system(size: CodexPanelTypography.headerTitle, weight: .semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(manager.status.state.accentColor)
                        .frame(width: 5, height: 5)
                    Text(manager.status.state.label)
                        .font(.system(size: CodexPanelTypography.headerStatus, weight: .medium))
                        .foregroundStyle(manager.status.state.accentColor)
                }
            }

            Spacer(minLength: 0)

            if let lastUpdatedAt = manager.status.lastUpdatedAt {
                Text(freshnessText(for: lastUpdatedAt))
                    .font(.system(size: CodexPanelTypography.compact, weight: .medium))
                    .foregroundStyle(isStale(lastUpdatedAt) ? .orange : .secondary)
            }

            headerIconButton(
                systemName: isRefreshing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise",
                help: "立即刷新"
            ) {
                refreshNow()
            }

            headerIconButton(systemName: "arrow.up.forward.app", help: "打开 Codex") {
                CodexAppLauncher.openCodex()
            }
        }
    }

    private var statusGlyph: some View {
        Image(systemName: manager.status.state.systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(manager.status.state.accentColor)
            .frame(width: 28, height: 28)
            .background(manager.status.state.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(manager.status.state.accentColor.opacity(0.22), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var statusBody: some View {
        switch manager.status.sourceAvailability {
        case .available:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    radarCorePanel
                        .frame(width: 158)
                    sessionOverviewPanel
                }

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        stagePanel
                        healthPanel
                    }
                    .frame(width: 188)

                    VStack(alignment: .leading, spacing: 8) {
                        previewPanel
                        taskReportPanel
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                timelinePanel

                footer
            }
        case .codexNotRunning, .permissionDenied, .unsupported, .error:
            VStack(alignment: .leading, spacing: 8) {
                unavailableBody
                healthPanel
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let elapsed = manager.status.elapsedWorkingTime {
                footerItem(icon: "clock", text: formatElapsed(elapsed))
            }

            if let activity = manager.status.displayActivityText(privacyMode: privacyMode) {
                footerItem(icon: "waveform.path", text: activity)
                    .lineLimit(1)
            }

            if debugLoggingEnabled {
                footerItem(icon: "ladybug", text: "Debug")
            }

            if let lastUpdatedAt = manager.status.lastUpdatedAt, isStale(lastUpdatedAt) {
                footerItem(icon: "exclamationmark.circle", text: "数据可能延迟")
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: CodexPanelTypography.compact, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private func footerItem(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .labelStyle(.titleAndIcon)
    }

    private var sessionCountText: String {
        let activeCount = manager.status.activeSessionCount
        if activeCount > 1 {
            return "\(activeCount) 个活跃"
        }
        return "\(manager.status.relatedSessions.count) 个最近会话"
    }

    @ViewBuilder
    private var sessionOverviewPanel: some View {
        let sessions = manager.status.relatedSessions
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label("会话雷达", systemImage: "scope")
                        .font(.system(size: CodexPanelTypography.sectionTitle, weight: .semibold))
                        .foregroundStyle(manager.status.state.accentColor)

                    Spacer(minLength: 0)

                    Text(sessionCountText)
                        .font(.system(size: CodexPanelTypography.compact, weight: .semibold))
                        .foregroundStyle(manager.status.activeSessionCount > 1 ? .orange : .secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(sessions.prefix(clampedSessionListLimit))) { session in
                            sessionRadarCard(session)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 98, alignment: .topLeading)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var clampedSessionListLimit: Int {
        min(max(sessionListLimit, 1), 6)
    }

    private var radarCorePanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(manager.status.state.accentColor.opacity(0.18), lineWidth: 1)
                    Circle()
                        .fill(manager.status.state.accentColor.opacity(0.1))
                    Image(systemName: manager.status.state.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(manager.status.state.accentColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.status.state.label)
                        .font(.system(size: CodexPanelTypography.body, weight: .semibold))
                        .foregroundStyle(manager.status.state.accentColor)
                    Text(manager.status.taskStage.label)
                        .font(.system(size: CodexPanelTypography.compact, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            HStack(spacing: 10) {
                radarMetric(title: "活跃", value: "\(manager.status.activeSessionCount)")
                radarMetric(title: "最近", value: "\(manager.status.relatedSessions.count)")
                if let elapsed = manager.status.elapsedWorkingTime {
                    radarMetric(title: "耗时", value: formatElapsed(elapsed))
                }
            }
        }
        .frame(height: 98, alignment: .topLeading)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(manager.status.state.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(manager.status.state.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private func radarMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: CodexPanelTypography.body, weight: .bold))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: CodexPanelTypography.badge, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionRadarCard(_ session: CodexSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.state.accentColor)
                    .frame(width: session.state.isActive ? 7 : 6, height: session.state.isActive ? 7 : 6)
                    .shadow(color: session.state.accentColor.opacity(session.state.isActive ? 0.75 : 0.15), radius: session.state.isActive ? 5 : 1)

                Text(session.state.label)
                    .font(.system(size: CodexPanelTypography.compact, weight: .semibold))
                    .foregroundStyle(session.state.accentColor)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if session.isPrimary {
                    Text("当前")
                        .font(.system(size: CodexPanelTypography.badge, weight: .bold))
                        .foregroundStyle(manager.status.state.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(manager.status.state.accentColor.opacity(0.14), in: Capsule())
                }
            }

            Text(session.displayTitle)
                .font(.system(size: CodexPanelTypography.body, weight: session.isPrimary ? .semibold : .medium))
                .foregroundStyle(.primary.opacity(session.isPrimary ? 0.94 : 0.78))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 5) {
                Image(systemName: session.taskStage.systemImage)
                    .font(.system(size: CodexPanelTypography.compact, weight: .semibold))
                Text(session.taskStage.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(sessionTimeText(session))
                    .lineLimit(1)
            }
            .font(.system(size: CodexPanelTypography.compact, weight: .medium))
            .foregroundStyle(.secondary)

            if let summary = session.displaySummary(privacyMode: privacyMode) {
                Text(summary)
                    .font(.system(size: CodexPanelTypography.compact))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: 154, height: 64, alignment: .topLeading)
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(session.state.accentColor.opacity(session.isPrimary ? 0.32 : 0.14), lineWidth: 1)
        )
    }

    private var stagePanel: some View {
        HStack(spacing: 8) {
            Image(systemName: manager.status.taskStage.systemImage)
                .font(.system(size: CodexPanelTypography.compact, weight: .semibold))
                .foregroundStyle(manager.status.state.accentColor)
                .frame(width: 18, height: 18)
                .background(manager.status.state.accentColor.opacity(0.12), in: Circle())

            Text("当前阶段")
                .font(.system(size: CodexPanelTypography.compact, weight: .medium))
                .foregroundStyle(.secondary)

            Text(manager.status.taskStage.label)
                .font(.system(size: CodexPanelTypography.body, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.92))

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private var taskReportPanel: some View {
        if let report = manager.status.taskReport {
            VStack(alignment: .leading, spacing: 5) {
                Label(report.title, systemImage: "checkmark.seal")
                    .font(.system(size: CodexPanelTypography.sectionTitle, weight: .semibold))
                    .foregroundStyle(Color.green)

                ForEach(report.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: 4, height: 4)
                            .padding(.top, 5)
                        Text(bullet)
                            .font(.system(size: CodexPanelTypography.compact))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.green.opacity(0.16), lineWidth: 1)
            )
        }
    }

    private var healthPanel: some View {
        let health = manager.status.healthReport
        return HStack(spacing: 8) {
            Circle()
                .fill(health.level.accentColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(health.title)
                    .font(.system(size: CodexPanelTypography.body, weight: .semibold))
                    .foregroundStyle(health.level.accentColor)
                Text(health.detail)
                    .font(.system(size: CodexPanelTypography.compact))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(health.level.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(health.level.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var timelinePanel: some View {
        let events = manager.status.displayTimelineEvents(privacyMode: privacyMode)
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("快速时间线", systemImage: "list.bullet.indent")
                    .font(.system(size: CodexPanelTypography.sectionTitle, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(events.reversed()) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: event.systemImage)
                            .font(.system(size: CodexPanelTypography.compact, weight: .semibold))
                            .foregroundStyle(event.accentColor)
                            .frame(width: 14, height: 14)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(event.title)
                                    .font(.system(size: CodexPanelTypography.body, weight: .medium))
                                    .foregroundStyle(.primary.opacity(0.9))
                                    .lineLimit(1)

                                Text(freshnessText(for: event.timestamp))
                                    .font(.system(size: CodexPanelTypography.compact, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            if let detail = event.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: CodexPanelTypography.compact))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    @ViewBuilder
    private var previewPanel: some View {
        if let assistantText = manager.status.displayAssistantText(privacyMode: privacyMode) {
            VStack(alignment: .leading, spacing: 5) {
                previewHeader(title: "Codex 回复", icon: "text.bubble", canCopy: true)
                Text(assistantText)
                    .font(.system(size: CodexPanelTypography.preview))
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineLimit(8)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else if let summary = manager.status.displaySummary(privacyMode: privacyMode) {
            VStack(alignment: .leading, spacing: 5) {
                previewHeader(
                    title: manager.status.state == .working ? "实时动态" : "最近内容",
                    icon: manager.status.state.systemImage,
                    canCopy: true
                )
                Text(summary)
                    .font(.system(size: CodexPanelTypography.preview, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(5)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Text("内容已隐藏")
                .font(.system(size: CodexPanelTypography.body))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func previewHeader(title: String, icon: String, canCopy: Bool) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: CodexPanelTypography.sectionTitle, weight: .semibold))
                .foregroundStyle(manager.status.state.accentColor)

            Spacer(minLength: 0)

            if canCopy {
                Button {
                    copyLatestCodexText()
                } label: {
                    Image(systemName: copiedAt == nil ? "doc.on.doc" : "checkmark")
                        .font(.system(size: CodexPanelTypography.compact, weight: .semibold))
                        .foregroundStyle(copiedAt == nil ? Color.secondary : Color.green)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("复制当前内容")
            }
        }
    }

    private var unavailableBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(manager.status.sourceAvailability.label)
                .font(.system(size: CodexPanelTypography.headerTitle, weight: .semibold))
            Text(manager.status.sourceAvailability.detail)
                .font(.system(size: CodexPanelTypography.body))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func sessionTimeText(_ session: CodexSessionSummary) -> String {
        if let elapsed = session.elapsedWorkingTime {
            return formatElapsed(elapsed)
        }
        guard let lastUpdatedAt = session.lastUpdatedAt else { return "未知" }
        return freshnessText(for: lastUpdatedAt)
    }

    private func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        CodexDebugLogger.log("用户在 Codex 面板触发立即刷新")
        Task {
            await manager.refreshOnce()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private func copyLatestCodexText() {
        let text = manager.status.displayAssistantText(privacyMode: privacyMode)
            ?? manager.status.displaySummary(privacyMode: privacyMode)
        guard let text, !text.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let timestamp = Date()
        copiedAt = timestamp
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                if copiedAt == timestamp {
                    copiedAt = nil
                }
            }
        }
    }

    private func headerIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func freshnessText(for date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 3 { return "刚刚" }
        if seconds < 60 { return "\(seconds)s 前" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m 前" }

        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private func isStale(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > 15
    }
}
