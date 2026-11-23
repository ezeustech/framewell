# Windows tools inside Gaming Mode

Gaming Mode embeds a source adaptation of Optimizer 17.0 in its Windows tools
workspace. `GamingMode.Optimizer.dll` is loaded into the existing app process and
hosted as a native child control. A separate Optimizer window or process is not
used. The complete modified source, GPL license, dependency MIT license, pinned
build inputs, and provenance are included here.

See [embedding and build details](embedded-source/EMBEDDING.md) and
[provenance.json](provenance.json). The main app is the entry point; it owns
startup, updates, themes, elevation, and window lifetime. The component applies
no Windows tweak when opened. Windows-changing controls require an elevated
host; each tool keeps its own confirmation and restore behavior. These changes
are not implicitly part of Gaming Mode's temporary gaming-session restore.

The searchable catalog contains 129 historical entries. Two retired entries
(smaller legacy taskbar and classic Explorer ribbon) are marked unavailable;
their implementations were removed by upstream. Windows-version-specific
controls remain subject to upstream compatibility rules.

Source and support references may open a browser. Tool actions, IP lookup,
network-adapter details, and cleanup controls operate inside Gaming Mode.
