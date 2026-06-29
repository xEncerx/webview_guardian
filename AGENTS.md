# AGENTS.md

## Project
`webview_guardian` is a Flutter package built on top of `flutter_inappwebview`. It provides a ready-to-use WebView wrapper and an `InAppWebView` adapter for ad blocking.

Main public entrypoint: `lib/webview_guardian.dart`.

Important public types:
- `AdblockService`
- `WebView`
- `WebViewController`
- `InAppWebViewAdblockAdapter`
- `StreamWebViewObserver`
- `WebViewObservabilityOptions`
- `FilterSubscription`
- `FilterHttpOptions`
- `CosmeticFilteringOptions`

## Architecture
Source code is split into:
- `lib/src/data`
- `lib/src/domain`
- `lib/src/infrastructure`
- `lib/src/presentation`

General responsibilities:
- `presentation`: WebView widget/controller API and `InAppWebView` adapter
- `infrastructure`: adblock service, request interceptors, injections, isolate, observability
- `domain`: entities, events, repository contracts
- `data`: parsers, network, persistence helpers

## Notes
- Current package/platform focus is Android and Windows.
- `WebView` wires ad blocking for users; `InAppWebViewAdblockAdapter` is for existing custom `InAppWebView` setups.
- The blocker handles network request interception plus cosmetic CSS/JS/scriptlet injection.
- Filter inputs: Hosts files, plain domain lists, and a practical subset of Adblock Plus/uBO-style rules.
- Heavy ABP features such as regex network rules, procedural cosmetics, and HTML filtering are intentionally unsupported.
- Filter downloads support custom timeouts, headers/User-Agent, and proxy settings.
- `updateSubscriptions()` and `clearCache()` are async and must be awaited when callers depend on the updated state.

## Validation
- Get dependencies: `flutter pub get`
- Analyze: `flutter analyze --no-fatal-infos --no-fatal-warnings`
- Format: `dart format .`
- Test: `flutter test`

## Testing Rule
Use only `flutter test`, not `dart test`, because this package mixes Flutter dependencies and barrel imports.

## Linting
- Analyzer config: `analysis_options.yaml`
- Lints: `very_good_analysis`
- Formatter width: 100
