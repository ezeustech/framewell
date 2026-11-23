# AI transparency

Framewell (previously Gaming Mode) was developed with substantial assistance from OpenAI's Codex/ChatGPT, directed by the project owner's feature requests and preferences.

## Where AI contributed

- PowerShell and C# implementation, including the WPF interface and embedded WinForms integration.
- Refactoring, troubleshooting, code review, and development of automated and mocked tests.
- Release packaging, technical explanations, and repository documentation.
- Original color palette definitions and interface layout. No AI-generated character art is included.

The Windows tools reuse and modify **Optimizer 17.0**, created by hellzerg and contributors. That work is credited separately and its GPL source is included. Microsoft APIs and NVIDIA interface references also underpin parts of the app; see the third-party notices.

## What this disclosure does not imply

AI assistance is not an independent audit, certification, performance benchmark, or guarantee of correctness. Much of the automated testing was developed with the same AI assistance as the implementation. Tests can share incorrect assumptions with the code they test.

The app has been checked on a single Windows 11 development PC. Read-only native checks and isolated tests cover important paths, but live system mutations, administrator handoff, every upstream action, anti-cheat compatibility, and broad hardware behavior have not all been exercised. There is no measured universal FPS or latency improvement. Version 3.2's updater and responsiveness changes, including their tests, were also implemented with Codex assistance.

## Runtime behavior

Framewell does not embed an AI model, call an AI API, or require an AI account. Development assistance is distinct from runtime functionality. Local profiles, paths, and journals stay in the portable installation's `app/state` directory unless you choose to export them. Network tests and explicit internet-connected Windows tools contact their selected services. Automatic updates contact GitHub's release API and download infrastructure; no profiles or system inventory are included in those requests. Updates can be disabled in Settings.

## Reporting problems

Report a reproducible issue with the app version, Windows version, affected feature, and expected versus observed behavior. Redact usernames, private game paths, server addresses, and credentials. Do not attach the entire `state` folder. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
