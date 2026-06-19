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

enum CodexAppLauncher {
    @MainActor
    static func openCodex() {
        if activateRunningCodexApp() {
            CodexDebugLogger.log("打开 Codex 入口 reason=activate-running-app")
            return
        }

        if openKnownBundleIdentifier() {
            CodexDebugLogger.log("打开 Codex 入口 reason=open-bundle-id")
            return
        }

        if openKnownApplicationPath() {
            CodexDebugLogger.log("打开 Codex 入口 reason=open-application-path")
            return
        }

        CodexDebugLogger.log("打开 Codex 入口失败 reason=no-known-app")
    }

    @MainActor
    private static func activateRunningCodexApp() -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: isCodexCandidate) else {
            return false
        }
        return app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private static func isCodexCandidate(_ app: NSRunningApplication) -> Bool {
        let values = [
            app.localizedName,
            app.bundleIdentifier,
            app.bundleURL?.lastPathComponent,
            app.executableURL?.lastPathComponent
        ]
        return values.compactMap { $0?.lowercased() }.contains { value in
            value.contains("codex") || value.contains("chatgpt") || value.contains("openai")
        }
    }

    @MainActor
    private static func openKnownBundleIdentifier() -> Bool {
        let bundleIdentifiers = [
            "com.openai.codex",
            "com.openai.chatgpt",
            "com.openai.ChatGPT",
            "com.openai.chat"
        ]
        for bundleIdentifier in bundleIdentifiers {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                continue
            }
            if openApplication(at: url) {
                return true
            }
        }
        return false
    }

    @MainActor
    private static func openKnownApplicationPath() -> Bool {
        let paths = [
            "/Applications/Codex.app",
            "\(NSHomeDirectory())/Applications/Codex.app",
            "/Applications/ChatGPT.app",
            "\(NSHomeDirectory())/Applications/ChatGPT.app",
            "/Applications/OpenAI.app",
            "\(NSHomeDirectory())/Applications/OpenAI.app"
        ]
        for path in paths {
            guard FileManager.default.fileExists(atPath: path),
                  openApplication(at: URL(fileURLWithPath: path)) else {
                continue
            }
            return true
        }
        return false
    }

    @MainActor
    private static func openApplication(at url: URL) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }
}
