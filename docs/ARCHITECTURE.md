# Architecture

## Desktop host

`PortableLauncher.cs` produces the public `Framewell.exe` entry point. It starts the included host at `app/GamingMode.exe` and exits, so it does not leave an extra background process running. The public ZIP can be extracted and opened without an installer or terminal commands.

`Launcher.cs` builds that x64 .NET Framework host. It runs Windows PowerShell in-process and opens the WPF interface in `MacInterface.ps1`. The dashboard does not need a browser, Electron runtime, or always-running Windows service.

The internal `GamingMode.exe`, module names, type names, and state formats retain their historical identifiers for compatibility. The app's public name and window title are Framewell; Gaming Mode remains the name of its optional gaming-session feature.

Feature modules handle game discovery, session/app profiles, process tuning, NVIDIA driver profiles, network diagnostics, memory tools, and Windows preferences. Native C# API declarations are compiled into the host to avoid compiling them at every launch.

## Embedded Windows tools

`EmbeddedOptimizer.ps1` loads `vendor/optimizer/GamingMode.Optimizer.dll` and its Newtonsoft.Json dependency when requested. `Optimizer.EmbeddedHost` creates the modified WinForms view, and WPF's `WindowsFormsHost` displays it inside the main window. The embedded view runs in Framewell's host process; no standalone Optimizer EXE is launched.

The fork removes standalone startup assumptions, suppresses the upstream automatic updater/feed and tray lifecycle, defers expensive scans, scopes preferences to this installation, and provides navigation, theme, dialog ownership, and disposal hooks. System-changing controls require explicit administrator activation. Embedded operations keep their own restore semantics; the gaming-session journal does not undo every Windows tool.

The additional CPU/process panel exposes the relevant upstream CLI features through fixed native controls. It validates process names, protects essential targets, records prior registry values, and preserves later conflicting edits during restoration.

## Explicit helpers

Some operations require a short-lived worker or Windows utility. These are implementation details of in-app controls, not separate replacement dashboards. The optional memory worker is tied to its originating process. The display worker previews an enumerated primary-display refresh mode and restores it if the user does not confirm within 15 seconds or the originating app closes.

NVIDIA controls use the installed driver's NVAPI. NVIDIA Control Panel can be opened as an external vendor interface. FPS capture requires a supported PresentMon installation; its output is consumed by the app and no PresentMon binary is bundled.

## State and packaging

The portable layout is:

```text
Framewell.exe
START HERE.txt
app/
  GamingMode.exe
  GamingMode.ps1
  vendor/
  docs/
  state/           created locally when needed
```

Portable state lives in `app/state`, beside the host and its support files. It includes personal profiles, paths, optional media configuration, and restore journals. A legacy flat Gaming Mode installation continues to use `state` beside its existing host. The rename does not change profile formats.

To move old profiles into a newly extracted portable copy, close both copies first, back up the old `state` folder, then copy its contents into the new copy's `app/state` folder. Keep the original until the new copy loads the expected profiles. Do not merge or move a live restore journal between running copies or share personal state publicly.

For subsequent portable updates, close Framewell and extract the complete new ZIP over the same folder. The release does not contain a `state` directory, so the existing `app/state` remains separate from distributed files. Back up that directory before replacing or removing an installation.

`runtime-files.json` is the support-file packaging allowlist. The release builder separately includes documentation, source, tests, and licenses; it excludes personal state and backups. `Framewell.exe` and the start guide sit above the support folder in the portable release.

`Build-EmbeddedOptimizer.ps1` compiles the modified upstream source using a SHA-256-pinned compiler package. `Build-Launcher.ps1` builds the host and invokes `Build-PortableLauncher.ps1` for the public entry point. `Build-Release.ps1` generates portable runtime/source ZIPs and checksums. The portable package includes modified corresponding source at `app/vendor/optimizer/embedded-source.zip`; the source distribution includes the complete editable tree and build scripts.

