# Changelog

## 3.2.0

- Moves window controls to the top right, enlarges their click targets, and shows action icons on hover or keyboard focus.
- Removes the old slogan and simplifies interface copy.
- Runs overview, game-library, profile, and Windows-preference reads in a reusable background runspace. Navigation remains available while reads finish; idle polling stops automatically.
- Reuses theme resources and applies the Windows-tools palette before attaching its native surface, reducing redraws and unthemed first paint.
- Adds automatic stable-release updates, manual checks, and a Settings toggle. Downloads use the official GitHub repository and published SHA-256 checksums; installation waits for app exit.
- Preserves private state and restore data, verifies package paths and required files, and rolls back replaced files if installation fails.
- Adds updater failure/recovery tests and a dispatcher responsiveness/shutdown test. These tests do not establish FPS or latency gains.

## 3.1.1-rc1 — Framewell

- Renames the app to **Framewell**, while preserving existing Gaming Mode profiles and internal compatibility identifiers.
- Adds a simple portable download: extract the complete ZIP and open `Framewell.exe`; support files stay in the accompanying `app` folder.
- Makes the Windows download prominent and separates the ready-to-run ZIP from developer source downloads.
- Refreshes the interface previews and startup documentation for the new name.

## 3.1.0-rc1

- Integrates the Optimizer 17.0 controls into Gaming Mode through a same-process WinForms host, with 16 navigable tool sections and lazy loading/unloading.
- Adapts standalone initialization, updater, tray, startup, window ownership, themes, and disposal for the embedded host.
- Adds native CPU/process controls for upstream CLI-only functions, with planning, protected targets, original-value journals, and conflict-aware restoration.
- Brings Windows gaming preferences, per-EXE GPU preference, and confirmed refresh-rate previews into the app.
- Adds administrator restart into the selected page and an instance handoff.
- Preserves existing user profiles while excluding personal state from public packages.
- Includes corresponding modified source, GPL licensing, original component notices, and an explicit AI-development disclosure.

## 3.0.0-rc1

- Expanded game discovery and manual EXE/folder addition.
- Added per-game CPU controls, memory monitoring, timer experiments, custom network endpoints, app/settings profiles, and 33 themes.
- Introduced an Optimizer companion and searchable feature catalog, superseded by the embedded integration in 3.1.

Versions before 3.2 were release candidates. The project remains early-stage. The changelog describes implemented behavior, not measured gaming performance improvements.
