# Validation approach

The release candidate uses isolated tests for state transitions, profile validation, API planning, UI handlers, packaging, and restoration behavior. Mutating operations are tested through mocks/fakes wherever practical. Native read-only checks inspect the actual Windows environment without applying optimization settings.

For the 3.1 embedded integration, tests verify:

- All 16 Windows-tool sections expose actual controls inside a WPF/WinForms host.
- The hosted native window belongs to the same process; no standalone Optimizer process is launched.
- Construction avoids automatic tweak application and keeps the standalone updater/tray/autostart disabled.
- Native controls unload, reopen, and dispose with the host.
- Page/theme layouts render across the 33 themes, and new UI handlers call the expected interfaces through mocks.
- Advanced CPU/process plans validate targets and restoration conflicts without changing the test machine.
- Clean installation uses default profiles and excludes private development state; extracted source can build and package the app.

Relevant entry points include `Test-EmbeddedOptimizer.ps1`, `Test-V3-Publication.ps1`, other `Test-*.ps1` scripts, and isolated `test-results/*tests.ps1` sources. Generated results and machine-specific fixtures are not part of public source releases.

The test suite does not establish correctness of every upstream operation. Live administrator changes, display transitions, every driver write, every app shutdown/relaunch, and every Windows build have not all been exercised. Tests developed with AI assistance are disclosed in [AI_TRANSPARENCY.md](../AI_TRANSPARENCY.md).
