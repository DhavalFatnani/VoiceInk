# VoiceInk — project conventions

Read this before writing or editing code. Rules, not suggestions.

## Meta

- macOS menu-bar dictation app. Swift 6.0, SwiftUI, SwiftData (63 files import it), deployment target macOS 14.4.
- Xcode project (`VoiceInk.xcodeproj`), not a SwiftPM package. Targets: `VoiceInk` (app), `VoiceInkRefineXPC` (XPC service), `VoiceInkTests` (unit), `VoiceInkUITests` (UI). One shared scheme: `VoiceInk`.
- GPLv3. This is a fork: `origin` is `DhavalFatnani/VoiceInk`, `upstream` is `Beingpax/VoiceInk`. Keep changes GPL-compatible and rebasable on upstream.
- Bundle id is `com.prakashjoshipax.VoiceInk` — upstream's, deliberately unchanged so the installed app keeps its data and privacy grants.

## Build and test

Use the Makefile. It carries the signing and package-validation flags that raw `xcodebuild` needs; a bare `xcodebuild` invocation fails on the `mlx-swift` CudaBuild plugin.

- `make build` — Debug build of the app.
- `make test` — the `VoiceInkTests` unit suite (20 test files, `-only-testing:VoiceInkTests`). This is the check to run before claiming a change works. `VoiceInkUITests` is not wired into `make test`; run it only on request.
- `make local` — installable local build into `~/Downloads/VoiceInk.app`, self-signed.
- `make run` / `make dev`, `make dmg`, `make clean`, `make help`.
- First build clones and builds whisper.cpp into `~/VoiceInk-Dependencies` (slow, once). Do not delete that directory to save disk without saying so.
- `make release` needs a paid Apple Developer cert and stored notarization credentials. Run `/launch` before any release or DMG handed to another machine.

## Local-build limits — not bugs

- **Keychain always fails with `-34018` on local builds.** `KeychainService` sets `kSecUseDataProtectionKeychain`, which needs the `keychain-access-groups` entitlement, and `VoiceInk.local.entitlements` omits it because a self-signed cert has no Team ID. Never chase `-34018` as a defect. Do treat anything that *loops* on the failure as one.
- Run `./scripts/make-local-signing-cert.sh` once. Without the stable "VoiceInk Local Dev" identity, macOS drops Accessibility and Screen Recording grants on every rebuild, which looks exactly like a shortcut bug.
- Local builds have no iCloud dictionary sync and no auto-update.

## Memory and performance

This machine has 16 GB of RAM and is usually several GB into swap before VoiceInk starts. Memory is the binding constraint on every local-model decision.

- Check a model's weights against 16 GB before recommending it. `qwen2.5:7b` (4.4 GiB) is the working default for enhancement; `qwen2.5:14b` (8.4 GiB) is already tight. Whisper Large v3 (~3 GB) plus a 7B enhancement model is about the ceiling.
- "The app is a memory hog" has been wrong before. VoiceInk's own footprint measured 334 MB while Ollama held a 16.75 GiB model. **Measure first**: `ps -o rss=,comm= -p <pid>` per process, then Instruments Allocations or Leaks before changing any code.
- **`llama-server` is Ollama's child process.** Killing it is futile; `ollama serve` respawns it. Stop Ollama itself. See the global `~/.claude/CLAUDE.md` traps section.
- Enhancement lives in `VoiceInk/Services/AIEnhancement/` and `VoiceInk/Services/OllamaService.swift`. Slowness or timeouts there are usually the model, not the code.
- Invoke `/perf` on any report of slowness, hangs, or memory growth. Do not optimize before you have a measurement.

## Never touch

- `~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/ggml-large-v3*` — the Hinglish model and its encoder. It looks like a duplicate of a turbo model. It is not; it is the only thing covering Hindi-English code-switching. Full reasoning is in the global `~/.claude/CLAUDE.md` traps section.
- Anything in `~/Library/Application Support/com.prakashjoshipax.VoiceInk/` without asking first. That directory holds the live app's transcription history and models.

## Shortcuts and hotkeys

Global shortcut handling lives in `VoiceInk/Shortcuts/`. Read the relevant file before changing key behavior; do not add a second monitor path.

- `ShortcutMonitor.swift` — the event tap. `ShortcutStore.swift` — persistence. `ShortcutValidator.swift` — conflict rules. `ShortcutMigration.swift` — schema upgrades of stored bindings.
- `RecordingShortcutManager.swift`, `ModeShortcutManager.swift`, `RecorderPanelShortcutManager.swift` — the three registration sites.
- Shortcuts breaking after a rebuild is almost always a lost Accessibility grant from ad-hoc signing, not a code regression. Check `System Settings > Privacy & Security > Accessibility` before debugging.

## Menu-bar app patterns

- `MenuBarManager.swift` owns the status item; `Views/MenuBarView.swift` owns its content. `AppDelegate.swift` and `VoiceInk.swift` own lifecycle.
- The app has no dock presence by default. Never derive visibility from window `show`/`hide` events; they fire on occlusion.
- Windows are managed by controllers (`HistoryWindowController.swift`, ambient window manager). Do not create `NSWindow`s ad hoc from views.

## Working rules

- Keep changes small and rebasable on `upstream/main`. Match surrounding Swift style; no new dependencies without asking.
- Run `/lean-code` on every change: ship the smallest diff that does the job, no speculative abstraction.
- Run `/prove-it` before reporting anything done. `make test` output or a described manual run in the real app, not "should work". Shipped-but-broken is the recurring failure here.
