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

struct NotchFeishuView: View {
    @ObservedObject private var manager = FeishuNotificationManager.shared
    @Default(.feishuShowMessagePreview) private var showMessagePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if manager.status.recentEvents.count > 1 {
                priorityQueue
            } else if let event = manager.status.latestEvent {
                latestEventCard(event)
            } else {
                statusCard
            }

            HStack(spacing: 8) {
                Button("立即检查") {
                    Task { await manager.refreshOnce() }
                }
                Button("清空提醒") {
                    manager.markAllRead()
                }
            }
            .buttonStyle(.bordered)
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            manager.start()
            await manager.refreshOnce()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: manager.status.latestEvent?.kind.systemImage ?? "message.badge")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(manager.status.accentColor)
                .frame(width: 30, height: 30)
                .background(manager.status.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("飞书")
                    .font(.system(size: 14, weight: .semibold))
                Text(manager.status.hasMention ? "\(manager.status.recentEvents.count) 条优先消息" : manager.status.availability.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(manager.status.accentColor)
            }

            Spacer(minLength: 0)
        }
    }

    private var statusCard: some View {
        Text(manager.status.availability.detail)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func latestEventCard(_ event: FeishuNotificationEvent) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(event.contextLine, systemImage: event.kind.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(manager.status.accentColor)

            Text(event.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Text(event.displayBody(showPreview: showMessagePreview))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var priorityQueue: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(manager.status.recentEvents) { event in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: event.kind.systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(event.kind == .mention ? .orange : manager.status.accentColor)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(event.displayTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(event.kind.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(manager.status.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(manager.status.accentColor.opacity(0.14), in: Capsule())
                        }

                        Text(event.displayBody(showPreview: showMessagePreview))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Text(event.contextLine)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.75))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}
