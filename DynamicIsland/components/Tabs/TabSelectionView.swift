/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import AtollExtensionKit
import SwiftUI
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let experienceID: String?
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil) {
        self.id = experienceID.map { "extension-\($0)" } ?? "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
        self.experienceID = experienceID
        self.accentColor = accentColor
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @ObservedObject private var codexManager = CodexManager.shared
    @ObservedObject private var feishuManager = FeishuNotificationManager.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    @Default(.enableCodexFeature) private var enableCodexFeature
    @Default(.codexAlwaysShowTab) private var codexAlwaysShowTab
    @Default(.enableFeishuNotifications) private var enableFeishuNotifications
    @Default(.feishuAlwaysShowTab) private var feishuAlwaysShowTab
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Default(.notchTabOrder) private var notchTabOrder
    @Default(.hiddenNotchTabs) private var hiddenNotchTabs
    
    private var tabs: [TabModel] {
        var tabGroups: [NotchTabItem: [TabModel]] = [:]

        if homeTabVisible {
            tabGroups[.home] = [TabModel(label: "Home", icon: NotchTabItem.home.systemImage, view: .home)]
        }

        if Defaults[.dynamicShelf] {
            tabGroups[.shelf] = [TabModel(label: "Shelf", icon: NotchTabItem.shelf.systemImage, view: .shelf)]
        }

        if enableTimerFeature && timerDisplayMode == .tab {
            tabGroups[.timer] = [TabModel(label: "Timer", icon: NotchTabItem.timer.systemImage, view: .timer)]
        }

        if Defaults[.enableStatsFeature] {
            tabGroups[.stats] = [TabModel(label: "Stats", icon: NotchTabItem.stats.systemImage, view: .stats)]
        }

        if Defaults[.enableNotes] || (Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .separateTab) {
            let label = Defaults[.enableNotes] ? "Notes" : "Clipboard"
            let icon = Defaults[.enableNotes] ? NotchTabItem.notes.systemImage : "doc.on.clipboard"
            tabGroups[.notes] = [TabModel(label: label, icon: icon, view: .notes)]
        }

        if Defaults[.enableTerminalFeature] {
            tabGroups[.terminal] = [TabModel(label: "Terminal", icon: NotchTabItem.terminal.systemImage, view: .terminal)]
        }

        if enableCodexFeature && (codexAlwaysShowTab || codexManager.status.state.isActive) {
            tabGroups[.codex] = [TabModel(label: "Codex", icon: NotchTabItem.codex.systemImage, view: .codex, accentColor: codexManager.status.state.accentColor)]
        }

        if enableFeishuNotifications && (feishuAlwaysShowTab || feishuManager.status.hasMention) {
            tabGroups[.feishu] = [TabModel(label: "飞书", icon: NotchTabItem.feishu.systemImage, view: .feishu, accentColor: feishuManager.status.accentColor)]
        }

        if extensionTabsEnabled {
            let extensionModels = extensionTabPayloads.compactMap { payload -> TabModel? in
                guard let tab = payload.descriptor.tab else { return nil }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? NotchTabItem.extensions.systemImage
                return TabModel(
                    label: tab.title,
                    icon: iconName,
                    view: .extensionExperience,
                    experienceID: payload.descriptor.id,
                    accentColor: accent
                )
            }
            if !extensionModels.isEmpty {
                tabGroups[.extensions] = extensionModels
            }
        }

        let hidden = Set(hiddenNotchTabs)
        return normalizedTabOrder.flatMap { item -> [TabModel] in
            guard !hidden.contains(item) else { return [] }
            return tabGroups[item] ?? []
        }
    }
    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                let isSelected = isSelected(tab)
                let activeAccent = tab.accentColor ?? .white

                // Render the tab button
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    if tab.view == .extensionExperience {
                        coordinator.selectedExtensionExperienceID = tab.experienceID
                    }
                    coordinator.currentView = tab.view
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? activeAccent : .gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill((tab.accentColor ?? Color(nsColor: .secondarySystemFill)).opacity(0.25))
                            .shadow(color: (tab.accentColor ?? .clear).opacity(0.4), radius: 8)
                    }
                }

                
            }
        }
        .animation(.smooth(duration: 0.3), value: coordinator.currentView)
        .clipShape(Capsule())
        .onAppear {
            ensureValidSelection(with: tabs)
        }
        .onChange(of: tabIDs) { _, _ in
            ensureValidSelection(with: tabs)
        }
    }

    private var tabIDs: [String] {
        tabs.map(\.id)
    }

    private var extensionTabsEnabled: Bool {
        enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showCalendar || showMirror
    }

    private var normalizedTabOrder: [NotchTabItem] {
        let defaults = NotchTabItem.defaultOrder
        var seen = Set<NotchTabItem>()
        let stored = notchTabOrder.filter { item in
            guard defaults.contains(item), !seen.contains(item) else { return false }
            seen.insert(item)
            return true
        }
        return stored + defaults.filter { !seen.contains($0) }
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        if tab.view == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        if first.view == .extensionExperience {
            coordinator.selectedExtensionExperienceID = first.experienceID
        } else {
            coordinator.selectedExtensionExperienceID = nil
        }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
