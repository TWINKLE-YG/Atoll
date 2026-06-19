# Atoll 内置 Codex Manager 设计

日期：2026-06-19
状态：待用户 review
目标仓库：`/Users/twinkle/workProjects/atoll/Atoll`

## 目标

在 Atoll 中新增一个内置 Codex 集成，让灵动岛可以展示 Codex 桌面 App 当前线程的状态，以及长任务运行进度。

第一版保持只读。Atoll 只观察 Codex 状态并在灵动岛中展示，不发送 prompt，不停止任务，不审批操作，也不修改 Codex 线程。

## 产品形态

这个集成应该像 Atoll 原生功能，而不是第三方扩展。体验上应接近 Media、Stats、Timer、Clipboard、Terminal 这些内置能力。

闭合或极简状态优先保护隐私：

- 只显示 Codex 图标或紧凑状态指示器。
- 只显示状态颜色和很短的状态文案。
- 闭合时不显示线程标题、prompt 内容、命令输出或摘要。

展开状态可以显示更有用的信息：

- 当前线程标题。
- 当前线程状态。
- 当前阶段或最近的 assistant 摘要。
- 最后更新时间。
- 任务运行中的已用时。
- 完成、等待、失败等状态的简短提示。

## 第一版范围

第一版要做：

- 新增内置 `CodexManager`。
- 新增 `CodexThreadStatus` 及相关状态模型。
- 新增 `CodexStatusProvider` 协议，用来隔离 Codex 状态数据源。
- 实现第一个 provider，通过当前本地环境里最安全的方式读取 Codex 桌面线程状态。
- 新增展开态 UI：`CodexTabView`。
- 新增闭合/极简态 Codex 状态视图。
- 新增设置项：启用 Codex 集成、隐私级别、刷新间隔、完成/等待/失败提醒。
- 监听状态变化，为长任务触发提醒。

第一版不做：

- 从 Atoll 里给 Codex 发送消息。
- 停止、继续或审批 Codex 操作。
- 管理多个 Codex 线程。
- 聚合云端 Codex 或远程主机线程。
- 读取完整聊天记录。
- 展示原始命令输出。
- 自动分析日志或测试输出。

## 状态模型

`CodexThreadStatus` 要保持小而稳定：

- `threadId: String?`
- `title: String?`
- `state: CodexRunState`
- `summary: String?`
- `lastUpdatedAt: Date?`
- `workingStartedAt: Date?`
- `sourceAvailability: CodexSourceAvailability`

`CodexRunState`：

- `idle`：没有活跃任务。
- `working`：Codex 正在处理当前线程。
- `waiting`：Codex 正在等待用户输入或审批。
- `done`：最近一次活跃任务已完成。
- `error`：最近一次任务失败或被阻塞。
- `unknown`：数据源无法可靠判断状态。

`CodexSourceAvailability`：

- `available`
- `codexNotRunning`
- `permissionDenied`
- `unsupported`
- `error(message: String)`

## 架构

### CodexManager

`CodexManager` 是一个 `ObservableObject` 单例，风格上对齐 Atoll 现有 manager。

职责：

- 持有当前 `CodexThreadStatus`。
- 通过 `CodexStatusProvider` 轮询或订阅状态。
- 对高频更新做 debounce。
- 检测关键状态迁移。
- 向 SwiftUI 视图发布状态。
- 在 waiting、done、error 等状态出现时触发 Atoll 的 sneak peek 或类似 live activity 的提醒。

`CodexManager` 不应该知道 Codex 如何存储线程数据。这部分细节必须放在 `CodexStatusProvider` 后面。

### CodexStatusProvider

provider 协议用于保证第一版实现以后可替换：

```swift
protocol CodexStatusProvider {
    func currentThreadStatus() async -> CodexThreadStatus
}
```

第一版 provider 应优先使用本地 Codex 环境中官方或 app 支持的状态接口。如果没有稳定公开接口，实现要保持隔离和保守：宁可返回 `unsupported`，也不要深度抓取脆弱的私有数据。

### UI 组件

`CodexTabView`：

- 展示当前状态、标题、摘要、已用时和最后更新时间。
- 使用适合灵动岛的紧凑文本和稳定尺寸。
- 支持空状态和不可用状态。

`CodexMinimalisticView`：

- 只展示图标、状态颜色和短状态文案。
- 永远不展示标题或摘要。

`CodexSettingsSection`：

- 启用 Codex 集成。
- 隐私模式：仅极简、展开显示摘要、展开显示详细信息。
- 提醒开关：等待、完成、失败。
- 刷新间隔。
- provider 可用性诊断状态。

## UI 行为

闭合灵动岛：

- `working`：显示 Codex 图标和活跃状态强调色。
- `waiting`：显示 Codex 图标和等待状态强调色。
- `done`：短暂成功反馈，然后回到 idle。
- `error`：短暂错误反馈，并在展开 tab 中保留错误状态，直到被新状态替换。
- `idle`：默认不持续打扰，除非用户开启 always-show。

Sneak peek：

- Codex 开始工作时显示。
- Codex 等待用户输入或审批时显示。
- 工作完成时显示。
- 工作失败或阻塞时显示。

展开 tab：

- 根据隐私设置显示详细程度。
- 第一版永远不显示原始命令输出。
- 标题和摘要要截断或换行，不能让灵动岛布局抖动或重叠。

## 数据流

1. `CodexManager` 通过 `CodexStatusProvider` 刷新状态。
2. provider 返回标准化后的 `CodexThreadStatus`。
3. `CodexManager` 对比新旧状态。
4. 状态迁移驱动 SwiftUI 视图刷新和可选提醒。
5. 功能启用时，`DynamicIslandViewCoordinator` 暴露 Codex tab。
6. 内容视图根据当前模式渲染极简态或展开态 Codex UI。

## 默认设置

- Codex 集成：默认关闭。
- 隐私模式：闭合极简，展开显示摘要。
- 提醒：等待、完成、失败默认开启。
- 刷新间隔：保守默认值，例如 Codex 活跃时 2 秒，空闲时 10 秒。
- 原始输出展示：第一版不可用。

## 错误处理

Codex 不可用时：

- 展开 tab 显示 `Codex unavailable`。
- 不反复弹提醒。
- 在设置页显示简短诊断。

provider 无法判断状态时：

- 发布 `unknown`。
- 只在很短的宽限期内保留上一次已知状态。
- 避免把过期任务信息展示成当前状态。

缺少权限时：

- 展开 tab 显示 `Permission needed`。
- 在设置页说明缺少哪种能力。
- 除非具体 provider 需要，否则不请求宽泛权限。

## 测试与验证

单元层：

- provider 结果到状态模型的标准化。
- `CodexManager` 的状态迁移检测。
- 闭合/极简态的隐私过滤。
- 不可用和 unknown 状态处理。

UI 层：

- 闭合视图永远不渲染线程标题或摘要。
- 展开视图遵守隐私级别。
- 长标题和长摘要不会溢出、重叠或撑坏布局。
- waiting、done、error 有清晰不同的视觉表现。

手动验证：

- Codex 未打开时启动 Atoll。
- Codex 打开且空闲时启动 Atoll。
- 运行一个长 Codex 任务，验证 working 进度展示。
- 让 Codex 等待用户输入，验证 waiting 提醒。
- 完成任务，验证完成提醒。
- 强制 provider 失败，验证不可用状态。

## 实现备注

Atoll 当前已经有基于 `localhost:9020` 的 extension RPC 系统，但最终目标是内置 manager，而不是第三方 extension client。RPC 路径可以用于早期 mock 测试，但正式实现应对齐 Atoll 原生 manager、view、settings 模式。

可参考的现有文件和模式：

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/managers/TimerManager.swift`
- `DynamicIsland/managers/ClipboardManager.swift`
- `DynamicIsland/DynamicIslandViewCoordinator.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/components/Settings/SettingsView.swift`
- `DynamicIsland/components/Settings/ExtensionsSettings.swift`

## 实现前待确认问题

- Codex 桌面 App 能否向独立 macOS app 暴露稳定的本地状态接口？
- 如果无法直接读取 Codex 状态，Atoll 是否需要在 app bundle 中包含一个小 helper？
- Codex tab 应该在功能启用后始终可见，还是只在当前线程活跃时可见？
- Atoll 内部应该使用什么图标资产表示 Codex？

