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

struct DynamicIslandHeader: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @State private var showClipboardPopover = false
    @State private var showColorPickerPopover = false
    @State private var showTimerPopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.showClipboardIcon) var showClipboardIcon
    @Default(.showColorPickerIcon) var showColorPickerIcon
    @Default(.clipboardDisplayMode) var clipboardDisplayMode
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.notchQuickActionOrder) private var notchQuickActionOrder
    @Default(.hiddenNotchQuickActions) private var hiddenNotchQuickActions
    
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if !enableMinimalisticUI {
                    let shouldShowTabs = coordinator.alwaysShowTabs || vm.notchState == .open || !shelfState.items.isEmpty
                    if shouldShowTabs {
                        TabSelectionView()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
            .padding(8)

            if vm.notchState == .open {
                let spacerWidth = min(vm.closedNotchSize.width, 300)
                Rectangle()
                    .fill(enableMinimalisticUI ? .clear : (NSScreen.screens
                        .first(where: { $0.localizedName == coordinator.selectedScreen })?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear))
                    .frame(width: spacerWidth)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    ForEach(visibleQuickActions) { item in
                        quickActionView(item)
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
        .onChange(of: coordinator.shouldToggleClipboardPopover) { _ in
            // Only toggle if clipboard is enabled
            if Defaults[.enableClipboardManager] {
                switch clipboardDisplayMode {
                case .panel:
                    ClipboardPanelManager.shared.toggleClipboardPanel()
                case .popover:
                    showClipboardPopover.toggle()
                case .separateTab:
                    if coordinator.currentView == .notes {
                        coordinator.currentView = .home
                    } else {
                        coordinator.currentView = .notes
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleClipboardPopover"))) { _ in
            // Handle keyboard shortcut for popover mode
            if Defaults[.enableClipboardManager] && clipboardDisplayMode == .popover {
                showClipboardPopover.toggle()
            }
        }
        .onChange(of: enableTimerFeature) { _, newValue in
            if !newValue {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
        .onChange(of: timerDisplayMode) { _, mode in
            if mode == .tab {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
    }
}

private extension DynamicIslandHeader {
    var visibleQuickActions: [NotchQuickActionItem] {
        let hidden = Set(hiddenNotchQuickActions)
        return normalizedQuickActionOrder.filter { item in
            guard !hidden.contains(item) else { return false }
            switch item {
            case .mirror:
                return !enableMinimalisticUI && Defaults[.showMirror]
            case .clipboard:
                return !enableMinimalisticUI
                    && Defaults[.enableClipboardManager]
                    && showClipboardIcon
                    && clipboardDisplayMode != .separateTab
            case .colorPicker:
                return !enableMinimalisticUI
                    && Defaults[.enableColorPickerFeature]
                    && showColorPickerIcon
            case .timer:
                return !enableMinimalisticUI
                    && Defaults[.enableTimerFeature]
                    && timerDisplayMode == .popover
            case .settings:
                return !enableMinimalisticUI && Defaults[.settingsIconInNotch]
            case .recording:
                return false
            case .focus:
                return false
            case .battery:
                return false
            }
        }
    }

    var normalizedQuickActionOrder: [NotchQuickActionItem] {
        let defaults = NotchQuickActionItem.defaultOrder
        var seen = Set<NotchQuickActionItem>()
        let stored = notchQuickActionOrder.filter { item in
            guard defaults.contains(item), !seen.contains(item) else { return false }
            seen.insert(item)
            return true
        }
        return stored + defaults.filter { !seen.contains($0) }
    }

    @ViewBuilder
    func quickActionView(_ item: NotchQuickActionItem) -> some View {
        switch item {
        case .mirror:
            headerIconButton(systemName: item.systemImage) {
                vm.toggleCameraPreview()
            }
        case .clipboard:
            headerIconButton(systemName: item.systemImage) {
                switch clipboardDisplayMode {
                case .panel:
                    ClipboardPanelManager.shared.toggleClipboardPanel()
                case .popover:
                    showClipboardPopover.toggle()
                case .separateTab:
                    coordinator.currentView = .notes
                }
            }
            .popover(isPresented: $showClipboardPopover, arrowEdge: .bottom) {
                ClipboardPopover()
            }
            .onChange(of: showClipboardPopover) { isActive in
                vm.isClipboardPopoverActive = isActive

                if !isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        vm.shouldRecheckHover.toggle()
                    }
                }
            }
            .onAppear {
                if Defaults[.enableClipboardManager] && !clipboardManager.isMonitoring {
                    clipboardManager.startMonitoring()
                }
            }
        case .colorPicker:
            headerIconButton(systemName: item.systemImage) {
                switch Defaults[.colorPickerDisplayMode] {
                case .panel:
                    ColorPickerPanelManager.shared.toggleColorPickerPanel()
                case .popover:
                    showColorPickerPopover.toggle()
                }
            }
            .popover(isPresented: $showColorPickerPopover, arrowEdge: .bottom) {
                ColorPickerPopover()
            }
            .onChange(of: showColorPickerPopover) { isActive in
                vm.isColorPickerPopoverActive = isActive

                if !isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        vm.shouldRecheckHover.toggle()
                    }
                }
            }
        case .timer:
            headerIconButton(systemName: item.systemImage) {
                withAnimation(.smooth) {
                    showTimerPopover.toggle()
                }
            }
            .popover(isPresented: $showTimerPopover, arrowEdge: .bottom) {
                TimerPopover()
            }
            .onChange(of: showTimerPopover) { isActive in
                vm.isTimerPopoverActive = isActive
                if !isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        vm.shouldRecheckHover.toggle()
                    }
                }
            }
        case .settings:
            headerIconButton(systemName: item.systemImage) {
                SettingsWindowController.shared.showWindow()
            }
        case .recording:
            RecordingIndicator()
                .frame(width: 30, height: 30)
        case .focus:
            FocusIndicator()
                .frame(width: 30, height: 30)
                .transition(.opacity)
        case .battery:
            if enableMinimalisticUI {
                MinimalisticBatteryView(
                    levelBattery: batteryModel.levelBattery,
                    isPluggedIn: batteryModel.isPluggedIn,
                    isCharging: batteryModel.isCharging,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    bodyWidth: 28,
                    bodyHeight: 14,
                    isForNotification: false,
                    showPercentInside: showBatteryPercentInside
                )
                .padding(.trailing, 4)
            } else {
                DynamicIslandBatteryView(
                    batteryWidth: 30,
                    isCharging: batteryModel.isCharging,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    isPluggedIn: batteryModel.isPluggedIn,
                    levelBattery: batteryModel.levelBattery,
                    maxCapacity: batteryModel.maxCapacity,
                    timeToFullCharge: batteryModel.timeToFullCharge,
                    isForNotification: false
                )
            }
        }
    }

    func headerIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: systemName)
                        .foregroundColor(.white)
                        .padding()
                        .imageScale(.medium)
                }
        }
        .buttonStyle(PlainButtonStyle())
    }

    var shouldSuppressStatusIndicators: Bool {
        Defaults[.settingsIconInNotch]
            && Defaults[.enableClipboardManager]
            && Defaults[.showClipboardIcon]
            && Defaults[.showColorPickerIcon]
            && Defaults[.enableTimerFeature]
    }
}

#Preview {
    DynamicIslandHeader()
        .environmentObject(DynamicIslandViewModel())
        .environmentObject(WebcamManager.shared)
}
