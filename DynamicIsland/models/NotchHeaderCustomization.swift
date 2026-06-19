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

enum NotchTabItem: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case home
    case shelf
    case timer
    case stats
    case notes
    case terminal
    case codex
    case feishu
    case extensions

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .home: return String(localized: "主页")
        case .shelf: return String(localized: "文件架")
        case .timer: return String(localized: "计时器")
        case .stats: return String(localized: "状态")
        case .notes: return String(localized: "笔记/剪贴板")
        case .terminal: return String(localized: "终端")
        case .codex: return String(localized: "Codex")
        case .feishu: return String(localized: "飞书")
        case .extensions: return String(localized: "扩展")
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.fill"
        case .timer: return "timer"
        case .stats: return "chart.xyaxis.line"
        case .notes: return "note.text"
        case .terminal: return "apple.terminal"
        case .codex: return "sparkles"
        case .feishu: return "message.badge"
        case .extensions: return "puzzlepiece.extension"
        }
    }

    static let defaultOrder: [NotchTabItem] = [.home, .shelf, .timer, .stats, .notes, .terminal, .codex, .feishu, .extensions]
}

enum NotchQuickActionItem: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case mirror
    case clipboard
    case colorPicker
    case timer
    case settings
    case recording
    case focus
    case battery

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .mirror: return String(localized: "镜像")
        case .clipboard: return String(localized: "剪贴板")
        case .colorPicker: return String(localized: "取色器")
        case .timer: return String(localized: "计时器弹窗")
        case .settings: return String(localized: "设置")
        case .recording: return String(localized: "录屏状态")
        case .focus: return String(localized: "专注状态")
        case .battery: return String(localized: "电量")
        }
    }

    var systemImage: String {
        switch self {
        case .mirror: return "web.camera"
        case .clipboard: return "doc.on.clipboard"
        case .colorPicker: return "eyedropper"
        case .timer: return "timer"
        case .settings: return "gear"
        case .recording: return "record.circle"
        case .focus: return "moon.fill"
        case .battery: return "battery.100percent"
        }
    }

    static let defaultOrder: [NotchQuickActionItem] = [.mirror, .clipboard, .colorPicker, .timer, .settings, .recording, .focus, .battery]
}
