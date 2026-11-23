Framewell 3.2.0 - Windows x64

START HERE
1. Download Framewell-3.2.0-win-x64.zip.
2. Extract the entire ZIP to a writable local folder.
3. Double-click Framewell.exe. Keep the app folder beside it.

Opening the dashboard needs no installer, compilation, or terminal commands.
Framewell is the new name for Gaming Mode; your existing profiles stay compatible.
Windows 11 x64, or Windows 10 version 1903+ with .NET Framework 4.8+ and Windows
PowerShell 5.1 available, is required. Those runtimes come with standard installs.
Some optional features need their own driver or tool. Privileged actions request
Windows administrator approval only when selected. This release is unsigned.

OVERVIEW
Widgets show process count, RAM, refresh rate, available/standby memory and the
last latency result. Quick actions open games, profiles, network and memory tools.
Refresh is on demand. No permanent service or game-watching loop is installed.
Framewell saves a journal before closing selected apps or applying session
settings. Steam, Discord, active games, Windows/security, drivers and remote access
are protected by built-in rules. Restore uses the journal and preserves identifiable
later manual changes. Unsaved work may keep gracefully closed apps open.

GAMES
Discover Steam, Epic, GOG, EA, Ubisoft, Xbox and bounded local folder candidates.
Add EXE handles a manually chosen game; Scan folder adds a custom directory.
Portable/emulator/launcher candidates can appear separately. Reparse points,
system/media/tool folders and recognizable helper EXEs are excluded. Use Add EXE
for arbitrarily named or deeply nested games the bounded scanner cannot recognize.
Bind the actual game process for NVIDIA, CPU, connection and FPS tools. Store or
launcher actions remain separate from that rendering executable.

NVIDIA: Performance, Quality, custom driver controls and Restore affect one game.
Shared/global/packaged associations are blocked to avoid changing other games.
Only driver-supported controls are enabled. These presets do not set game
resolution, DLSS, ray tracing or Reflex. Preferences persist until GPU Restore;
Gaming-session Restore is separate. Performance favors filtering shortcuts
and VSync off; Quality favors filtering and VSync on. Both can raise power use,
and neither guarantees the best result for every engine, display or frame target.

CPU: choose priority and logical processors for the bound game. Empty core
selection means all. Apply verifies EXE/PID/creation time and records a restore
snapshot. Optional apply-on-launch waits at most 15 seconds, with no permanent
watcher. Slow-starting games can use Apply once running. Realtime is excluded;
multi-group CPUs do not support core selection here. Access denial is reported,
not bypassed. Core restrictions or higher priority can reduce performance.
FPS capture uses a supported installed PresentMon; no capture binary is bundled.
It measures rendering, not physical input latency or guaranteed displayed frames.

NETWORK
Choose an installed game and saved/verified endpoint, or type a hostname/IP and
TCP port. ICMP measures echo RTT; TCP measures connection-handshake time. Neither
is the game's own UDP/protocol latency counter. Probe timeouts may reflect blocked
traffic, not gameplay packet loss. Provider reference targets are labeled separately.
Known game endpoints have source links. Missing servers are not fabricated.
Inspect running-game TCP connections for candidates; these may be login, CDN or
telemetry rather than gameplay. Save named servers and test settings for reuse.
Comparisons require matching target, protocol, port and adapter. No DNS/network
settings are changed by tests. These latency tests are not bandwidth speed tests.

MEMORY TOOLS
View physical/available RAM, standby cache and timer readings. Standby is already
reusable RAM. Manual standby purge and an opt-in threshold monitor use a fixed
Windows native operation; no process working-set emptying or pagefile changes.
The monitor checks every 15-600 seconds and purges only when BOTH standby is above
and available RAM is below the configured thresholds. It stops with the dashboard;
an elevated helper is tied to its original parent process. Unsupported native
operations are reported. Clearing cache can slow subsequent file reads.
Timer experiments accept 0.5-16 ms in half-millisecond steps. Integer values use
paired timeBeginPeriod/timeEndPeriod; fractional values use an explicitly labeled
experimental native request, bounded by Windows' reported limits and released on
stop/exit. Requested, effective and observed values can differ. Modern Windows does
not guarantee an effect on another game, and Windows 11 may ignore an occluded app.
Readings can reflect other programs. Closing the app releases this app's request.
No FPS or latency improvement is promised. Sources: SystemToolsReferences.txt.

PROFILES
App collections include Media stack and Super Performance. Select individual
known apps or add custom local application EXEs. The catalog covers 36 apps.
Editors, browsers, cloud clients and recorders can show their normal quit/save
prompts. New users receive an unconfigured Media stack. Existing private media
integrations remain local and never enter the public archive.
Settings profiles capture All, Overview, Performance, Games, Network, Profiles,
Appearance, Memory, Tools or Settings. Applying loads saved choices only: it does
not close apps, change CPU/GPU settings, enable monitoring or change startup.
Imports are validated and receive a new profile ID. Exports can contain local game
and app paths and server addresses, but exclude private media configuration, keys,
runtime worker files and restore journals. Hardware GPU state and embedded
Optimizer changes are not included in portable settings profiles.

SETTINGS AND THEMES
33 original palettes include Dark, Light, OLED, Midnight, every main JoJo, Dio/DIO,
Kars, Kira, Diavolo, Pucci, Funny Valentine, Tooru, Diego and additional allies.
Only colors and names are included; there is no character art or game content.
Startup opens the dashboard without activating Gaming Mode. Close-after-activation
exits the dashboard by default. If an opt-in memory feature is active, it minimizes
instead to keep that requested feature alive. Closing always stops memory tools.

EMBEDDED WINDOWS TOOLS
The Tools catalog opens Windows tools directly inside Framewell. The modified
Optimizer 17.0 library provides 16 embedded sections, including native controls
for the upstream CLI-only CPU/process functions. No standalone Optimizer window
is launched. Administrator activation is explicit; loading applies no tweaks.
The upstream automatic updater/feed/tray lifecycle is disabled. Persistent tools
have their own restore semantics, separate from gaming-session Restore. Two stale
upstream template entries are marked unavailable. Compatibility depends on OS.
Full modified source, GPL license and original notices accompany the release.
See README.md, AI_TRANSPARENCY.md and THIRD-PARTY-NOTICES.txt.

DISTRIBUTION
Portable profiles live in app/state. Framewell installs no telemetry,
account service or automatic updater. Embedded tools contact services only for selected internet features.
Public runtime/source archives exclude personal state, snapshots, credentials,
logs, backups and development fixtures. This is an unsigned release candidate;
see PUBLICATION.txt for validation limits and steps toward a broad stable release.


UPDATES
Automatic stable-release checks are enabled by default in Settings. Verified
updates install when Framewell closes, preserving local profiles and settings.
See docs/UPDATES.md for verification, manual updates and recovery.
