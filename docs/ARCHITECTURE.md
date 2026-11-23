# Architecture

## Desktop host

`Launcher.cs` produces a small x64 .NET Framework executable. It hosts Windows PowerShell in-process and opens the WPF interface in `MacInterface.ps1`. The dashboard does not need a browser, Electron runtime, or always-running Windows service.

Feature modules handle game discovery, session/app profiles, process tuning, NVIDIA driver profiles, network diagnostics, memory tools, and Windows preferences. Native C# API declarations are compiled into the launcher to avoid compiling them at every launch.

## Embedded Windows tools

`EmbeddedOptimizer.ps1` loads `vendor/optimizer/GamingMode.Optimizer.dll` and its Newtonsoft.Json dependency when requested. `Optimizer.EmbeddedHost` creates the modified WinForms view, and WPF's `WindowsFormsHost` displays it inside the main window. The embedded view is in the Gaming Mode process; no standalone Optimizer EXE is launched.

The fork removes standalone startup assumptions, suppresses the upstream automatic updater/feed and tray lifecycle, defers expensive scans, scopes preferences to this installation, and provides navigation, theme, dialog ownership, and disposal hooks. System-changing controls require explicit administrator activation. Embedded operations keep their own restore semantics; the gaming-session journal does not undo every Windows tool.

The additional CPU/process panel exposes the relevant upstream CLI features through fixed native controls. It validates process names, protects essential targets, records prior registry values, and preserves later conflicting edits during restoration.

## Explicit helpers

Some operations require a short-lived worker or Windows utility. These are implementation details of in-app controls, not separate replacement dashboards. The optional memory worker is tied to its originating process. The display worker previews an enumerated primary-display refresh mode and restores it if the user does not confirm within 15 seconds or the originating app closes.

NVIDIA controls use the installed driver's NVAPI. NVIDIA Control Panel can be opened as an external vendor interface. FPS capture requires a supported PresentMon installation; its output is consumed by the app and no PresentMon binary is bundled.

## State and packaging

Local state lives in `state` beside the executable. It includes personal profiles, paths, optional media configuration, and restore journals. `runtime-files.json` is the runtime packaging allowlist. The release builder separately includes documentation, source, tests, and licenses; it excludes development state and backups.

`Build-EmbeddedOptimizer.ps1` compiles the modified upstream source using a SHA-256-pinned compiler package. `Build-Launcher.ps1` builds the host. `Build-Release.ps1` generates portable runtime/source ZIPs and checksums. The runtime includes the modified corresponding source archive and the source distribution includes the complete editable tree.
