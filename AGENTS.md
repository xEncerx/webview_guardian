# AGENTS.md

## Project
`webview_guardian` is a Flutter package built on top of `flutter_inappwebview`. It provides a WebView wrapper with optional built-in ad blocking.

Main public entrypoint: `lib/webview_guardian.dart`.

Important public types:
- `AdblockService`
- `WebView`
- `WebViewController`
- `StreamWebViewObserver`
- `FilterSubscription`
- `FilterHttpOptions`

## Architecture
Source code is split into:
- `lib/src/data`
- `lib/src/domain`
- `lib/src/infrastructure`
- `lib/src/presentation`

General responsibilities:
- `presentation`: WebView widget/controller API
- `infrastructure`: adblock service, interceptors, isolate, observability
- `domain`: entities, events, repository contracts
- `data`: parsers, network, persistence helpers

## Notes
- Ad blocking is optional; `WebView` can be used without `AdblockService`.
- Filter parsing and compilation happen in a background isolate.
- The engine supports request interception and cosmetic CSS/JS injection.
- Current package/platform focus is Android and Windows.

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
