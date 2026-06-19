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

struct CodexSettings: View {
    @ObservedObject private var manager = CodexManager.shared
    @Default(.enableCodexFeature) private var enableCodexFeature
    @Default(.codexPrivacyMode) private var privacyMode
    @Default(.codexActiveRefreshInterval) private var activeRefreshInterval
    @Default(.codexIdleRefreshInterval) private var idleRefreshInterval
    @Default(.codexAlwaysShowTab) private var alwaysShowTab
    @Default(.codexSessionListLimit) private var sessionListLimit
    @Default(.codexMockStatusFilePath) private var mockStatusFilePath
    @Default(.codexDebugLoggingEnabled) private var debugLoggingEnabled
    @State private var diagnosticsExportMessage: String?

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableCodexFeature) {
                    Text("启用 Codex 集成")
                }
                Defaults.Toggle(key: .codexAlwaysShowTab) {
                    Text("始终显示 Codex 标签页")
                }
                .disabled(!enableCodexFeature)
            } header: {
                Text("Codex")
            } footer: {
                Text("当前版本中，\(Bundle.main.displayName) 只读取 Codex 状态，不会发送消息、停止任务或批准操作。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("隐私模式", selection: $privacyMode) {
                    ForEach(CodexPrivacyMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!enableCodexFeature)
            } header: {
                Text("隐私")
            }

            Section {
                Defaults.Toggle(key: .codexShowWaitingAlerts) {
                    Text("等待你处理时提醒")
                }
                Defaults.Toggle(key: .codexShowDoneAlerts) {
                    Text("任务完成时提醒")
                }
                Defaults.Toggle(key: .codexShowErrorAlerts) {
                    Text("发生错误时提醒")
                }
            } header: {
                Text("提醒")
            }
            .disabled(!enableCodexFeature)

            Section {
                Stepper(value: $sessionListLimit, in: 1...6, step: 1) {
                    Text("最近会话显示：\(sessionListLimit) 个")
                }
            } header: {
                Text("会话列表")
            } footer: {
                Text("灵动岛内默认只显示最近 3 个 Codex 会话，数量越少越清爽。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enableCodexFeature)

            Section {
                Stepper(value: $activeRefreshInterval, in: 1...30, step: 1) {
                    Text("活跃状态刷新：\(Int(activeRefreshInterval)) 秒")
                }
                Stepper(value: $idleRefreshInterval, in: 2...60, step: 1) {
                    Text("空闲状态刷新：\(Int(idleRefreshInterval)) 秒")
                }
            } header: {
                Text("刷新频率")
            } footer: {
                Text("开启低资源模式后，Codex 工作中最快三秒刷新一次，空闲时最少间隔二十秒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enableCodexFeature)

            Section {
                Defaults.Toggle(key: .lowResourceMode) {
                    Text("低资源模式")
                }
            } footer: {
                Text("降低后台轮询频率，减少 CPU 唤醒和电量消耗。Codex 活跃状态仍会保持较快刷新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("状态来源") {
                    Text("Codex 桌面 App 本机状态")
                        .foregroundStyle(.secondary)
                }
                TextField("备用 mock 状态文件路径", text: $mockStatusFilePath)
                    .textFieldStyle(.roundedBorder)
                Button("立即刷新") {
                    CodexDebugLogger.log("用户在设置页触发立即刷新")
                    Task { await manager.refreshOnce() }
                }
                .disabled(!enableCodexFeature)
            } header: {
                Text("诊断")
            } footer: {
                Text("\(manager.status.sourceAvailability.detail) 只有在无法读取 Codex 本机状态时，才会使用备用 mock 文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("开启 Debug 日志", isOn: $debugLoggingEnabled)
                    .disabled(!enableCodexFeature)
                LabeledContent("日志文件") {
                    Text(CodexDebugLogger.logFileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("打开日志目录") {
                        NSWorkspace.shared.activateFileViewerSelecting([CodexDebugLogger.logFileURL])
                    }
                    Button("复制日志路径") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CodexDebugLogger.logFileURL.path, forType: .string)
                    }
                }
                .disabled(!enableCodexFeature)
                Button("导出诊断包") {
                    exportDiagnostics()
                }
                .disabled(!enableCodexFeature)
                if let diagnosticsExportMessage {
                    Text(diagnosticsExportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("反馈日志")
            } footer: {
                Text("开启后，\(Bundle.main.displayName) 会记录 Codex 状态判断原因。复现问题后，把这个日志文件发回来即可分析。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exportDiagnostics() {
        do {
            let url = try CodexDiagnosticsExporter.export(status: manager.status)
            diagnosticsExportMessage = "已导出：\(url.path)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            diagnosticsExportMessage = "导出失败：\(error.localizedDescription)"
            CodexDebugLogger.log("导出 Codex 诊断包失败 message=\(error.localizedDescription)")
        }
    }
}
