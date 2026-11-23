# Contributing

Keep changes explicit, reviewable, and reversible where the underlying operation allows. Do not add a tweak solely because it is popular or claim performance improvements without controlled measurements.

For a bug report, include the release version, Windows build, relevant hardware, steps to reproduce, and expected/actual results. Remove personal paths, hostnames, credentials, and tokens. Never upload your full `state` directory.

Build with Windows PowerShell 5.1 and .NET Framework 4.8 as described in the README. Run the relevant `Test-*.ps1` or isolated UI tests for the changed area. Tests must use temporary fixtures or fake system interfaces for mutations; do not apply live registry, driver, service, cleanup, or display actions as unattended test setup.

Preserve the distinction between session restore and persistent settings. Record original values before writes, validate the target executable/process, and preserve identifiable later manual changes. Do not silently enable monitoring, start administrator processes, or change system settings while rendering a page.

Contributions to the combined project must be compatible with GPL-3.0. Keep upstream copyright and license notices, document changes to the embedded Optimizer source, and include corresponding source in releases. Clearly identify significant AI assistance in contributions. AI-assisted patches still need the same review and validation.

Before publishing, use `Build-Release.ps1` and inspect the resulting allowlisted archives. Do not publish the working directory wholesale: it may contain local configuration and development results.
