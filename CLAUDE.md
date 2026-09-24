# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An iOS comic reader whose UI follows Pixiv-SwiftUI and whose core is a **from-scratch Swift
reimplementation of Breeze's plugin system**. Breeze itself is a Flutter/Rust/QuickJS app
(plugins are TypeScript → single-file `.cjs` bundles distributed via npm/jsDelivr and GitHub
Releases); none of its code runs here — only its **plugin contract** does, so existing Breeze
plugins install and run unmodified.

Authoritative external references (check these instead of guessing at a contract):

- Plugin API contract and runtime API: <https://deretame.github.io/plugin-dev-docs/>
  (`getInfo`, `searchComic`, `getComicDetail`, `getReadSnapshot`, `fetchImageBytes`, …)
- Exact `bridge.call` route names plugins use: the `breeze-plugin-kit` npm package
  (`dist/tools.js`, `dist/runtime-api.js`)
- Plugin catalogue: `deretame/Breeze-plugin-list` → `plugins_data.json`

## Commands

There is no local macOS toolchain — **CI is the build**. Push to `develop` and read the run:

```
git push origin develop    # macos-26 → xcodegen → xcodebuild test → unsigned iPA artifact
gh run watch               # or: gh run view <id> --log-failed
```

With Xcode available:

```
brew install xcodegen
xcodegen generate                         # project.yml -> iBreeze.xcodeproj (gitignored)
xcodebuild test -project iBreeze.xcodeproj -scheme iBreeze \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test ... -only-testing:iBreezeTests/PluginCryptoTests          # one suite
xcodebuild test ... -only-testing:iBreezeTests/PluginCryptoTests/digests  # one test
```

New files need no project edits — drop them under `iBreeze/` or `iBreezeTests/`.

Smoke tests hit the network and are opt-in (CI sets both; skipped locally so offline runs stay green):

```
TEST_RUNNER_IBREEZE_SMOKE=1            # download + install real plugin, getInfo, image bytes
TEST_RUNNER_IBREEZE_SMOKE_NETWORK=1    # + real list -> detail -> chapter over the network
```

JS-layer work can be verified **without a Mac** — the harness boots the same injection chain in a
bare `node:vm` context that mimics JavaScriptCore (no web globals):

```
node Tools/plugin-js-harness.mjs                                 # 50 self-checks
node Tools/plugin-js-harness.mjs <bundle.cjs> <fnPath> '[json]'  # drive a real plugin bundle
node Tools/generate-app-icon.mjs                                 # regenerate the app icon
```

The harness re-execs itself with `NODE_USE_ENV_PROXY=1` when `HTTP_PROXY` is set (Node's `fetch`
ignores it otherwise), so real-network runs work behind a local proxy. Use it before pushing
whenever you touch the JS layer.

## Architecture

### Plugin call chain (spans several files)

```
UI (Features/*)
  └─ PluginRegistry   @MainActor @Observable; owns one runtime per plugin uuid
       └─ PluginSource    typed wrappers over fnPath contract calls (pagedList/comicDetail/…)
            └─ PluginRuntime       owns one JSContext; serialises all JS work
                 ├─ PluginRuntimeThread   16 MB-stack thread + hand-rolled serial loop
                 ├─ PluginJSLayer         concatenates and injects the JS layers (once per process)
                 ├─ PluginTimerCenter     setTimeout/setInterval → __host_runtime_timer_complete
                 └─ PluginHostBridge      the `bridge.call` route table
                      ├─ PluginCache / PluginConfigStore   per-plugin storage
                      ├─ PluginHTTPClient                  URLSession + HTTP/SOCKS5 proxy
                      └─ PluginCryptoRoutes → PluginCrypto (CryptoKit + CommonCrypto)
```

Bus: Swift installs `__nativeCall` / `__nativeCallSync` / `__nativeLog` / `__nativeTimer*` on the
JSContext; JS invokes routes by name, Swift resolves them back on the JS thread.

JS injection order (`PluginJSLayer.scriptNames`) — the order is load-bearing:

```
10_ibreeze_native_shim   host bus, byte-buffer pool, base64, crypto/timer/http hooks
20_ibreeze_html          BreezeHtml (cheerio subset) — plugins need it right after getInfo
04 → 00 → 05 → 06 → 07 → 10 → 20 → 30 → 60 → 63 → 70 → 99   vendored Breeze polyfills
90_ibreeze_host_shim     bridge/console + CommonJS loader — must run AFTER 99_exports
```

`Resources/PluginRuntime/` is a **folder reference** in `project.yml` and is excluded from the main
source glob; vendored files keep their upstream form, provenance in that folder's `NOTICE.md`.

### Install and storage

`PluginRepository` (cloud list) → `PluginInstaller` (jsDelivr mirrors → GitHub Release fallback;
loads the bundle in a throwaway runtime and reads `getInfo()` as the authoritative uuid/version,
rejecting mismatches) → `PluginStore` (bundle to `Application Support/Plugins/<uuid>.cjs`,
metadata in `index.json`).

### UI

`AppRoute` + `appNavigationDestinations()` is the single mapping from routes to pages
(`comicList` / `comicDetail` / `reader`). Plugin images never use their URLs directly: they go
through `PluginSource.imageBytes` via `ComicImageLoader` (memory + disk, keyed by uuid+url) and
`PluginImageView`. Plugin-declared settings are rendered generically by `PluginSettingsView` from
`getSettingsBundle`, and any user-facing text from a plugin is passed through `.convertedChinese`.

## Gotchas (hard-won)

- **Plugin JS must run on `PluginRuntimeThread` (16 MB stack).** With GCD's default worker stack,
  plugins bundling axios die with `Maximum call stack size exceeded` on real requests. Do not
  swap it back to `DispatchQueue`.
- **`BreezeHtml` is mandatory.** Plugins scrape HTML right after `getInfo`; without it they throw
  `ReferenceError: BreezeHtml is not defined`.
- **04 before 00**: `04_runtime_base_polyfills` supplies the `Buffer`/`Blob`/`FormData` that
  `00_bootstrap` reads at load time; reversing them breaks startup.
- **Binary crosses the bus as base64**: arguments send byte arrays, returns are wrapped as
  `{ "__ibreezeBinary": "<base64>" }`. Use `invokeData` / `invoke(_:fnPath:)` accordingly.
- **`extern` round-trips**: whatever a plugin returns as `extern` must be sent back on the next
  call in the same context.
- Contract models are deliberately lenient (`JSONValue`, optionals) — real plugins deviate from
  the docs, so make decoding tolerant instead of strict.
- Deployment target is iOS 18; Liquid Glass APIs (`glassEffect`, `tabBarMinimizeBehavior`) are
  iOS 26-only and must stay behind `if #available(iOS 26.0, *)` — see `glassSurface`.

## Conventions

- Comments and commit messages in Chinese; identifiers in English.
- Conventional Commits, since this is the owner's own project — `feat(runtime): …`, `fix(ui): …`,
  `chore(ci): …` (scope examples: `runtime`, `install`, `ui`, `docs`, `test`, `ci`).
- One type per file; `@MainActor @Observable` for view models and stores.
- Work on `develop` only. `main` receives PRs **from `develop`** — never push to `main` directly.
  Before opening a PR, lay out how many PRs and what each contains, then wait for confirmation.
- Release notes follow the owner's CHANGELOG format (newest version block on top, grouped by
  `### Feat(scope)` / `### Fix(scope)` / `### Refactor` / `### Chore`, Chinese bullets that say
  what changed for the user rather than a per-file diff).
