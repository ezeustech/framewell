# Behavior and limitations

## Performance

Process count alone is not a performance measurement. Essential Windows, security, driver, remote-access, Steam, Discord, and active-game processes are protected. Apps may keep save prompts open or refuse to close. Reducing background work can help when it removes actual contention; the app does not promise the lowest possible process count on every PC.

CPU priority, affinity, cache purging, timer resolution, GPU scheduling, and NVIDIA presets are configurable experiments. They can improve, worsen, or leave a game unchanged. Realtime CPU priority is excluded; affinity selection is unavailable on multiple processor groups. OS policy and app visibility can affect timer requests. A standby cache is already reusable memory.

## Networking and capture

ICMP echo and TCP handshake tests measure different operations. A timeout is not necessarily gameplay packet loss. A process's observed TCP endpoint can be a login service, CDN, or telemetry endpoint. Not every installed game has a published reliable test server, and the app does not fabricate missing endpoints. These tests do not measure bandwidth.

PresentMon support depends on an installed compatible binary. Rendering measurements are not physical input-latency measurements. NVIDIA presets affect supported driver settings in eligible individual EXE profiles, not all in-game graphics.

## Restore and profiles

Session Restore, NVIDIA Restore, Windows preference Restore, and individual upstream tool undo operations are separate. Destructive cleanup and uninstall actions may have no undo. Imported settings profiles load selections; they do not automatically execute system changes. Some saved profiles can contain local EXE paths or server names; review exports before sharing them.

## Windows tools

The embedded Optimizer controls retain upstream OS-specific behavior. Available actions vary by Windows edition/version, privileges, installed apps, and hardware. They are not all automatically reversible. The app disables the standalone upstream updater/tray lifecycle; the combined release is updated as a unit.

The built-in refresh picker currently targets the primary display at its current resolution and color depth. It previews only modes Windows enumerates and requires confirmation. GPU-scheduling controls save a preference; effective support depends on the installed GPU/driver and a Windows restart.

## Distribution

3.1.0-rc1 is unsigned and has been checked on one Windows 11 PC. Windows 10, high-DPI layouts, non-NVIDIA systems, CPUs with more than 64 logical processors, administrator transitions, and anti-cheat interactions need broader real-world validation. Source and isolated test results provide evidence, not an independent audit or certification.
