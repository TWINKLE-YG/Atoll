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

struct NotchHeaderCustomizationSettings: View {
    @Default(.notchTabOrder) private var tabOrder
    @Default(.hiddenNotchTabs) private var hiddenTabs
    @Default(.notchQuickActionOrder) private var quickActionOrder
    @Default(.hiddenNotchQuickActions) private var hiddenQuickActions

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("页面入口")
                    .font(.headline)
                ForEach(normalizedTabOrder) { item in
                    tabRow(item)
                }
            }
            Button("恢复页面入口默认顺序") {
                tabOrder = NotchTabItem.defaultOrder
                hiddenTabs = []
            }
        } header: {
            Text("顶部入口")
        } footer: {
            Text("控制灵动岛顶部左侧页面入口的显示和顺序。功能本身未启用时，即使这里开启也不会显示。")
        }

        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("快捷按钮")
                    .font(.headline)
                ForEach(normalizedQuickActionOrder) { item in
                    quickActionRow(item)
                }
            }
            Button("恢复快捷按钮默认顺序") {
                quickActionOrder = NotchQuickActionItem.defaultOrder
                hiddenQuickActions = []
            }
        } header: {
            Text("顶部快捷操作")
        } footer: {
            Text("控制灵动岛顶部右侧快捷按钮的显示和顺序。电量、设置、剪贴板等仍会受各自功能开关影响。")
        }
    }

    private func tabRow(_ item: NotchTabItem) -> some View {
        customizationRow(
            icon: item.systemImage,
            title: item.localizedName,
            isVisible: !hiddenTabs.contains(item),
            canMoveUp: normalizedTabOrder.first != item,
            canMoveDown: normalizedTabOrder.last != item,
            toggleVisibility: { setTab(item, visible: $0) },
            moveUp: { moveTab(item, offset: -1) },
            moveDown: { moveTab(item, offset: 1) }
        )
    }

    private func quickActionRow(_ item: NotchQuickActionItem) -> some View {
        customizationRow(
            icon: item.systemImage,
            title: item.localizedName,
            isVisible: !hiddenQuickActions.contains(item),
            canMoveUp: normalizedQuickActionOrder.first != item,
            canMoveDown: normalizedQuickActionOrder.last != item,
            toggleVisibility: { setQuickAction(item, visible: $0) },
            moveUp: { moveQuickAction(item, offset: -1) },
            moveDown: { moveQuickAction(item, offset: 1) }
        )
    }

    private func customizationRow(
        icon: String,
        title: String,
        isVisible: Bool,
        canMoveUp: Bool,
        canMoveDown: Bool,
        toggleVisibility: @escaping (Bool) -> Void,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
            Toggle(title, isOn: Binding(
                get: { isVisible },
                set: toggleVisibility
            ))
            Spacer(minLength: 0)
            Button {
                moveUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)
            Button {
                moveDown()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)
        }
    }

    private var normalizedTabOrder: [NotchTabItem] {
        normalized(tabOrder, defaults: NotchTabItem.defaultOrder)
    }

    private var normalizedQuickActionOrder: [NotchQuickActionItem] {
        normalized(quickActionOrder, defaults: NotchQuickActionItem.defaultOrder)
    }

    private func normalized<T: Hashable>(_ stored: [T], defaults: [T]) -> [T] {
        var seen = Set<T>()
        let cleanStored = stored.filter { item in
            guard defaults.contains(item), !seen.contains(item) else { return false }
            seen.insert(item)
            return true
        }
        return cleanStored + defaults.filter { !seen.contains($0) }
    }

    private func setTab(_ item: NotchTabItem, visible: Bool) {
        hiddenTabs = updatedHiddenItems(hiddenTabs, item: item, visible: visible)
    }

    private func setQuickAction(_ item: NotchQuickActionItem, visible: Bool) {
        hiddenQuickActions = updatedHiddenItems(hiddenQuickActions, item: item, visible: visible)
    }

    private func updatedHiddenItems<T: Equatable>(_ items: [T], item: T, visible: Bool) -> [T] {
        if visible {
            return items.filter { $0 != item }
        }
        return items.contains(item) ? items : items + [item]
    }

    private func moveTab(_ item: NotchTabItem, offset: Int) {
        tabOrder = moved(item, in: normalizedTabOrder, offset: offset)
    }

    private func moveQuickAction(_ item: NotchQuickActionItem, offset: Int) {
        quickActionOrder = moved(item, in: normalizedQuickActionOrder, offset: offset)
    }

    private func moved<T: Equatable>(_ item: T, in order: [T], offset: Int) -> [T] {
        var next = order
        guard let index = next.firstIndex(of: item) else { return order }
        let target = index + offset
        guard next.indices.contains(target) else { return order }
        next.swapAt(index, target)
        return next
    }
}

