# Updates

Framewell 3.2 checks the latest stable release in `ezeustech/framewell` when the dashboard opens. Automatic updates are on by default and can be disabled in Settings. Manual checking and downloading remain available. Prereleases and drafts are not installed automatically.

The app downloads the Windows ZIP, verifies its published SHA-256 digest, validates its manifest and paths, and stages it under `%LOCALAPPDATA%\Framewell\Updates`. A small helper waits for the original process to exit before replacing application files. Framewell does not force a restart or install a permanent service. Open the app again to use the new version.

Only application files are replaced. The updater rejects package entries targeting `state` or `backups`, so app profiles, preferences, media configuration, and restore journals remain local. Both the portable `app` layout and older flat installations are supported. Updates are designed for a writable local folder; protected or linked installation paths may require a manual update.

The updater contacts GitHub's release API and download infrastructure. It sends a Framewell version user-agent, not personal profiles or system inventories. Network failures leave the installed version in place. Disabling automatic updates prevents an automatically staged update from being installed when the app closes; an in-flight download may finish staging locally.

## Verification and recovery

The download digest comes from GitHub release metadata or the release's `SHA256SUMS.txt`. HTTPS and those hashes detect corrupted or mismatched downloads; the binaries are not Authenticode-signed, and this does not protect against a compromised maintainer account or GitHub release.

Before copying, the helper verifies the archive again and extracts fresh files. It saves replacement backups under a `rollback-*` folder beside the staged plan. If a copy fails, it attempts to restore all files it already replaced. A failed rollback is reported with the recovery folder path instead of claiming success. `update-error.txt` records helper errors and `installed.txt` records a completed version.

If an update fails, close all copies of Framewell and retry, or extract the complete official ZIP over the same installation. Keep `app/state` (or `state` for older flat installations) and your backups. Staged downloads and rollback copies remain in the Updates folder for recovery and can be removed once the new version works.

## Testing

`Test-Updater.ps1` uses isolated temporary installations to test path rejection, archive validation, checksums, portable and flat upgrades, state preservation, changed staging files, locked files, and rollback. `Test-ResponsiveUI.ps1` checks that background reads leave the dispatcher active and release their runspace on shutdown. Neither test applies optimization settings to the host PC.
