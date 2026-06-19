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

import AppKit
import Defaults
import SwiftUI

struct FeishuSettings: View {
    @ObservedObject private var manager = FeishuNotificationManager.shared
    @Default(.enableFeishuNotifications) private var enableFeishuNotifications
    @Default(.feishuAlwaysShowTab) private var alwaysShowTab
    @Default(.feishuPollInterval) private var pollInterval
    @Default(.feishuMentionKeywords) private var mentionKeywords
    @Default(.feishuDirectMessageKeywords) private var directMessageKeywords
    @Default(.feishuAllowedSenderKeywords) private var allowedSenderKeywords
    @Default(.feishuAllowedConversationKeywords) private var allowedConversationKeywords
    @Default(.feishuBlockedKeywords) private var blockedKeywords
    @Default(.feishuPriorityQueueLimit) private var priorityQueueLimit
    @Default(.feishuShowMessagePreview) private var showMessagePreview
    @Default(.feishuDebugLoggingEnabled) private var debugLoggingEnabled

    var body: some View {
        Form {
            Section {
                Toggle("启用飞书本地通知监听", isOn: $enableFeishuNotifications)
                Toggle("始终显示飞书标签页", isOn: $alwaysShowTab)
                    .disabled(!enableFeishuNotifications)
                Toggle("显示消息预览", isOn: $showMessagePreview)
                    .disabled(!enableFeishuNotifications)
            } header: {
                Text("飞书")
            } footer: {
                Text("\(Bundle.main.displayName) 只读取本机通知记录，用于识别飞书 @你 和私聊；不连接飞书开放平台，也不会发送消息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $pollInterval, in: 1...15, step: 1) {
                    Text("检查间隔：\(Int(pollInterval)) 秒")
                }
                Stepper(value: $priorityQueueLimit, in: 1...6, step: 1) {
                    Text("灵动岛队列：最近 \(priorityQueueLimit) 条")
                }
            } header: {
                Text("刷新")
            }
            .disabled(!enableFeishuNotifications)

            Section {
                TextEditor(text: $allowedSenderKeywords)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 70)
                TextEditor(text: $allowedConversationKeywords)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 70)
                TextEditor(text: $blockedKeywords)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 58)
            } header: {
                Text("重要人和群")
            } footer: {
                Text("前三个输入框依次是：重要联系人、重要群聊、屏蔽词。每行一个关键词；联系人和群都为空时不过滤，屏蔽词始终优先。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enableFeishuNotifications)

            Section {
                TextEditor(text: $mentionKeywords)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 70)
                TextEditor(text: $directMessageKeywords)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 70)
            } header: {
                Text("识别关键词")
            } footer: {
                Text("每行一个关键词。飞书通知格式随版本变化时，可以在这里补充“@你”“提到了你”等文本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enableFeishuNotifications)

            Section {
                LabeledContent("当前状态") {
                    Text(manager.status.availability.label)
                        .foregroundStyle(manager.status.availability.accentColor)
                }
                Text(manager.status.availability.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("立即检查") {
                        Task { await manager.refreshOnce() }
                    }
                    Button("打开完全磁盘访问") {
                        FullDiskAccessPermissionStore.shared.openSystemSettings()
                    }
                    Button("定位 PulseDock") {
                        FullDiskAccessPermissionStore.shared.revealAppBundleInFinder()
                    }
                    Button("清空提醒") {
                        manager.markAllRead()
                    }
                }
                .disabled(!enableFeishuNotifications)
            } header: {
                Text("状态")
            } footer: {
                Text("飞书通知数据库需要“完全磁盘访问权限”，不是“文件与文件夹”。如果列表里没有 \(Bundle.main.displayName)，请点击“定位 PulseDock”，再把 app 拖进“完全磁盘访问权限”列表并开启，然后重启 \(Bundle.main.displayName)。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("开启 Debug 日志", isOn: $debugLoggingEnabled)
                    .disabled(!enableFeishuNotifications)
                LabeledContent("日志文件") {
                    Text(FeishuDebugLogger.logFileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("打开日志目录") {
                        NSWorkspace.shared.activateFileViewerSelecting([FeishuDebugLogger.logFileURL])
                    }
                    Button("复制日志路径") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(FeishuDebugLogger.logFileURL.path, forType: .string)
                    }
                }
            } header: {
                Text("反馈日志")
            }
        }
    }
}
