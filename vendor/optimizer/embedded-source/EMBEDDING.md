# Embedded Optimizer source

This directory contains Gaming Mode's GPL-3.0 adaptation of upstream
[`hellzerg/optimizer` tag 17.0](https://github.com/hellzerg/optimizer/tree/17.0).
Upstream copyright and license notices are retained. Gaming Mode is not endorsed
by the upstream project. The integration code was developed with AI assistance
and checked through compilation, read-only UI tests, and source review.

## Build

From a Windows PowerShell 5.1 terminal on Windows with .NET Framework 4.8:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GamingMode\Build-EmbeddedOptimizer.ps1
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\GamingMode\Test-EmbeddedOptimizer.ps1
```

The build uses the complete source in `optimizer-17.0/Optimizer`, its embedded
resources, and its included Newtonsoft.Json dependency. It obtains Microsoft's
Roslyn compiler 4.8.0 from NuGet, verifies the pinned SHA-256 before use, and
caches it under the build user's temporary directory. No Optimizer executable is
launched or required. The output is `GamingMode.Optimizer.dll` and
`Newtonsoft.Json.dll`, placed in `GamingMode/vendor/optimizer` by default.

## Host contract

Load both assemblies on the WPF UI STA thread. Set `EmbeddedHost.SetOwnerWindow`
with the host window's HWND. Assign the result of
`Optimizer.EmbeddedHost.CreateView(absoluteStateDirectory, enableActions)` to a
`WindowsFormsHost.Child`. The window must not use WPF `AllowsTransparency`.
The returned borderless child control has no separate process or message loop.

`GetSections()` provides metadata without initializing the tools.
`GetSections(view)` lists sections available for the running Windows version.
`SelectSection(view, id)` changes the child workspace. `ApplyTheme` accepts an
accent/light-mode pair or additionally background, surface, and text colors for
OLED and character themes. Call `DisposeView(view)` before releasing the host.
Only one view may exist at a time; the state directory is fixed for the process.

Windows actions are disabled unless the current host is elevated and explicitly
passes `enableActions=true`. The component never requests elevation itself.
The host can offer an explicit restart as administrator.

## Integration behavior

All original Windows-tool sections and their action handlers are retained.
`EmbeddedTemplatePanel.cs` adds native controls for CPU-core metadata, svchost
splitting, and process blocking/unblocking that upstream exposes through its
automation template. Those extra actions preview exact changes, require an
explicit confirmation, and maintain a conflict-aware restore record.

Opening the workspace extracts bundled resource files and saves tool preferences
only inside the supplied private state directory. It does not apply tweaks.
Startup feed downloads and upstream binary updates are disabled. The app catalog
uses its bundled feed; its Refresh action can retrieve an updated feed. Hardware,
cleaner, and UWP enumeration are deferred until their section is selected.
Process-global culture, TLS policy, DPI, and system-color overrides are not
changed. Hosts-file attribute reads do not write the file. Native dialogs use
the host HWND. Child resource disposal also releases timers and file observers.

App startup, tray lifetime, and app updates belong to Gaming Mode's settings;
the standalone Optimizer controls for these are disabled or explain the host
equivalent. Upstream reset/restart routines cannot restart or replace the host
binary. Explicit Windows restart actions still require confirmation.

Network adapter details and Shodan IP results use native owned dialogs. The
Shodan viewer queries [InternetDB](https://internetdb.shodan.io/) only after the
user chooses the lookup. Its metadata is a weekly snapshot, is narrower than a
full authenticated Shodan search, and is free for non-commercial use; Shodan
requires a commercial license for commercial use. Source, support, and license
links remain ordinary browser references. The cleanup shortcut refreshes the
embedded cleaner preview instead of launching Windows Disk Cleanup.

The 129-entry catalog preserves two retired upstream template names:
`TaskbarSmaller` and `ClassicRibbon`. Optimizer 17.0 comments out both
implementations. Their catalog rows are explicitly unavailable and have no
Apply action. Other Windows-version visibility rules remain intact, including
upstream's hidden legacy Defender control on Windows 10/11. The catalog does not
promise an unsupported Windows tweak just because its old name still exists.

Tests deliberately do not execute registry tweaks, delete files, uninstall apps,
change network configuration, or reboot Windows. Tool behavior still depends on
Windows edition, permissions, and hardware; a successful UI test is not a claim
that every Windows-changing action was exercised on a live system.
