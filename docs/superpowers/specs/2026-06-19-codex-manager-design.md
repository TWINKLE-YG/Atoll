# Atoll Built-In Codex Manager Design

Date: 2026-06-19
Status: Draft for user review
Target repository: `/Users/twinkle/workProjects/atoll/Atoll`

## Goal

Add a built-in Codex integration to Atoll so the Dynamic Island can show the current Codex Desktop thread's status and long-running task progress.

The first version is intentionally read-only. Atoll observes Codex state and presents it in the notch, but it does not send prompts, stop tasks, approve actions, or mutate Codex threads.

## Product Shape

The integration should feel like a native Atoll feature, similar to Media, Stats, Timer, Clipboard, and Terminal. It should not rely on Atoll's third-party extension surface as the final architecture.

Closed or minimalistic presentation is privacy-first:

- Show a Codex icon or compact status indicator.
- Show status color and a short state label only.
- Do not show thread title, prompt text, command output, or summaries while closed.

Expanded presentation can show useful detail:

- Current thread title.
- Thread state.
- Current phase or recent assistant summary.
- Last updated time.
- Elapsed working time when a task is active.
- Completion, waiting, or failure messages in a compact form.

## First-Version Scope

Build:

- `CodexManager` as a built-in Atoll manager.
- `CodexThreadStatus` and related status models.
- `CodexStatusProvider` protocol to isolate the Codex data source.
- A first provider implementation that can read the current Codex Desktop thread status through the safest available local mechanism.
- `CodexTabView` for expanded notch UI.
- A minimalistic/closed Codex status view.
- Settings for enabling Codex integration, privacy level, refresh interval, and completion/waiting/error alerts.
- State transition notifications for long-running tasks.

Do not build in the first version:

- Sending user messages to Codex from Atoll.
- Stopping, resuming, or approving Codex actions.
- Managing multiple Codex threads.
- Cloud or remote-host Codex aggregation.
- Reading full conversation transcripts.
- Displaying raw command outputs.
- Automatically interpreting logs or test output.

## Status Model

`CodexThreadStatus` should be small and stable:

- `threadId: String?`
- `title: String?`
- `state: CodexRunState`
- `summary: String?`
- `lastUpdatedAt: Date?`
- `workingStartedAt: Date?`
- `sourceAvailability: CodexSourceAvailability`

`CodexRunState`:

- `idle`: no active work is running.
- `working`: Codex is actively processing the current thread.
- `waiting`: Codex is waiting for user input or approval.
- `done`: the most recent active task completed.
- `error`: the most recent task failed or became blocked.
- `unknown`: the source cannot confidently determine state.

`CodexSourceAvailability`:

- `available`
- `codexNotRunning`
- `permissionDenied`
- `unsupported`
- `error(message: String)`

## Architecture

### CodexManager

`CodexManager` is an `ObservableObject` owned as a singleton, matching the existing Atoll manager style.

Responsibilities:

- Own the active `CodexThreadStatus`.
- Poll or subscribe to `CodexStatusProvider`.
- Debounce noisy updates.
- Detect important state transitions.
- Publish status for SwiftUI views.
- Trigger Atoll sneak peek/live-style alerts for waiting, done, and error states.

It should not know how Codex stores thread data. That belongs behind `CodexStatusProvider`.

### CodexStatusProvider

The provider protocol keeps the first implementation replaceable:

```swift
protocol CodexStatusProvider {
    func currentThreadStatus() async -> CodexThreadStatus
}
```

The first provider should prefer an official or app-supported status surface if one exists in the local Codex environment. If no stable public interface is available, the implementation should remain isolated and conservative, returning `unsupported` rather than scraping fragile private data deeply.

### UI Components

`CodexTabView`:

- Shows current status, title, summary, elapsed time, and last update.
- Uses compact text and stable dimensions suitable for the notch.
- Provides empty and unavailable states.

`CodexMinimalisticView`:

- Shows only icon, state color, and short status label.
- Never shows title or summary.

`CodexSettingsSection`:

- Enable Codex integration.
- Privacy mode: minimal only, expanded summary, expanded detailed.
- Alert toggles: waiting, done, error.
- Refresh interval.
- Diagnostics state for provider availability.

## UI Behavior

Closed notch:

- `working`: Codex icon plus active accent color.
- `waiting`: Codex icon plus waiting accent color.
- `done`: short success pulse, then return to idle.
- `error`: short error pulse, then persist in expanded tab until replaced.
- `idle`: no persistent interruption unless user enables always-show.

Sneak peek:

- Show when Codex starts working.
- Show when Codex waits for user input or approval.
- Show when work completes.
- Show when work fails or becomes blocked.

Expanded tab:

- Show details according to privacy settings.
- Never show raw command output in version one.
- Use truncation and wrapping so text never changes the notch layout unexpectedly.

## Data Flow

1. `CodexManager` refreshes through `CodexStatusProvider`.
2. Provider returns a normalized `CodexThreadStatus`.
3. `CodexManager` compares old and new status.
4. State transitions update SwiftUI views and optional alerts.
5. `DynamicIslandViewCoordinator` exposes the Codex tab when the feature is enabled.
6. Content views render either minimalistic or expanded Codex UI.

## Settings Defaults

- Codex integration: off by default.
- Privacy mode: minimal closed, summary expanded.
- Alerts: waiting/done/error on.
- Refresh interval: conservative default, such as 2 seconds while Codex is active and 10 seconds while idle.
- Raw output display: unavailable in version one.

## Error Handling

If Codex is unavailable:

- Show `Codex unavailable` in the expanded tab.
- Do not repeatedly alert.
- Surface a short diagnostic in settings.

If the provider cannot determine state:

- Publish `unknown`.
- Keep the previous known state only for a short grace period.
- Avoid showing stale task details as current.

If permissions are missing:

- Show `Permission needed` in the expanded tab.
- Explain the missing capability in settings.
- Do not request broad permissions unless a specific provider requires them.

## Testing And Verification

Unit-level:

- State normalization for provider results.
- Transition detection in `CodexManager`.
- Privacy filtering for closed/minimalistic presentation.
- Unavailable and unknown source handling.

UI-level:

- Closed view never renders thread title or summary.
- Expanded view respects privacy level.
- Long title and summary text are truncated or wrapped without overlap.
- Waiting, done, and error states have distinct visual treatment.

Manual:

- Start Atoll with Codex closed.
- Start Atoll with Codex open and idle.
- Run a long Codex task and verify working progress.
- Let Codex wait for user input and verify waiting alert.
- Finish a task and verify completion alert.
- Force provider failure and verify unavailable state.

## Implementation Notes

The Atoll repository currently has an extension RPC system at `localhost:9020`, but the final target is a built-in manager, not a third-party extension client. The RPC path may still be useful for early mock testing, but production code should integrate with Atoll's native manager/view/settings patterns.

Known nearby files and patterns:

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/managers/TimerManager.swift`
- `DynamicIsland/managers/ClipboardManager.swift`
- `DynamicIsland/DynamicIslandViewCoordinator.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/components/Settings/SettingsView.swift`
- `DynamicIsland/components/Settings/ExtensionsSettings.swift`

## Open Questions Before Implementation

- What stable local status surface can Codex Desktop expose to a separate macOS app?
- Should Atoll include a small helper inside the app bundle if direct Codex status access is unavailable?
- Should the Codex tab be always visible when enabled, or only visible while a thread is active?
- What icon asset should represent Codex inside Atoll?

