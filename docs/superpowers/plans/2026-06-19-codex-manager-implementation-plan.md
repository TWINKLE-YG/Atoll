# Codex Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Atoll 中新增内置 Codex Manager，让灵动岛以只读方式展示 Codex 桌面 App 当前线程状态和长任务进度。

**Architecture:** 先建立可测试的状态模型和 provider 抽象，再用 `CodexManager` 统一轮询、状态迁移和提醒。UI 走 Atoll 原生 tab/settings/coordinator 管线，第一版 provider 保守返回 `unsupported` 或读取 mock 文件，避免依赖未确认的 Codex 私有接口。

**Tech Stack:** Swift, SwiftUI, Combine, Defaults, macOS AppKit, Xcode project `DynamicIsland.xcodeproj`

---

## 当前约束

- 目标仓库：`/Users/twinkle/workProjects/atoll/Atoll`
- 当前分支：`main`
- 当前机器 `xcodebuild -list -project DynamicIsland.xcodeproj` 失败，原因是 active developer directory 是 CommandLineTools，不是完整 Xcode。
- 仓库当前没有 XCTest target。第一轮计划以可编译代码、纯 Swift 逻辑可隔离、手动验证为主；如果后续要自动化测试，单独增加 test target。
- 第一版保持只读，不发送消息、不停止任务、不审批 Codex 操作。

## 文件结构

- Create `DynamicIsland/models/CodexStatusModels.swift`
  - 定义 `CodexRunState`、`CodexSourceAvailability`、`CodexPrivacyMode`、`CodexThreadStatus`。
  - 放置展示用派生属性，例如 `label`、`systemImage`、`accentColor`、`displaySummary(privacyMode:)`。
- Create `DynamicIsland/managers/CodexStatusProvider.swift`
  - 定义 `CodexStatusProvider` 协议。
  - 提供 `UnsupportedCodexStatusProvider` 和 `MockFileCodexStatusProvider`。
- Create `DynamicIsland/managers/CodexManager.swift`
  - 单例 `CodexManager.shared`。
  - 负责 start/stop、轮询 provider、状态迁移检测、触发 sneak peek。
- Create `DynamicIsland/components/Notch/NotchCodexView.swift`
  - 展开态 Codex tab。
- Create `DynamicIsland/components/Notch/CodexMinimalisticView.swift`
  - 闭合/极简态可复用小视图。
- Create `DynamicIsland/components/Settings/CodexSettings.swift`
  - Codex 设置页内容。
- Modify `DynamicIsland/models/Constants.swift`
  - 增加 Defaults keys。
- Modify `DynamicIsland/enums/generic.swift`
  - `NotchViews` 增加 `.codex`。
- Modify `DynamicIsland/DynamicIslandViewCoordinator.swift`
  - tab 顺序、sneak peek 类型、feature toggle 观察。
- Modify `DynamicIsland/components/Tabs/TabSelectionView.swift`
  - 启用时显示 Codex tab。
- Modify `DynamicIsland/sizing/matters.swift`
  - Codex tab 计入推荐最小宽度。
- Modify `DynamicIsland/ContentView.swift`
  - 注入 manager、渲染 `NotchCodexView`、显示 Codex sneak peek。
- Modify `DynamicIsland/DynamicIslandApp.swift`
  - app 启动时根据设置启动/停止 `CodexManager`，监听窗口尺寸变化。
- Modify `DynamicIsland/components/Settings/SettingsView.swift`
  - 侧边栏新增 Codex tab，集成 `CodexSettings`。
- Modify `DynamicIsland.xcodeproj/project.pbxproj`
  - 将新增 Swift 文件加入 DynamicIsland target。

---

### Task 1: 状态模型和 Defaults

**Files:**
- Create: `DynamicIsland/models/CodexStatusModels.swift`
- Modify: `DynamicIsland/models/Constants.swift`

- [ ] **Step 1: 新增状态模型文件**

Create `DynamicIsland/models/CodexStatusModels.swift`:

```swift
import Foundation
import SwiftUI
import Defaults

enum CodexRunState: String, Codable, CaseIterable, Defaults.Serializable {
    case idle
    case working
    case waiting
    case done
    case error
    case unknown

    var label: String {
        switch self {
        case .idle: return String(localized: "Idle")
        case .working: return String(localized: "Working")
        case .waiting: return String(localized: "Waiting")
        case .done: return String(localized: "Done")
        case .error: return String(localized: "Error")
        case .unknown: return String(localized: "Unknown")
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "circle"
        case .working: return "sparkles"
        case .waiting: return "person.crop.circle.badge.questionmark"
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var accentColor: Color {
        switch self {
        case .idle: return .secondary
        case .working: return .cyan
        case .waiting: return .orange
        case .done: return .green
        case .error: return .red
        case .unknown: return .gray
        }
    }

    var isActive: Bool {
        self == .working || self == .waiting
    }
}

enum CodexSourceAvailability: Equatable, Codable {
    case available
    case codexNotRunning
    case permissionDenied
    case unsupported
    case error(message: String)

    var label: String {
        switch self {
        case .available: return String(localized: "Available")
        case .codexNotRunning: return String(localized: "Codex not running")
        case .permissionDenied: return String(localized: "Permission needed")
        case .unsupported: return String(localized: "Unsupported")
        case .error: return String(localized: "Error")
        }
    }

    var detail: String {
        switch self {
        case .available:
            return String(localized: "Codex status source is available.")
        case .codexNotRunning:
            return String(localized: "Open Codex Desktop to show current thread status.")
        case .permissionDenied:
            return String(localized: "Atoll cannot read Codex status with current permissions.")
        case .unsupported:
            return String(localized: "No stable local Codex status source is configured yet.")
        case .error(let message):
            return message
        }
    }
}

enum CodexPrivacyMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case minimal
    case summary
    case detailed

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .minimal: return String(localized: "Minimal")
        case .summary: return String(localized: "Summary")
        case .detailed: return String(localized: "Detailed")
        }
    }

    var allowsSummary: Bool {
        self == .summary || self == .detailed
    }
}

struct CodexThreadStatus: Equatable, Codable {
    var threadId: String?
    var title: String?
    var state: CodexRunState
    var summary: String?
    var lastUpdatedAt: Date?
    var workingStartedAt: Date?
    var sourceAvailability: CodexSourceAvailability

    static let unavailable = CodexThreadStatus(
        threadId: nil,
        title: nil,
        state: .unknown,
        summary: nil,
        lastUpdatedAt: nil,
        workingStartedAt: nil,
        sourceAvailability: .unsupported
    )

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized: "Codex") : trimmed
    }

    func displaySummary(privacyMode: CodexPrivacyMode) -> String? {
        guard privacyMode.allowsSummary else { return nil }
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var elapsedWorkingTime: TimeInterval? {
        guard let workingStartedAt, state.isActive else { return nil }
        return max(0, Date().timeIntervalSince(workingStartedAt))
    }
}
```

- [ ] **Step 2: 增加 Defaults keys**

Modify `DynamicIsland/models/Constants.swift`, inside `extension Defaults.Keys`, near other feature keys:

```swift
    // MARK: Codex Feature
    static let enableCodexFeature = Key<Bool>("enableCodexFeature", default: false)
    static let codexPrivacyMode = Key<CodexPrivacyMode>("codexPrivacyMode", default: .summary)
    static let codexActiveRefreshInterval = Key<Double>("codexActiveRefreshInterval", default: 2.0)
    static let codexIdleRefreshInterval = Key<Double>("codexIdleRefreshInterval", default: 10.0)
    static let codexShowWaitingAlerts = Key<Bool>("codexShowWaitingAlerts", default: true)
    static let codexShowDoneAlerts = Key<Bool>("codexShowDoneAlerts", default: true)
    static let codexShowErrorAlerts = Key<Bool>("codexShowErrorAlerts", default: true)
    static let codexAlwaysShowTab = Key<Bool>("codexAlwaysShowTab", default: true)
    static let codexMockStatusFilePath = Key<String>("codexMockStatusFilePath", default: "")
```

- [ ] **Step 3: 语法检查**

Run:

```bash
xcrun swiftc -parse DynamicIsland/models/CodexStatusModels.swift
```

Expected:

```text
No output and exit code 0
```

If this fails because dependencies such as `Defaults` are unavailable outside Xcode, continue and rely on target build in Task 8.

- [ ] **Step 4: Commit**

```bash
git add DynamicIsland/models/CodexStatusModels.swift DynamicIsland/models/Constants.swift
git commit -m "feat: add codex status models"
```

---

### Task 2: Provider 抽象和 mock 数据源

**Files:**
- Create: `DynamicIsland/managers/CodexStatusProvider.swift`

- [ ] **Step 1: 新增 provider 文件**

Create `DynamicIsland/managers/CodexStatusProvider.swift`:

```swift
import Foundation

protocol CodexStatusProvider {
    func currentThreadStatus() async -> CodexThreadStatus
}

struct UnsupportedCodexStatusProvider: CodexStatusProvider {
    func currentThreadStatus() async -> CodexThreadStatus {
        CodexThreadStatus.unavailable
    }
}

struct MockFileCodexStatusProvider: CodexStatusProvider {
    let filePath: String

    func currentThreadStatus() async -> CodexThreadStatus {
        let trimmedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return CodexThreadStatus.unavailable
        }

        let url = URL(fileURLWithPath: trimmedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CodexThreadStatus(
                threadId: nil,
                title: nil,
                state: .unknown,
                summary: nil,
                lastUpdatedAt: Date(),
                workingStartedAt: nil,
                sourceAvailability: .error(message: String(localized: "Mock status file does not exist."))
            )
        }

        do {
            let data = try Data(contentsOf: url)
            var status = try JSONDecoder.codexStatusDecoder.decode(CodexThreadStatus.self, from: data)
            if status.sourceAvailability != .available {
                status.sourceAvailability = .available
            }
            return status
        } catch {
            return CodexThreadStatus(
                threadId: nil,
                title: nil,
                state: .unknown,
                summary: nil,
                lastUpdatedAt: Date(),
                workingStartedAt: nil,
                sourceAvailability: .error(message: error.localizedDescription)
            )
        }
    }
}

extension JSONDecoder {
    static var codexStatusDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 2: 新增 mock 文件手动样例**

Create `/private/tmp/atoll-codex-status.json` while testing manually:

```json
{
  "threadId": "local-current",
  "title": "Atoll Codex Manager",
  "state": "working",
  "summary": "正在实现 Codex 状态展示",
  "lastUpdatedAt": "2026-06-19T12:00:00Z",
  "workingStartedAt": "2026-06-19T11:55:00Z",
  "sourceAvailability": {
    "available": {}
  }
}
```

If Swift synthesized Codable for `CodexSourceAvailability` does not match this JSON shape, adjust the mock file after checking encoded output in Xcode. Keep provider code unchanged unless decoding fails in build.

- [ ] **Step 3: Commit**

```bash
git add DynamicIsland/managers/CodexStatusProvider.swift
git commit -m "feat: add codex status provider"
```

---

### Task 3: CodexManager 轮询和状态迁移

**Files:**
- Create: `DynamicIsland/managers/CodexManager.swift`

- [ ] **Step 1: 新增 manager 文件**

Create `DynamicIsland/managers/CodexManager.swift`:

```swift
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
    private var provider: CodexStatusProvider
    private let coordinator = DynamicIslandViewCoordinator.shared

    private init(provider: CodexStatusProvider? = nil) {
        if let provider {
            self.provider = provider
        } else if !Defaults[.codexMockStatusFilePath].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.provider = MockFileCodexStatusProvider(filePath: Defaults[.codexMockStatusFilePath])
        } else {
            self.provider = UnsupportedCodexStatusProvider()
        }
    }

    func configure(provider: CodexStatusProvider) {
        self.provider = provider
    }

    func start() {
        guard Defaults[.enableCodexFeature] else {
            stop()
            return
        }
        guard refreshTask == nil else { return }

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
        status = .unavailable
        lastTransition = nil
    }

    func refreshOnce() async {
        let previous = status
        let next = await provider.currentThreadStatus()
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
            showSneakPeek(status, title: String(localized: "Codex is working"), enabled: true)
        case .waiting:
            showSneakPeek(status, title: String(localized: "Codex needs you"), enabled: Defaults[.codexShowWaitingAlerts])
        case .done:
            guard previous.state == .working || previous.state == .waiting else { return }
            showSneakPeek(status, title: String(localized: "Codex finished"), enabled: Defaults[.codexShowDoneAlerts])
        case .error:
            showSneakPeek(status, title: String(localized: "Codex needs attention"), enabled: Defaults[.codexShowErrorAlerts])
        case .idle, .unknown:
            break
        }
    }

    private func showSneakPeek(_ status: CodexThreadStatus, title: String, enabled: Bool) {
        guard enabled else { return }
        coordinator.toggleSneakPeek(
            status: true,
            type: .codex,
            duration: 3,
            icon: status.state.systemImage,
            title: title,
            subtitle: status.displaySummary(privacyMode: Defaults[.codexPrivacyMode]) ?? status.state.label,
            accentColor: status.state.accentColor,
            styleOverride: .standard
        )
    }
}
```

- [ ] **Step 2: 更新 sneak peek 类型**

Modify `DynamicIsland/DynamicIslandViewCoordinator.swift`:

```swift
enum SneakContentType: Equatable {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
    case timer
    case reminder
    case recording
    case doNotDisturb
    case bluetoothAudio
    case privacy
    case lockScreen
    case capsLock
    case codex
    case extensionLiveActivity(bundleID: String, activityID: String)
}
```

Also update the `==` switch to include:

```swift
             (.codex, .codex):
            return true
```

- [ ] **Step 3: Commit**

```bash
git add DynamicIsland/managers/CodexManager.swift DynamicIsland/DynamicIslandViewCoordinator.swift
git commit -m "feat: add codex manager"
```

---

### Task 4: Codex tab UI

**Files:**
- Create: `DynamicIsland/components/Notch/NotchCodexView.swift`
- Create: `DynamicIsland/components/Notch/CodexMinimalisticView.swift`

- [ ] **Step 1: 新增极简状态视图**

Create `DynamicIsland/components/Notch/CodexMinimalisticView.swift`:

```swift
import Defaults
import SwiftUI

struct CodexMinimalisticView: View {
    let status: CodexThreadStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.state.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(status.state.accentColor)
            Text("Codex")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text(status.state.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Codex \(status.state.label)")
    }
}
```

- [ ] **Step 2: 新增展开态 tab**

Create `DynamicIsland/components/Notch/NotchCodexView.swift`:

```swift
import Defaults
import SwiftUI

struct NotchCodexView: View {
    @ObservedObject private var manager = CodexManager.shared
    @Default(.codexPrivacyMode) private var privacyMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusBody
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: manager.status.state.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(manager.status.state.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex")
                    .font(.system(size: 13, weight: .semibold))
                Text(manager.status.state.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(manager.status.state.accentColor)
            }

            Spacer(minLength: 0)

            if let lastUpdatedAt = manager.status.lastUpdatedAt {
                Text(lastUpdatedAt, style: .time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusBody: some View {
        switch manager.status.sourceAvailability {
        case .available:
            VStack(alignment: .leading, spacing: 8) {
                Text(manager.status.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let summary = manager.status.displaySummary(privacyMode: privacyMode) {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else {
                    Text("Details hidden by privacy settings")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if let elapsed = manager.status.elapsedWorkingTime {
                    Label(formatElapsed(elapsed), systemImage: "clock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        case .codexNotRunning, .permissionDenied, .unsupported, .error:
            unavailableBody
        }
    }

    private var unavailableBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(manager.status.sourceAvailability.label)
                .font(.system(size: 15, weight: .semibold))
            Text(manager.status.sourceAvailability.detail)
                .font(.system(size: 12))
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
}
```

- [ ] **Step 3: Commit**

```bash
git add DynamicIsland/components/Notch/NotchCodexView.swift DynamicIsland/components/Notch/CodexMinimalisticView.swift
git commit -m "feat: add codex notch views"
```

---

### Task 5: Tab 管线集成

**Files:**
- Modify: `DynamicIsland/enums/generic.swift`
- Modify: `DynamicIsland/DynamicIslandViewCoordinator.swift`
- Modify: `DynamicIsland/components/Tabs/TabSelectionView.swift`
- Modify: `DynamicIsland/sizing/matters.swift`
- Modify: `DynamicIsland/ContentView.swift`

- [ ] **Step 1: 新增 NotchViews.codex**

Modify `DynamicIsland/enums/generic.swift`:

```swift
public enum NotchViews {
    case home
    case shelf
    case timer
    case stats
    case colorPicker
    case notes
    case clipboard
    case terminal
    case codex
    case extensionExperience
}
```

- [ ] **Step 2: 更新 coordinator tab order 和设置观察**

Modify `DynamicIsland/DynamicIslandViewCoordinator.swift`:

```swift
private static let tabOrder: [NotchViews] = [.home, .shelf, .timer, .stats, .colorPicker, .notes, .clipboard, .terminal, .codex, .extensionExperience]
```

Add the Defaults publisher to the existing tab-affecting `Publishers.MergeMany`:

```swift
Defaults.publisher(.enableCodexFeature).map { _ in () }.eraseToAnyPublisher()
```

- [ ] **Step 3: TabSelectionView 显示 Codex tab**

Modify `DynamicIsland/components/Tabs/TabSelectionView.swift`:

Add:

```swift
@ObservedObject private var codexManager = CodexManager.shared
@Default(.enableCodexFeature) private var enableCodexFeature
@Default(.codexAlwaysShowTab) private var codexAlwaysShowTab
```

Insert before extension tabs:

```swift
if enableCodexFeature && (codexAlwaysShowTab || codexManager.status.state.isActive) {
    tabsArray.append(TabModel(label: "Codex", icon: "sparkles", view: .codex, accentColor: codexManager.status.state.accentColor))
}
```

- [ ] **Step 4: sizing 计入 Codex tab**

Modify `DynamicIsland/sizing/matters.swift`:

```swift
    // Codex tab
    if Defaults[.enableCodexFeature] && (Defaults[.codexAlwaysShowTab] || CodexManager.shared.status.state.isActive) {
        count += 1
    }
```

- [ ] **Step 5: ContentView 渲染 Codex tab**

Modify `DynamicIsland/ContentView.swift`:

Add observed object:

```swift
@ObservedObject var codexManager = CodexManager.shared
```

Add Defaults property:

```swift
@Default(.enableCodexFeature) var enableCodexFeature
```

Add switch case:

```swift
case .codex:
    NotchCodexView()
```

- [ ] **Step 6: ContentView 渲染 Codex sneak peek**

In `ContentView.swift`, near existing timer/reminder/extension sneak peek branches, add:

```swift
else if coordinator.sneakPeek.type == .codex {
    if !vm.hideOnClosed && activeSneakPeekStyle == .standard {
        GeometryReader { geo in
            HStack(spacing: 6) {
                Image(systemName: coordinator.sneakPeek.icon.isEmpty ? "sparkles" : coordinator.sneakPeek.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle((coordinator.sneakPeek.accentColor ?? .cyan).ensureMinimumBrightness(factor: 0.7))
                MarqueeText(
                    .constant(codexSneakPeekText()),
                    textColor: (coordinator.sneakPeek.accentColor ?? .cyan).ensureMinimumBrightness(factor: 0.7),
                    minDuration: 1,
                    frameWidth: max(0, geo.size.width - 20)
                )
            }
        }
        .padding(.bottom, 10)
    }
}
```

Add helper:

```swift
private func codexSneakPeekText() -> String {
    let title = coordinator.sneakPeek.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let subtitle = coordinator.sneakPeek.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty { return subtitle.isEmpty ? "Codex" : subtitle }
    if subtitle.isEmpty { return title }
    return "\(title) • \(subtitle)"
}
```

- [ ] **Step 7: Commit**

```bash
git add DynamicIsland/enums/generic.swift DynamicIsland/DynamicIslandViewCoordinator.swift DynamicIsland/components/Tabs/TabSelectionView.swift DynamicIsland/sizing/matters.swift DynamicIsland/ContentView.swift
git commit -m "feat: wire codex tab into notch"
```

---

### Task 6: App lifecycle 和设置页

**Files:**
- Create: `DynamicIsland/components/Settings/CodexSettings.swift`
- Modify: `DynamicIsland/DynamicIslandApp.swift`
- Modify: `DynamicIsland/components/Settings/SettingsView.swift`

- [ ] **Step 1: 新增 CodexSettings**

Create `DynamicIsland/components/Settings/CodexSettings.swift`:

```swift
import Defaults
import SwiftUI

struct CodexSettings: View {
    @ObservedObject private var manager = CodexManager.shared
    @Default(.enableCodexFeature) private var enableCodexFeature
    @Default(.codexPrivacyMode) private var privacyMode
    @Default(.codexActiveRefreshInterval) private var activeRefreshInterval
    @Default(.codexIdleRefreshInterval) private var idleRefreshInterval
    @Default(.codexShowWaitingAlerts) private var showWaitingAlerts
    @Default(.codexShowDoneAlerts) private var showDoneAlerts
    @Default(.codexShowErrorAlerts) private var showErrorAlerts
    @Default(.codexAlwaysShowTab) private var alwaysShowTab
    @Default(.codexMockStatusFilePath) private var mockStatusFilePath

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableCodexFeature) {
                    Text("Enable Codex integration")
                }
                Defaults.Toggle(key: .codexAlwaysShowTab) {
                    Text("Always show Codex tab")
                }
                .disabled(!enableCodexFeature)
            } header: {
                Text("Codex")
            } footer: {
                Text("Atoll only reads Codex status in this version. It does not send messages, stop tasks, or approve actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Privacy", selection: $privacyMode) {
                    ForEach(CodexPrivacyMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!enableCodexFeature)
            } header: {
                Text("Privacy")
            }

            Section {
                Defaults.Toggle(key: .codexShowWaitingAlerts) {
                    Text("Waiting alerts")
                }
                Defaults.Toggle(key: .codexShowDoneAlerts) {
                    Text("Done alerts")
                }
                Defaults.Toggle(key: .codexShowErrorAlerts) {
                    Text("Error alerts")
                }
            } header: {
                Text("Alerts")
            }
            .disabled(!enableCodexFeature)

            Section {
                Stepper(value: $activeRefreshInterval, in: 1...30, step: 1) {
                    Text("Active refresh: \(Int(activeRefreshInterval))s")
                }
                Stepper(value: $idleRefreshInterval, in: 2...60, step: 1) {
                    Text("Idle refresh: \(Int(idleRefreshInterval))s")
                }
            } header: {
                Text("Refresh")
            }
            .disabled(!enableCodexFeature)

            Section {
                TextField("Mock status file path", text: $mockStatusFilePath)
                    .textFieldStyle(.roundedBorder)
                Button("Refresh now") {
                    Task { await manager.refreshOnce() }
                }
                .disabled(!enableCodexFeature)
            } header: {
                Text("Diagnostics")
            } footer: {
                Text(manager.status.sourceAvailability.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: App 启动和设置变更时管理 CodexManager**

Modify `DynamicIsland/DynamicIslandApp.swift`, in `applicationDidFinishLaunching` after other manager setup:

```swift
if Defaults[.enableCodexFeature] {
    CodexManager.shared.start()
}

Defaults.publisher(.enableCodexFeature, options: [])
    .sink { change in
        if change.newValue {
            CodexManager.shared.start()
        } else {
            CodexManager.shared.stop()
        }
    }
    .store(in: &cancellables)

Defaults.publisher(.codexMockStatusFilePath, options: [])
    .sink { change in
        CodexManager.shared.configure(provider: change.newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UnsupportedCodexStatusProvider()
            : MockFileCodexStatusProvider(filePath: change.newValue)
        )
        if Defaults[.enableCodexFeature] {
            CodexManager.shared.start()
        }
    }
    .store(in: &cancellables)

Defaults.publisher(.enableCodexFeature, options: []).sink { [weak self] _ in
    self?.debouncedUpdateWindowSize()
}.store(in: &cancellables)
```

- [ ] **Step 3: SettingsView 新增 Codex tab**

Modify `DynamicIsland/components/Settings/SettingsView.swift`:

Add enum case:

```swift
case codex
```

Add group mapping:

```swift
case .extensions, .codex: return .integrations
```

Add title:

```swift
case .codex: return String(localized: "Codex")
```

Add system image:

```swift
case .codex: return "sparkles"
```

Add tint:

```swift
case .codex: return .cyan
```

Add to ordered tabs before `.extensions`:

```swift
.codex,
```

Add content switch:

```swift
case .codex:
    SettingsForm(tab: .codex) {
        CodexSettings()
    }
```

Add search entries:

```swift
SettingsSearchEntry(tab: .codex, title: "Enable Codex integration", keywords: ["codex", "ai", "thread", "status"], highlightID: SettingsTab.codex.highlightID(for: "Enable Codex integration")),
SettingsSearchEntry(tab: .codex, title: "Privacy", keywords: ["codex", "privacy", "summary"], highlightID: SettingsTab.codex.highlightID(for: "Privacy")),
```

- [ ] **Step 4: Commit**

```bash
git add DynamicIsland/components/Settings/CodexSettings.swift DynamicIsland/DynamicIslandApp.swift DynamicIsland/components/Settings/SettingsView.swift
git commit -m "feat: add codex settings"
```

---

### Task 7: Xcode project 文件接入

**Files:**
- Modify: `DynamicIsland.xcodeproj/project.pbxproj`

- [ ] **Step 1: 使用 Xcode 或脚本把新增 Swift 文件加入 target**

Add these files to the DynamicIsland target:

```text
DynamicIsland/models/CodexStatusModels.swift
DynamicIsland/managers/CodexStatusProvider.swift
DynamicIsland/managers/CodexManager.swift
DynamicIsland/components/Notch/NotchCodexView.swift
DynamicIsland/components/Notch/CodexMinimalisticView.swift
DynamicIsland/components/Settings/CodexSettings.swift
```

Preferred manual method:

```text
Open DynamicIsland.xcodeproj in Xcode.
Right click matching groups.
Choose Add Files to "DynamicIsland"...
Select the six files.
Check target membership "DynamicIsland".
Save project.
```

If using a script, preserve existing project formatting and only add PBXFileReference/PBXBuildFile/PBXSourcesBuildPhase entries for the six files.

- [ ] **Step 2: Verify project references**

Run:

```bash
rg -n "CodexStatusModels|CodexStatusProvider|CodexManager|NotchCodexView|CodexMinimalisticView|CodexSettings" DynamicIsland.xcodeproj/project.pbxproj
```

Expected:

```text
Each new Swift file appears in the project file and in Sources build phase references.
```

- [ ] **Step 3: Commit**

```bash
git add DynamicIsland.xcodeproj/project.pbxproj
git commit -m "build: include codex manager files"
```

---

### Task 8: 编译和手动验证

**Files:**
- No required edits unless verification finds build errors.

- [ ] **Step 1: 检查 Xcode 环境**

Run:

```bash
xcode-select -p
xcodebuild -list -project DynamicIsland.xcodeproj
```

Expected if full Xcode is selected:

```text
Information about project "DynamicIsland":
    Targets:
        DynamicIsland
```

If it fails with CommandLineTools, run only after user switches Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 3: 手动 mock 验证**

Create `/private/tmp/atoll-codex-status.json` with a supported encoded shape from Task 2, then set it in Settings -> Codex -> Mock status file path.

Toggle states in the mock file:

```json
{
  "threadId": "local-current",
  "title": "Atoll Codex Manager",
  "state": "waiting",
  "summary": "等待用户确认下一步",
  "lastUpdatedAt": "2026-06-19T12:05:00Z",
  "workingStartedAt": "2026-06-19T12:00:00Z",
  "sourceAvailability": {
    "available": {}
  }
}
```

Expected:

```text
Codex tab appears when enabled.
Closed notch does not show thread title or summary.
Expanded Codex tab shows title and summary when privacy is Summary.
Waiting state triggers a short sneak peek when alert is enabled.
Done and error states use distinct colors.
```

- [ ] **Step 4: Privacy verification**

Set Settings -> Codex -> Privacy to Minimal.

Expected:

```text
Closed notch shows only Codex/state indicator.
Expanded tab hides summary and shows "Details hidden by privacy settings".
No raw command output appears anywhere.
```

- [ ] **Step 5: Final status**

Run:

```bash
git status --short
git log --oneline -8
```

Expected:

```text
No uncommitted changes, unless build fixes were intentionally made and committed.
Recent commits show each Codex Manager task commit.
```

---

## Self-Review

- Spec coverage:
  - 内置 `CodexManager`: Task 3.
  - 状态模型和 provider 抽象: Task 1, Task 2.
  - 展开态和极简态 UI: Task 4.
  - 设置项: Task 6.
  - tab/coordinator/content 集成: Task 5.
  - 长任务状态提醒: Task 3 and Task 5.
  - 第一版只读和隐私限制: Task 1, Task 3, Task 4, Task 8.
- Placeholder scan:
  - 未发现占位词或缺少落地细节的步骤。
  - Open Codex real interface remains intentionally unsupported in first provider; mock/provider abstraction keeps implementation testable without pretending a stable external API exists.
- Type consistency:
  - `CodexRunState`, `CodexSourceAvailability`, `CodexPrivacyMode`, `CodexThreadStatus`, `CodexStatusProvider`, `CodexManager`, `NotchCodexView`, `CodexMinimalisticView`, and `CodexSettings` are consistently named across tasks.
