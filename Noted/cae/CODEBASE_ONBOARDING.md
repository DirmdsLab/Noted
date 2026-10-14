# Caelestia Shell — technical onboarding and reverse-engineering report

Repository inspected: `shell/` from `shell(1).zip` at commit `6f7ce62b` (`fix(core): release image grabs after saving (#2093)`). The repository contains 491 archived files including assets and Git metadata; the analysis below focuses on the QML, C++, build, configuration, packaging, and CI files.

Evidence labels used below:

- **VERIFIED** — directly visible in source/configuration.
- **INFERRED** — a strong architectural conclusion derived from several verified relationships.
- **UNKNOWN** — not determinable from this repository.

## 1. Executive summary

**VERIFIED:** This is `caelestia-shell`, a Linux desktop shell implemented mostly in QML and hosted by Quickshell. It renders a multi-monitor Wayland UI for Hyprland: a background, bar, drawers (dashboard, launcher, session, sidebar, utilities, OSD, notifications and popouts), screenshot area picker, lock screen, and status/utility widgets. The top-level QML entry is `shell.qml`.

**VERIFIED:** The UI calls Quickshell APIs and Caelestia C++ QML modules. The C++ modules provide configuration/settings persistence, system metrics, Hyprland socket integration, DBus session operations, lyrics/network requests, file/application models, image utilities, custom visual components, and translations. CMake builds the C++ QML plugins and installs the QML tree; Nix wraps Quickshell as `caelestia-shell`.

**INFERRED:** The effective architecture is a reactive QML composition with singleton service objects, backed by a small C++ platform/infrastructure layer. It is a desktop application, not a web service or daemon with an HTTP server. Most business behavior is distributed between QML service singletons and feature modules; C++ is used where Qt/system APIs, concurrency, socket/DBus access, or performance-sensitive work is needed.

**VERIFIED:** Runtime state is primarily in memory (QML singleton properties, per-screen `ScreenState`, Quickshell/Hyprland models). Durable state is JSON under `~/.config/caelestia`, state files under the configured state path, user media files, optional SQLite app-frequency data, and external system state managed by Hyprland, PipeWire, NetworkManager, login1, PAM, and the Caelestia CLI.

**UNKNOWN:** The CLI implementation (`caelestia`) and the Quickshell implementation are external dependencies, so their internal command parsing, persistence details, and exact IPC transport are not part of this repository.

## 2. Technology stack

| Area | Evidence | What it means |
|---|---|---|
| Runtime/UI | QML/Qt 6, Quickshell | `shell.qml`, 200+ QML components, imports of `QtQuick`, `Quickshell`, `Quickshell.Wayland`, `Quickshell.Hyprland`. |
| Native layer | C++20, Qt 6 QML modules | Root `CMakeLists.txt` sets C++20; `plugin/cmake/qml-module.cmake` calls `qt_add_qml_module`. |
| Windowing/compositor | Wayland + Hyprland | `StyledWindow`, `WlrLayershell`, `Hyprland`, `HyprlandFocusGrab`, and C++ Hyprland local sockets. |
| Audio/media | PipeWire, MPRIS, libcava, aubio | `services/Audio.qml`, `services/Players.qml`, C++ `audioprovider`, `cavaprovider`, `beattracker`. |
| System | UPower, `/proc`, `/sys`, sensors, login1 DBus, PAM | `BatteryMonitor.qml`, C++ metrics services, `sessionmanager.cpp`, `modules/lock/Pam.qml`. |
| Networking | NetworkManager `nmcli`, HTTP(S) | `services/Nmcli.qml`, `services/VPN.qml`, `Caelestia::Requests`, `Weather.qml`, C++ lyrics backends. |
| Persistence | JSON config/state, QFileSystemWatcher, optional SQLite | C++ settings tree writes JSON; `FileView` reads state; `AppDb` uses SQLite `:memory:` by default or a configured path. |
| Build/package | CMake + Ninja; Nix flake/Home Manager; GitHub Actions | `CMakeLists.txt`, `flake.nix`, `nix/default.nix`, `nix/hm-module.nix`, `.github/workflows/*`. |
| External CLI | `caelestia`, `brightnessctl`, `ddcutil`, `nmcli`, `swappy`, `wl-copy`, `notify-send`, `gpu-screen-recorder`, `hyprctl`, shell commands | Spawned through `Process` or `Quickshell.execDetached`; binaries are not implemented here. |
| Tests | No application test tree found | CI builds and runs QML/C++ lint; no unit/integration/e2e tests are present in the archive. |

## 3. Repository map

```text
shell/
├── shell.qml                         Quickshell root and application composition
├── components/                       Reusable visual controls/layout/effects/file dialog
├── modules/                          Feature UI and composition by desktop feature
│   ├── drawers/                      Per-monitor layer-shell window, panels, hit regions
│   ├── bar/                          Bar, workspaces, tray, status and popouts
│   ├── dashboard/                    Dashboard/media/performance/weather
│   ├── launcher/                     App/wallpaper/action/scheme launcher
│   ├── lock/                         Wayland session lock and PAM UI
│   ├── nexus/                        Settings/control-center window and pages
│   ├── notifications/                Notification panel/popups
│   ├── sidebar/                      Notification/sidebar presentation
│   ├── utilities/                    Toggles, recording, idle inhibition and toasts
│   ├── background/                   Wallpaper, clock, visualiser
│   ├── areapicker/                   Screenshot selection and save/copy flow
│   ├── osd/                          On-screen display
│   ├── session/                      Power/session actions
│   └── windowinfo/                   Active-window details/preview
├── services/                         QML singleton state and system adapters
├── utils/                            Paths, icons, search, network helpers
├── plugin/src/Caelestia/              Native QML modules
│   ├── Config/                       Typed config schema, overlays, tokens
│   ├── Settings/                     JSON schema/load/save/watch machinery
│   ├── Services/                     Hyprland, DBus, audio, metrics, lyrics
│   ├── Models/                       File system and app-frequency models
│   ├── Components/                   Native visual/custom QML items
│   ├── Blobs/                        Shape/material/shader primitives
│   ├── Images/                       Image analysis/cache/provider
│   ├── I18n/                         Translation and plural rules
│   └── core files                    CUtils, Requests, Qalculator, Toaster
├── assets/                            Fonts, fallback wallpaper, PAM snippets, scripts
├── extras/version.cpp                 Installed version helper executable
├── nix/                               Nix package and Home Manager module
├── scripts/                           QML lint/translation checks
├── CMakeLists.txt                     Build/install graph
├── flake.nix                          Nix inputs/outputs/dev shell
├── README.md                          User-facing install/config/usage docs
└── .github/workflows/                 Build, lint, formatting, release and image workflows
```

### Directory responsibilities and dependencies

- `components/` is the lowest-level QML UI layer. It imports Qt/Quickshell and, where needed, `Caelestia.Config` and `qs.utils`; feature modules consume it.
- `services/` is the application integration layer. Most files are `pragma Singleton`; they hold live state, expose methods, register `IpcHandler` targets, and call Quickshell APIs, C++ singletons, local files, external commands, or HTTP.
- `modules/` composes screens and feature workflows. It consumes services and components and mutates `ScreenState` or feature-local state.
- `plugin/src/Caelestia/` is the native boundary. The CMake helper creates importable QML modules (`Caelestia`, `Caelestia.Config`, `Caelestia.Services`, `Caelestia.Models`, etc.) and installs their generated `qmldir`/type info and plugin libraries.
- `nix/` is packaging/deployment configuration, not runtime domain logic.
- `assets/` contains runtime resources and PAM configuration fragments; it is installed alongside QML.

## 4. Actual architecture

### Classification

**INFERRED:** This is a reactive, component-based desktop UI with a service-singleton architecture. It resembles a modular monolith at the process level: all QML features run in one Quickshell process and share singleton state; there are no separately deployable services in the repository.

The evidence for this classification is:

1. `shell.qml` instantiates all top-level features in one `ShellRoot`.
2. `services/*.qml` expose process-wide singletons (`Audio`, `Hypr`, `Weather`, `Players`, etc.).
3. `modules/drawers/Drawers.qml` creates one `ContentWindow` per enabled screen and composes all panels under that window.
4. Native functionality is linked into QML import modules rather than exposed as a separate process.
5. Interactions with other processes are boundary calls (Hyprland sockets, DBus, HTTP, PipeWire, PAM, and CLI processes).

### Layer-by-layer behavior

**Presentation/composition (`modules/`, `components/`)**

- Inputs: `ScreenState`, singleton services, config/token attached properties, Quickshell models.
- Outputs: QML items/windows, user input events, calls into services.
- Side effects: usually state mutations and calls to service methods; some components directly invoke external commands (for example screenshot copy or session fallback).
- Consumers: `shell.qml` and `modules/drawers/Panels.qml`.

**QML integration/services (`services/`, `modules/*/services/`)**

- Inputs: Quickshell objects, Hyprland models/events, config, user actions.
- Outputs: properties/signals, IPC handlers, requests to native services or commands.
- Side effects: command execution, file reads/writes through `FileView`, network requests through `Requests`, Hyprland dispatch, PipeWire mutations, DBus actions.
- Consumers: feature modules and external `caelestia shell ...` IPC calls.

**Native QML modules (`plugin/src/Caelestia/`)**

- Inputs: Qt/OS APIs and QML calls.
- Outputs: QML singleton/types/properties/signals.
- Side effects: JSON file I/O, QFileSystemWatcher, QNetworkAccessManager, QLocalSocket, QDBus, SQLite, threads/timers, image/file operations.
- Consumers: QML imports `Caelestia*`.

**Packaging/initialization (`CMakeLists.txt`, `flake.nix`, `nix/*`)**

- Inputs: source tree, Git version/revision, Nix inputs or system packages.
- Outputs: installed QML tree, plugin libraries, `caelestia-shell` wrapper and optional version helper.
- Side effects: install files and define a systemd user service through the Home Manager module.

### Architectural boundaries and coupling

- **Verified boundary:** QML calls native types through QML modules; native code does not import feature QML.
- **Verified boundary:** `SessionManager` owns login1 DBus calls; `HyprExtras` owns low-level Hyprland local-socket requests/events; higher-level QML `Hypr` adapts them for UI.
- **Verified coupling:** feature modules import broad `qs.services`; many modules therefore depend on global singleton state rather than narrow interfaces.
- **Verified coupling:** commands are often hard-coded in QML (`caelestia`, `nmcli`, `hyprctl`, `swappy`, `wl-copy`, etc.), so runtime behavior depends on external executables and PATH.
- **Potential concern:** the same business action can have multiple entry points (shortcut, `IpcHandler`, UI click, or external CLI), and they sometimes converge only by convention rather than a typed command bus.
- **Potential concern:** singleton mutable state makes feature behavior easy to reach but makes isolated testing difficult.

## 5. True entry points

| Entry point | File/function | Trigger | First significant call | Downstream flow | Final output |
|---|---|---|---|---|---|
| Shell process | External `caelestia shell -d` (README) or `qs -c caelestia -n -d`; Nix wrapper `nix/default.nix` | User/Hyprland startup | Quickshell loads installed `shell.qml` | `ShellRoot` → loaders/modules/services | Wayland layer-shell windows and IPC handlers |
| QML bootstrap | `shell.qml:16` `ShellRoot` | Quickshell config load | `Binding` to `ShellState`, then `ServiceLoader` and feature objects | Background, Drawers, AreaPicker, Lock, Shortcuts, BatteryMonitor, IdleMonitors | Live desktop shell |
| Service eager load | `modules/ServiceLoader.qml:7-19` | `Component.onCompleted` | References `IdleInhibitor`, `GameMode`, `Notifs`, `Players`, `Brightness`; calls `Weather.reload()` | Singleton initialization and initial polling/network work | Services ready before user opens most panels |
| Per-monitor UI | `modules/drawers/Drawers.qml:7-25` | `Screens.screens` model changes | Creates `ContentWindow` for each enabled `ShellScreen` | `ContentWindow` → `Panels` → bar/dashboard/launcher/... | One top-level shell window per configured monitor |
| Global shortcut | `modules/Shortcuts.qml` `CustomShortcut` handlers | Quickshell/Hyprland global shortcut | Reads `ShellState.forActive()` | Mutates active screen booleans or calls `WindowFactory.create()` | Drawer toggled or Nexus window opened |
| IPC command | QML `IpcHandler` targets (`drawers`, `wallpaper`, `mpris`, `lock`, etc.) | `caelestia shell ...` / Quickshell IPC | Target method | Same service/module method as UI path | State transition or command result |
| Lock request | `modules/lock/Lock.qml` + `SessionManager` signals | Shortcut, IPC, login1 `Lock` signal | `WlSessionLock.locked = true` | `LockSurface` + `Pam.qml` | Secure lock surface; unlock on PAM success |
| Screenshot | `modules/areapicker/AreaPicker.qml` | Shortcut or `picker` IPC | Activates per-screen overlay | `Picker.save()` → `CUtils.saveItem()` → `swappy` or `wl-copy`/`notify-send` | Saved PNG and/or clipboard |

### Startup execution map

```text
caelestia shell -d / qs -c caelestia
        ↓
Quickshell loads shell.qml
        ↓
ShellRoot + settings.watchFiles
        ↓
ServiceLoader (eager singleton initialization)
        ↓
Background + Drawers + AreaPicker + Lock + Shortcuts + BatteryMonitor + IdleMonitors
        ↓
Screens.screens filters enabled monitors
        ↓
Drawers creates ContentWindow per monitor
        ↓
ContentWindow creates Panels and feature wrappers
        ↓
Reactive bindings consume services/config/Hyprland models
```

## 6. Module dependency map

### Core modules

- `shell.qml` → `modules`, `modules/drawers`, `modules/background`, `modules/areapicker`, `modules/lock`, `qs.services`.
- `modules/drawers/Drawers.qml` → `Screens` and `ContentWindow`.
- `modules/drawers/ContentWindow.qml` → `Hypr`, `ShellState`, `Colours`, config/tokens, `Bar`, `Panels`, `Interactions`, layer-shell primitives.
- `modules/drawers/Panels.qml` → all major feature wrappers: bar, dashboard, launcher, notifications, OSD, session, sidebar, utilities, bar popouts, toasts.
- `services/ShellState.qml` → `Screens`, `Hypr`, `ScreenState`; stores per-screen state and component references.
- `services/Hypr.qml` → Quickshell `Hyprland` plus native `HyprExtras`; centralizes monitor/workspace/window dispatch and refresh behavior.
- `services/Colours.qml` → `Hypr`, `Wallpapers`, `ImageAnalyser`, config/tokens; controls palette/transparency and Hyprland blur rules.
- `Caelestia.Config` → `Caelestia.Settings`; `Caelestia.Services` → core/config and Qt system libraries.

### Important dependency directions

```text
UI modules/components
        ↓
QML singleton services / config / tokens
        ↓
Quickshell APIs + Caelestia C++ QML types
        ↓
OS/system sockets, DBus, PipeWire, files, HTTP, external commands
```

### Core, boundary, and leaf modules

- **Core:** `ShellState`, `Screens`, `Hypr`, `GlobalConfig`, `TokenConfig`, `Panels`, `ContentWindow`.
- **Boundaries:** `HyprExtras`, `SessionManager`, `Requests`, `Audio`/PipeWire, `Nmcli`, `VPN`, `Pam`, C++ `Lyrics`, external CLI invocations.
- **Leaf-like UI:** individual controls under `components/controls`, status cards, icon/text primitives.
- **High fan-in:** `qs.services`, `Caelestia.Config`, `qs.components`; changing their public properties can affect most features.
- **Circular runtime reachability (not import cycle):** `Colours` reads `Wallpapers.current`; `Wallpapers` uses `Colours` for preview updates. This is coordinated through properties/timers, not a direct C++ cycle.

## 7. Main execution flows

### A. Open/toggle a drawer

```text
Hyprland global shortcut or IPC `drawers toggle <name>`
  ↓
modules/Shortcuts.qml: CustomShortcut or IpcHandler.toggle()
  ↓
ShellState.forActive()
  ↓
ScreenState.launcher/dashboard/session/sidebar/utilities/... boolean
  ↓
ContentWindow.qml observes screenState
  ↓
Panels.qml feature wrapper becomes visible/animated
  ↓
Feature module reads services and renders
```

**VERIFIED:** `Shortcuts.qml` suppresses some drawer opens when a fullscreen toplevel is present (`hasFullscreen`). `ContentWindow.qml` also closes launcher/session/dashboard and popouts on fullscreen transitions and uses `HyprlandFocusGrab` to clear drawer state when focus is lost.

### B. Launcher app/action execution

1. `modules/launcher/Content.qml:onAccepted` chooses the selected list item.
2. Wallpaper selection calls `Wallpapers.setWallpaper()`.
3. Prefix actions call an item `onClicked()`; calculator actions invoke the calculator item.
4. Normal app selection calls `Apps.launch(modelData)`.
5. `modules/launcher/services/Actions.qml` first tries `SessionManager.exec(command)` for power/session commands; otherwise calls `Quickshell.execDetached(command)`.
6. `modules/launcher/services/Apps.qml` executes the desktop entry command and uses `AppDb.incrementFrequency()` (via the app model path) to update ranking.
7. `plugin/src/Caelestia/Models/appdb.cpp` persists frequencies in SQLite, defaulting to `:memory:` unless a path is configured.

Failure behavior: external process startup/exit behavior is delegated to Quickshell; `SessionManager.exec()` returns `false` for unsupported commands, which triggers the CLI fallback. The repository does not provide a global action error dialog for arbitrary command failures.

### C. Wallpaper and dynamic colour flow

```text
Launcher wallpaper item / wallpaper IPC
  ↓
services/Wallpapers.qml:setWallpaper(path)
  ↓
Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...])
  ↓
External CLI writes wallpaper state (expected at `${Paths.state}/wallpaper/path.txt`)
  ↓
FileView watcher updates `actualCurrent`
  ↓
services/Colours.qml ImageAnalyser reads `Wallpapers.current`
  ↓
Scheme state `${Paths.state}/scheme.json` is loaded
  ↓
Palette/transparency bindings update; Hypr blur/ignore-alpha rules are batched
```

**VERIFIED:** `Wallpapers.qml` falls back to `assets/wallpaper.webp` when the path file is missing/empty and invokes the CLI to install that fallback. **UNKNOWN:** exact CLI state-writing implementation is external.

### D. Hyprland event and command flow

```text
Hyprland event socket (.socket2.sock)
  ↓
plugin/src/Caelestia/Services/hyprextras.cpp:readEvent()
  ↓
HyprExtras::handleEvent() refreshes options/devices for relevant events
  ↓
services/Hypr.qml Connections.onRawEvent()
  ↓
Hyprland.refreshWorkspaces/Monitors/Toplevels or `configReloaded`
  ↓
ShellState, bar, workspace UI, fullscreen logic re-evaluate
```

Commands take the reverse path: QML `Hypr.dispatch()` calls Quickshell `Hyprland.dispatch`; `HyprExtras.message/batchMessage/applyOptions()` sends commands through `.socket.sock`. `HyprExtras` supports both legacy keyword commands and Lua-generated commands based on `usingLua`.

Failure behavior: missing `$HYPRLAND_INSTANCE_SIGNATURE` or socket directory logs a warning and leaves requests unavailable. Socket errors log warnings; callers generally receive no thrown exception and may retain stale state.

### E. Weather HTTP flow

1. `ServiceLoader` calls `Weather.reload()`.
2. If `GlobalConfig.services.weatherLocation` is configured as coordinates, `fetchCityFromCoords()` calls Nominatim for a display city. If it is a city name, `fetchCoordsFromCity()` calls Open-Meteo geocoding. If unset, `reload()` calls `Requests.get()` to `ip-api.com` for approximate location.
3. Once `loc` is available, `fetchWeatherData()` calls Open-Meteo and maps JSON into `cc`, `forecast`, and `hourlyForecast`.
4. UI reads formatted properties such as `temp`, `feelsLike`, `sunrise`, and `sunset`.
5. `FileView` stores/loads the city cache under the service state path.

Failure behavior: JSON parse errors and invalid responses log warnings; IP API rate limits set a block timer; geocoding/weather errors leave prior/empty data and use “Unknown city”/“No weather” presentation. Requests itself returns success body/metadata or an error callback; it does not retry.

### F. Lock and PAM flow

```text
Shortcut/IPC/login1 Lock signal
  ↓
Lock.qml: WlSessionLock.locked = true
  ↓
LockSurface + Pam.qml
  ↓
PamContext / ManualPamContext using assets/pam.d/{passwd,fprint,howdy}
  ↓
PAM result
  ├─ Success → WlSessionLock.unlock()
  ├─ Failed/Error/MaxTries → state/message/flash timer
  └─ Wake signal + configured Howdy → optional biometric attempt
```

**VERIFIED:** password input is buffered in QML; fingerprint/howdy availability is checked using external commands (`fprintd-list`, `command -v howdy`); max tries and enable flags are config properties. PAM result handling is explicit in `modules/lock/Pam.qml`.

### G. Screenshot area picker

1. `AreaPicker.qml` receives shortcut or IPC and activates a per-screen overlay.
2. `Picker.qml` determines the selected rectangle, optionally freezes/captures the screen, and calls `CUtils.saveItem()`.
3. `CUtils::saveItem()` asynchronously grabs the QQuick item, scales the rectangle by device-pixel ratio, writes the image on a QtConcurrent thread, and invokes success/failure JS callback.
4. Success either starts `swappy -f <path>` or pipes the PNG to `wl-copy --type image/png` and sends `notify-send`.
5. The picker closes through an animation and deactivates its lazy loader.

Failure behavior: invalid target/window/non-local path or grab/write failure logs a C++ warning and invokes `onFailed` when supplied; the QML `Picker.save()` only supplies a success callback, so some failures result in no user-visible completion.

## 8. Function-level map

| File:function | Purpose / callers | Inputs → outputs | State/side effects | Failure behavior |
|---|---|---|---|---|
| `shell.qml:ShellRoot` | Quickshell root; instantiated by loader | Environment/config → root object tree | Creates all top-level objects | QML/runtime errors are handled by Quickshell; no local catch. |
| `modules/ServiceLoader.qml:Component.onCompleted` | Eagerly loads key services | None | Instantiates singletons; calls `Weather.reload()` | Weather handles request errors internally. |
| `services/ShellState.qml:forActive()` | Finds state for Hyprland focused monitor | `ShellScreen` implicit | Reads `Hypr.focusedMonitor`, returns `ScreenState` | Returns `null` if no matching screen; callers usually assume active screen. |
| `services/Hypr.qml:cycleSpecialWorkspace()` | Selects next/previous occupied special workspace | direction | Dispatches workspace focus command | No-op if no occupied specials. |
| `services/Hypr.qml:reloadDynamicConfs()` | Reinstalls Caps/Num lock global bindings | None | Sends batched Hyprland command via `HyprExtras` | Native socket logs failures; no thrown error. |
| `services/Wallpapers.qml:setWallpaper()` | Requests wallpaper change | path | Optimistically updates `actualCurrent`; spawns CLI | CLI failure is not synchronously surfaced. |
| `services/Weather.qml:reload()` | Chooses configured/IP location path | config values | Starts geocoding/IP requests and timers | Invalid/rate-limited requests are logged/blocked. |
| `services/Colours.qml:load()` | Parses scheme JSON into palette objects | JSON string, preview flag | Mutates palette properties and scheme metadata | `JSON.parse` is not wrapped in this function; malformed scheme data can raise a QML exception. |
| `modules/Shortcuts.qml:IpcHandler.toggle()` | External drawer IPC | drawer name | Mutates active `ScreenState` boolean | Warns for unknown drawer; ignores restricted fullscreen cases. |
| `modules/launcher/Content.qml:onAccepted` | Routes launcher selection | selected item/search text | Mutates launcher visibility, invokes wallpaper/app/action | Empty selection is ignored. |
| `plugin/src/Caelestia/requests.cpp:Requests::get()` | Shared HTTP GET bridge | URL, JS callbacks, optional headers | QNetworkAccessManager request | Warns if success callback non-callable; error callback optional; no retry/timeout visible. |
| `plugin/src/Caelestia/Settings/rootnode.cpp:RootNode::load/saveToFile` | Connects tree to debounced settings file | JSON path/tree | Loads/writes config and emits tree events | `detail::loadFailed/saveFailed` show toasts for relevant config kinds. |
| `plugin/src/Caelestia/Settings/settingsfile.cpp:SettingsFile::save()` | Atomic JSON persistence | pending JSON | Creates parent dir; writes `QSaveFile`; reinstalls watcher | Emits `writeFailed` on mkdir/open/commit failure. |
| `plugin/src/Caelestia/Services/hyprextras.cpp:makeRequest()` | Native Hyprland IPC request | command string/callback | Connects local socket, writes, reads response, closes | Logs socket error and invokes callback(false, {}). |
| `plugin/src/Caelestia/Services/sessionmanager.cpp:exec()` | Maps configured session command to login1 method | command list | Calls logout/suspend/hibernate/poweroff/reboot | Returns false for unsupported command; hibernate falls back to suspend or toasts unavailable. |
| `plugin/src/Caelestia/Models/appdb.cpp:incrementFrequency()` | Ranking signal for launcher apps | app ID | SQLite upsert and in-memory sort update | Logs if app ID is absent; SQL errors are not surfaced to QML. |
| `plugin/src/Caelestia/cutils.cpp:CUtils::saveItem()` | Async visual capture/file write | target, local URL/rect, callbacks | Grab-to-image, device-scale crop, QtConcurrent file save | Logs and returns for invalid target/path/window/grab; callback on save result. |

## 9. Call graph

### Shell initialization

```text
Quickshell
  └─ shell.qml:ShellRoot
     ├─ modules/ServiceLoader.qml:Component.onCompleted
     │  ├─ Weather.reload()
     │  └─ instantiate IdleInhibitor/GameMode/Notifs/Players/Brightness/(VPN)
     ├─ modules/drawers/Drawers.qml
     │  └─ modules/drawers/ContentWindow.qml (one per Screens.screens)
     │     └─ modules/drawers/Panels.qml
     │        ├─ Bar.Wrapper
     │        ├─ Dashboard.Wrapper
     │        ├─ Launcher.Wrapper
     │        ├─ Notifications.Wrapper
     │        ├─ OSD.Wrapper
     │        ├─ Session.Wrapper
     │        ├─ Sidebar.Wrapper
     │        ├─ Utilities.Wrapper
     │        └─ Popouts/Toasts
     ├─ modules/areapicker/AreaPicker.qml
     ├─ modules/lock/Lock.qml
     ├─ modules/Shortcuts.qml
     ├─ modules/BatteryMonitor.qml
     └─ modules/IdleMonitors.qml
```

### Drawer toggle

```text
modules/Shortcuts.qml:IpcHandler.toggle()
  → services/ShellState.qml:forActive()
  → ScreenState.<drawer> = !ScreenState.<drawer>
  → modules/drawers/ContentWindow.qml / Panels.qml bindings
  → feature Wrapper/Content.qml
```

### Wallpaper selection

```text
modules/launcher/Content.qml:onAccepted
  → services/Wallpapers.qml:setWallpaper()
  → Quickshell.execDetached(["caelestia", "wallpaper", "-f", path])
  → external CLI/state file
  → Wallpapers.FileView.onFileChanged()
  → services/Colours.qml:ImageAnalyser + scheme FileView
  → Hypr.extras.batchMessage() for layer rules
```

### Hyprland event refresh

```text
Hyprland .socket2.sock
  → HyprExtras::readEvent()
  → HyprExtras::handleEvent()
  → services/Hypr.qml:Connections.onRawEvent()
  → Hyprland.refresh*()
  → ScreenState/Bar/Workspace/Fullscreen bindings
```

### Lock/unlock

```text
Lock shortcut or login1 signal
  → modules/lock/Lock.qml:lock.locked = true
  → modules/lock/Pam.qml:handleKey()/PamContext
  → PAM result
  → WlSessionLock.unlock()
```

## 10. Data flow

### Configuration

```text
~/.config/caelestia/shell.json
        ↓ QFileSystemWatcher + SettingsFile
Caelestia.Settings RootNode
        ↓ ConfigSingleton / GlobalConfig
Config attached property and feature config objects
        ↓ QML bindings in modules/services
UI behavior and external command parameters
```

`plugin/src/Caelestia/Config/common.cpp` resolves the base directory as `QStandardPaths::GenericConfigLocation + "/caelestia"`; `rootnodes.cpp` uses `shell.json` and `shell-tokens.json`, with per-monitor overlays under `monitors/<screen>/`.

`SettingsFile` debounces loads (50 ms), retries parse errors up to a bounded number visible in `settingsfile.cpp`, debounces writes (500 ms), and writes atomically with `QSaveFile`. Load/save failures are converted to config toasts by `rootnodes.cpp`.

### User/media data

```text
Paths.qml / config.paths
  ├─ wallpaper directory → FileSystemModel → WallpaperList → Wallpapers.setWallpaper
  ├─ state/wallpaper/path.txt → FileView → current wallpaper
  ├─ state/scheme.json → FileView → Colours.load
  ├─ ~/.face → file dialog / CUtils.copyFile → dashboard profile image
  └─ lyrics directory → Lyrics service cache/local files
```

### Audio/media

```text
PipeWire/MPRIS
  ↓
Quickshell Pipewire + Mpris models / C++ audio providers
  ↓
services/Audio.qml / Players.qml / Lyrics.qml
  ↓
bar popouts, dashboard media, OSD, visualiser
```

### Network/HTTP

```text
QML service (Weather/VPN/UI) or C++ Lyrics
  ↓
Caelestia::Requests (QNetworkAccessManager) or direct QNetworkAccessManager
  ↓
HTTP(S) provider
  ↓
body + status/header metadata
  ↓
JSON/parser/cache/state properties
  ↓
weather/lyrics UI
```

## 11. Business logic

The repository’s domain is desktop interaction and presentation rather than transactional business. The main rules are:

| Rule | Location | Conditions/outcome |
|---|---|---|
| Only enabled monitors receive shell windows | `services/Screens.qml:screens` | Filters `Quickshell.screens` through `GlobalConfig.forScreen(name).enabled`. |
| Drawer opens are blocked in fullscreen for selected drawers | `modules/Shortcuts.qml`, `ContentWindow.qml` | `hasFullscreen` prevents toggles and closes relevant panels. |
| Per-monitor config overrides global config | `Caelestia.Config` layer registry + attached `Config.screen` | Missing overlay values fall back to global root; some options are declared global-only in README/config schema. |
| Volume/brightness are clamped | `services/Audio.qml`, `services/Brightness.qml` | Values are bounded by config max/increment and hardware backend. |
| Special workspace cycling chooses occupied workspaces | `services/Hypr.qml:cycleSpecialWorkspace()` | Empty list no-op; remembers last special workspace when possible. |
| App launcher ranking favors favourites then frequency then locale name | `plugin/src/Caelestia/Models/appdb.cpp:getSortedApps()` | Favourite regex, descending frequency, locale-aware name. |
| Session commands use login1 when recognized | `SessionManager::exec()` | Normalizes aliases; unsupported commands return false and QML falls back to external execution. |
| Weather protects IP API rate limit | `Weather.recordIpApiRateLimit()` | 429 or `x-rl: 0` starts a retry delay timer. |
| Lock authentication has bounded attempts | `modules/lock/Pam.qml` | Password, fingerprint, and Howdy each track failures/max tries; success unlocks. |
| Screenshot crop respects device pixel ratio | `CUtils::saveItem()` | Rect is scaled before crop; write runs off the UI thread. |

## 12. Database and persistence

There is no server database schema or migration directory.

**VERIFIED:** `AppDb` creates a SQLite database connection with a UUID connection name. It starts with `:memory:` and creates `frequencies(id TEXT PRIMARY KEY, frequency INTEGER)`. `setPath()` can switch to a configured path and recreates the table. It stores launcher usage frequencies only.

**VERIFIED:** Main user configuration is JSON (`shell.json`, `shell-tokens.json`, and per-monitor overlays), managed by the native Settings tree. Writes are debounced and atomic.

**VERIFIED:** Other persistence is file-based: wallpaper path, scheme JSON, notification cache/state, lyrics cache/map, profile picture, and user-selected media paths.

**UNKNOWN:** Whether the external Caelestia CLI stores additional data outside paths visible here cannot be determined.

## 13. External systems

| System | Adapter | Requests/side effects | Error behavior |
|---|---|---|---|
| Hyprland | Quickshell `Hyprland`; native `HyprExtras` | Workspace/window/monitor reads, dispatch, local socket commands/events | Warnings on missing env/socket/errors; stale state possible. |
| Wayland compositor | `StyledWindow`, `WlrLayershell`, `WlSessionLock`, `ScreencopyView` | Layer-shell windows, focus grabs, secure lock, screenshots | Quickshell/compositor errors are outside local handling. |
| PipeWire | Quickshell `Pipewire` | Default sink/source, volume/mute, stream lists | Guarded on `ready`/audio object; no-op when unavailable. |
| MPRIS | Quickshell `Mpris` | Track/player state and controls | UI reflects available players; unavailable player yields empty/idle state. |
| login1 DBus | `SessionManager` | Lock/unlock/suspend/hibernate/poweroff/reboot | DBus errors logged; hibernate unavailable falls back/toasts. |
| PAM | `Pam.qml`, `assets/pam.d/*` | Password/fingerprint/Howdy authentication | Explicit state machine and retry limits. |
| NetworkManager | `Nmcli.qml` | `nmcli` processes, network parsing/connect/disconnect | Process callbacks update state; command-specific errors are handled in QML. |
| HTTP providers | `Requests`, `Weather`, `Lyrics` | Weather/geocoding/lyrics GETs | Callbacks, parse guards in some paths, rate-limit handling; no general retry layer. |
| External CLI | QML `Process`/`execDetached` | Wallpaper, scheme, recording, brightness, screenshot tools, notifications | Usually asynchronous; failures often only visible as process exit/logs. |
| SQLite | `AppDb` | Launcher frequency upsert/query | SQL failures return default/continue; not surfaced as domain errors. |

## 14. Async/event flow

- **Hyprland events:** native local-socket reader → QML `Connections` → targeted Quickshell model refreshes.
- **Reactive QML signals:** property changes (config, monitor, player, battery, notification, fullscreen) drive bindings and animations without explicit controller loops.
- **HTTP:** `Requests::get()` is asynchronous via `QNetworkReply::finished`; lyrics uses multiple `QNetworkAccessManager` callbacks and request IDs/pending reply tracking.
- **Timers:** settings load/save debounce, polling metrics, weather refresh/rate-limit retry, recording elapsed time, toast expiration, animation cooldowns.
- **Threaded work:** `CUtils::saveItem`, Qalculate evaluation, file model scans, and audio processing use QtConcurrent/worker threads where visible.
- **Lifecycle-managed services:** native `Service::ref/unref` starts a service on first reference and stops it when the last reference is destroyed (used by audio providers/ticking services).

**UNKNOWN:** No queue/broker or durable event log is present. Async ordering guarantees beyond the local callbacks/timers are not specified.

## 15. Configuration and runtime initialization

### Environment/runtime inputs

- `QS_CRASHREPORT_URL`, `QS_NO_RELOAD_POPUP`, `QS_DROP_EXPENSIVE_FONTS`, `QSG_RENDER_LOOP`, and `QT_QUICK_FLICKABLE_WHEEL_DECELERATION` are declared in `shell.qml` pragmas.
- `CAELESTIA_LIB_DIR` is set by the Nix wrapper for the installed extras library.
- `CAELESTIA_XKB_RULES_PATH` selects the XKB rules file; `HyprExtras` reads `HYPRLAND_INSTANCE_SIGNATURE` and `XDG_RUNTIME_DIR` to locate sockets.
- `XDG_CONFIG_HOME` is used by user-facing install/config docs; native code uses Qt `QStandardPaths::GenericConfigLocation`.
- `QT_QPA_PLATFORM=wayland` is set by the Home Manager systemd service.

### Initialization order

1. Package/wrapper starts Quickshell and points it at the installed QML config.
2. `shell.qml` constructs `ShellRoot` and enables file watching.
3. Config/token singletons load lazily/on first reference; ServiceLoader forces selected services.
4. Screens are filtered and per-monitor windows instantiated.
5. Native HyprExtras attempts socket setup and initial `descriptions`/`devices` requests.
6. Services begin polling, listening, reading files, and exposing IPC targets.

## 16. Error and failure handling

### Native settings

```text
SettingsFile open/parse/write failure
  ↓
readFailed/writeFailed signals
  ↓
RootNode callbacks
  ↓
detail::loadFailed/saveFailed
  ↓
Toaster warning/error
```

Malformed JSON is retried after debounced watcher events before a final failure path. Writes use `QSaveFile` and report parent-directory/open/commit failures.

### Native Hyprland

```text
Missing env/socket or socket error
  ↓
qCWarning logging
  ↓
callback(false, {}) for requests
  ↓
QML leaves state unchanged or refreshes only on success
```

### QML/external processes

Most `Process` instances handle standard output/exit callbacks locally. `Quickshell.execDetached` calls intentionally detach from the shell; the caller usually cannot synchronously observe exit status. This is a recurring boundary limitation for wallpapers, schemes, notifications, brightness, recording, and screenshot post-processing.

### Silent/weak failure surfaces observed

- `Weather.fetchCoordsFromCity()` and `fetchWeatherData()` parse JSON without the same broad `try/catch` used by IP/Nominatim paths; malformed provider bodies can raise a QML exception.
- `Colours.load()` calls `JSON.parse(data)` directly.
- `AppDb` SQL execution results are mostly ignored; a failed DB operation looks like zero frequency/default ordering.
- `Picker.save()` supplies a success callback to `CUtils.saveItem()` but no explicit failure callback, so an image write failure may only be logged.
- External CLI failures are often asynchronous and not converted into a common user-facing error model.

These are **observed implementation characteristics**, not claims that they are currently production defects.

## 17. Testing and CI architecture

**VERIFIED:** No `test/`, `tests/`, `spec/`, or test-named source files were found in the archive.

CI provides:

- `.github/workflows/build.yml`: Nix build and CMake builds with GCC/Clazy.
- `.github/workflows/lint.yml`: CMake build, generated QML tooling, `qmllint`, and `clang-tidy` with warnings-as-errors.
- `.github/workflows/check-format.yml`: `qmlformat`, custom `scripts/qml-lint-conventions.py`, and `clang-format` dry run.
- `.github/workflows/update-flake-inputs.yml`: headless Sway smoke test starts `caelestia-shell`, checks the process, then stops it.
- `.github/workflows/release.yml`: archives source, creates GitHub release, moves stable branch.

**INFERRED:** Verification is compile/lint/smoke-test oriented. There is no repository-level executable specification for business behavior, error cases, or service contracts.

## 18. Important files ranked

### Critical

1. `shell.qml` — real QML bootstrap and top-level object graph.
2. `modules/drawers/ContentWindow.qml` — per-monitor layer-shell window, fullscreen/focus/exclusion behavior.
3. `modules/drawers/Panels.qml` — feature composition and panel wiring.
4. `services/ShellState.qml` — per-screen state and component registry.
5. `services/Hypr.qml` — compositor state/dispatch/event adaptation.
6. `plugin/src/Caelestia/Config/rootnodes.cpp/.hpp` — config singleton and overlay initialization.
7. `plugin/src/Caelestia/Settings/settingsfile.cpp` and `rootnode.cpp` — JSON persistence/watch/debounce semantics.
8. `CMakeLists.txt`, `plugin/cmake/qml-module.cmake` — build/install/module boundaries.

### High

- `modules/ServiceLoader.qml` — eager singleton initialization.
- `modules/Shortcuts.qml` — global shortcut and IPC routing.
- `services/Wallpapers.qml`, `Colours.qml`, `Weather.qml`, `Audio.qml`, `Players.qml`, `Notifs.qml`, `Nmcli.qml`, `VPN.qml` — major external/system flows.
- `modules/lock/Pam.qml`, `modules/areapicker/Picker.qml`, `modules/session/Content.qml` — security/system-action flows.
- `plugin/src/Caelestia/Services/hyprextras.cpp`, `sessionmanager.cpp`, `requests.cpp`, `cutils.cpp` — native boundaries.
- `plugin/src/Caelestia/Models/appdb.cpp` — launcher ranking persistence.
- `nix/default.nix`, `nix/hm-module.nix` — production packaging/service startup.

### Medium

- `components/controls/*`, `components/containers/*`, `components/filedialog/*` — shared UI primitives.
- `modules/nexus/*` — settings/control-center pages.
- `plugin/src/Caelestia/Services/{cpu,gpu,memory,storage,networkusage,lyrics}.*` — native service implementations.
- `README.md` — user-facing install/config semantics; use implementation when it conflicts.

### Low (for first pass)

- Individual icon/text wrappers, decorative shapes, image effects, and static assets.
- Release/issue-template workflows unless changing project governance or release packaging.

## 19. Recommended contributor reading order

1. `README.md` sections Usage, Configuring, and dependencies to understand user-facing expectations.
2. `shell.qml` to see the actual bootstrap.
3. `modules/ServiceLoader.qml`, `services/Screens.qml`, and `services/ShellState.qml` to understand lifecycle and per-monitor state.
4. `modules/drawers/Drawers.qml`, `ContentWindow.qml`, and `Panels.qml` to understand window/panel composition.
5. `modules/Shortcuts.qml` and one feature path you intend to change.
6. `services/Hypr.qml` and the relevant service singleton (`Audio`, `Weather`, `Players`, etc.).
7. `plugin/cmake/qml-module.cmake` and the relevant C++ module CMake file.
8. `plugin/src/Caelestia/Config/rootnodes.*`, `Settings/*` before changing config schema or persistence.
9. `nix/default.nix` and `nix/hm-module.nix` before changing installation/startup.
10. CI workflows and lint scripts before submitting changes.

### Safe/isolated areas

- Pure visual components under `components/controls` are relatively isolated when they do not import global services.
- Individual Nexus pages and status cards are usually consumers of established services.

### Critical paths to modify carefully

- `ShellState`, `Screens`, `ContentWindow`, `Panels`, `Hypr`, config/settings code, lock/PAM, and external command adapters.
- Any singleton property or signal used across `qs.services`; changes can affect many features without compiler errors.

### Hidden complexity

- Per-monitor config is layered through native attached properties rather than simple QML object inheritance.
- Fullscreen behavior spans shortcut gating, layer level, mask regions, focus grabs, and panel-closing side effects.
- Hyprland has both direct Quickshell model APIs and a custom native socket adapter; both paths must stay coherent.
- External CLI commands are part of normal behavior even though their implementations are outside the repository.
- Service objects may start/stop native workers based on reference lifetime.

## 20. Architectural observations

### Observed

- One process composes all screens/features and exposes many mutable singletons.
- QML feature code directly performs substantial business/integration work, not only rendering.
- Native modules are cleanly separated by QML URI, but broad `qs.services` imports create high fan-in.
- Configuration has a comparatively sophisticated typed schema, layered monitor overrides, file watching, retry/debounce, and atomic writes.
- CI has strong static/build gates but no behavior-level tests.
- There is deliberate compatibility logic for Hyprland Lua mode versus legacy keyword commands.

### Potential concerns

- External process calls lack a uniform result/error abstraction; contributor changes can accidentally create silent failures.
- Direct JSON parsing in several QML paths is less defensive than the shared `Requests` abstraction.
- Native SQLite and file I/O often log/continue rather than propagate structured errors.
- The repository depends on exact versions of Quickshell/Qt modules and external commands; packaging drift can break runtime despite a successful source build.
- The user-facing README documents a broader ecosystem (CLI/dotfiles) than this repository contains; treat external CLI behavior as an integration contract, not local implementation.

## 21. Unknowns and ambiguities

- The `caelestia` CLI source is not included, so exact command semantics, IPC command grammar, state-file writes, and process exit contracts are external.
- Quickshell source is not included, so exact `ShellRoot`, `IpcHandler`, `CustomShortcut`, `FileView`, `LazyLoader`, and layer-shell lifecycle semantics are framework behavior.
- Production config values, monitor names, installed commands, compositor version, DBus policy, PAM policy, and network availability are environment-specific.
- No repository tests establish expected behavior for edge cases; inferred behavior comes from implementation paths and CI smoke coverage.
- The README may describe supported dependencies/options beyond what the checked-out commit currently exposes; implementation/config schema should win when they disagree.

## 22. Master codebase map

```text
SYSTEM: caelestia-shell (one Quickshell process)
│
├── ENTRY POINTS
│   ├── external `caelestia shell -d` / `qs -c caelestia`
│   └── shell.qml:ShellRoot
│
├── APPLICATION FLOW
│   ├── ServiceLoader → singleton initialization
│   ├── Screens → per-monitor Drawers/ContentWindow
│   ├── Panels → bar/dashboard/launcher/sidebar/session/utilities/OSD/notifs
│   └── Shortcuts + IpcHandler → ScreenState mutations
│
├── CORE MODULES
│   ├── ShellState / ScreenState
│   ├── Screens
│   ├── Hypr / HyprExtras
│   ├── GlobalConfig / TokenConfig
│   └── Panels / ContentWindow
│
├── BUSINESS LOGIC
│   ├── fullscreen/focus gating
│   ├── app ranking and launcher routing
│   ├── config overlay/fallback rules
│   ├── volume/brightness/workspace/session/lock rules
│   └── weather/wallpaper/scheme state transitions
│
├── DATA FLOW
│   ├── JSON config/state → typed config/QML properties
│   ├── Hyprland/PipeWire/MPRIS/UPower → services → UI
│   ├── HTTP → JSON/cache → Weather/Lyrics UI
│   └── UI actions → commands/DBus/socket/file writes
│
├── DATABASE
│   └── optional SQLite AppDb frequencies table (no server DB)
│
├── EXTERNAL SERVICES
│   ├── Hyprland local sockets
│   ├── Wayland layer shell/session lock/screencopy
│   ├── PipeWire/MPRIS/UPower
│   ├── login1 DBus and PAM
│   ├── NetworkManager/nmcli
│   ├── weather/lyrics HTTP APIs
│   └── external caelestia/system commands
│
├── ASYNC / EVENTS
│   ├── QML bindings/signals/timers
│   ├── Hyprland event socket
│   ├── QNetworkReply callbacks
│   ├── QFileSystemWatcher/debounced settings
│   └── QtConcurrent/audio worker services
│
├── CONFIGURATION
│   ├── ~/.config/caelestia/shell.json
│   ├── shell-tokens.json
│   ├── monitors/<name> overlays
│   └── environment variables and Nix/Home Manager service
│
└── TESTS / QUALITY
    ├── CMake/Nix builds
    ├── qmllint/clang-tidy/format checks
    └── headless Sway smoke test; no application test suite
```

## Excalidraw deliverables

The companion diagrams are valid Excalidraw JSON files and are intentionally split into readable sections:

- `01-system-architecture.excalidraw`
- `02-entry-and-main-flows.excalidraw`
- `03-module-dependency-map.excalidraw`
- `04-data-and-error-flow.excalidraw`
