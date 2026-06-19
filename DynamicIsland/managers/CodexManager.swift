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

import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
final class CodexManager: ObservableObject {
    static let shared = CodexManager()

    @Published private(set) var status: CodexThreadStatus = .unavailable
    @Published private(set) var lastTransition: CodexRunState?

    private var refreshTask: Task<Void, Never>?
    private var provider: any CodexStatusProvider
    private let coordinator = DynamicIslandViewCoordinator.shared

    private init(provider: (any CodexStatusProvider)? = nil) {
        if let provider {
            self.provider = provider
        } else {
            self.provider = CodexStatusProviderFactory.makeDefaultProvider(
                mockStatusFilePath: Defaults[.codexMockStatusFilePath]
            )
        }
    }

    func configure(provider: any CodexStatusProvider) {
        self.provider = provider
    }

    func start() {
        guard Defaults[.enableCodexFeature] else {
            stop()
            return
        }
        guard refreshTask == nil else { return }

        CodexDebugLogger.log("CodexManager start activeInterval=\(Defaults[.codexActiveRefreshInterval]) idleInterval=\(Defaults[.codexIdleRefreshInterval])")
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshOnce()
                let interval = self.status.state.isActive
                    ? Defaults[.codexActiveRefreshInterval]
                    : Defaults[.codexIdleRefreshInterval]
                try? await Task.sleep(for: .seconds(max(1, interval)))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        CodexDebugLogger.log("CodexManager stop")
        status = .unavailable
        lastTransition = nil
    }

    func refreshOnce() async {
        let previous = status
        let next = await provider.currentThreadStatus()
        CodexDebugLogger.log("刷新状态 previous=\(previous.state.rawValue) next=\(next.state.rawValue) availability=\(next.sourceAvailability.label) title=\(next.displayTitle)")
        apply(next, previous: previous)
    }

    private func apply(_ next: CodexThreadStatus, previous: CodexThreadStatus) {
        status = next
        guard next.state != previous.state else { return }
        lastTransition = next.state
        notifyIfNeeded(for: next, previous: previous)
    }

    private func notifyIfNeeded(for status: CodexThreadStatus, previous: CodexThreadStatus) {
        switch status.state {
        case .working:
            showSneakPeek(status, title: String(localized: "Codex 正在工作"), enabled: true, duration: 3)
        case .waiting:
            showSneakPeek(status, title: String(localized: "Codex 等待你处理"), enabled: Defaults[.codexShowWaitingAlerts], duration: 5)
        case .done:
            guard previous.state == .working || previous.state == .waiting else { return }
            showSneakPeek(status, title: String(localized: "Codex 已完成"), enabled: Defaults[.codexShowDoneAlerts], duration: 5)
        case .error:
            showSneakPeek(status, title: String(localized: "Codex 需要关注"), enabled: Defaults[.codexShowErrorAlerts], duration: 6)
        case .idle, .unknown:
            break
        }
    }

    private func showSneakPeek(_ status: CodexThreadStatus, title: String, enabled: Bool, duration: TimeInterval) {
        guard enabled else { return }
        coordinator.toggleSneakPeek(
            status: true,
            type: .codex,
            duration: duration,
            icon: status.state.systemImage,
            title: title,
            subtitle: status.displaySummary(privacyMode: Defaults[.codexPrivacyMode]) ?? status.state.label,
            accentColor: status.state.accentColor,
            styleOverride: .standard
        )
    }
}
