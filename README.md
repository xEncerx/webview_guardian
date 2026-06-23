[![Powered by flutter_inappwebview](https://img.shields.io/badge/Powered%20by-flutter__inappwebview-blue.svg)](https://github.com/pichillilorenzo/flutter_inappwebview)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

# webview_guardian

`webview_guardian` is a Flutter WebView wrapper with optional ad blocking. You can use it as a regular WebView, or pass an `AdblockService` to block network requests and apply cosmetic filters.

The package is built on top of [`flutter_inappwebview`](https://github.com/pichillilorenzo/flutter_inappwebview).

## Supported Platforms

| Android | Windows | iOS | macOS | Linux | Web |
| :-----: | :-----: | :-: | :---: | :---: | :-: |
|   ✅   |   ✅   | 🚧  |  🚧   |  🚧   | ❌  |

## Installation

The package is not published on pub.dev yet. Add it from GitHub:

```yaml
dependencies:
  webview_guardian:
    git:
      url: https://github.com/xEncerx/webview_guardian.git
      ref: main
```

Then fetch dependencies:

```sh
flutter pub get
```

## Quick Start

Create one `AdblockService`, initialize it once, and pass it to `WebView`.

```dart
import 'package:flutter/material.dart';
import 'package:webview_guardian/webview_guardian.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final AdblockService _adblockService = AdblockService();
  late final Future<void> _initAdblock;

  @override
  void initState() {
    super.initState();
    _initAdblock = _adblockService.init(
      subscriptions: const [
        FilterSubscription(
          url: 'https://easylist.to/easylist/easylist.txt',
        ),
      ],
    );
  }

  @override
  void dispose() {
    _adblockService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initAdblock,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Adblock init failed: ${snapshot.error}'));
        }

        return WebView(
          initialUrl: 'https://example.com',
          adblockService: _adblockService,
        );
      },
    );
  }
}
```

`AdblockService.init()` must complete before you call `updateSubscriptions()` or `clearCache()`.

## Use WebView Without Adblock

Ad blocking is optional. If you do not pass `adblockService`, the widget behaves like a normal WebView wrapper.

```dart
WebView(
  initialUrl: 'https://example.com',
  onWebViewCreated: (controller) async {
    final url = await controller.getUrl();
    debugPrint('Current URL: $url');
  },
)
```

## Use Adblock With Your Own InAppWebView

The `WebView` widget already wires the adblock service into `InAppWebView`. If you need a custom `InAppWebView` setup, use `InAppWebViewAdblockAdapter` directly.

Use one long-lived `AdblockService`, but create one adapter per `InAppWebView` instance. Do not share one adapter between tabs or widgets because it stores per-WebView script injection state.

```dart
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_guardian/webview_guardian.dart';

class CustomWebView extends StatefulWidget {
  const CustomWebView({
    required this.adblockService,
    super.key,
  });

  final AdblockService adblockService;

  @override
  State<CustomWebView> createState() => _CustomWebViewState();
}

class _CustomWebViewState extends State<CustomWebView> {
  static final WebUri _initialUri = WebUri('https://example.com');

  late final InAppWebViewAdblockAdapter _adapter;

  @override
  void initState() {
    super.initState();

    _adapter = InAppWebViewAdblockAdapter(
      adblockService: widget.adblockService,
      baseSettings: InAppWebViewSettings(
        isInspectable: kDebugMode,
        mediaPlaybackRequiresUserGesture: false,
      ),
      initialUrl: Uri.parse(_initialUri.toString()),
    );
  }

  @override
  void dispose() {
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: _initialUri),
      initialSettings: _adapter.initialSettings,
      initialUserScripts: UnmodifiableListView(_adapter.initialUserScripts),
      shouldInterceptRequest: _adapter.shouldInterceptRequest,
      shouldOverrideUrlLoading: _adapter.shouldOverrideUrlLoading,
      onLoadStart: (controller, url) async {
        await _adapter.onLoadStart(controller, url);
      },
    );
  }
}
```

The adapter applies the settings required for request interception and adblock script injection. Pass your own `baseSettings` if you need additional `InAppWebViewSettings`; the adapter will copy them and enable the required adblock settings on top.

## Configure Filters

Each filter list is described by `FilterSubscription`.

```dart
await adblockService.init(
  subscriptions: const [
    FilterSubscription(
      url: 'https://easylist.to/easylist/easylist.txt',
      updateInterval: Duration(hours: 24),
    ),
  ],
);
```

`updateInterval` defaults to 24 hours. Set it to `null` if you do not want automatic periodic updates for that subscription.

To replace subscriptions after initialization:

```dart
await adblockService.updateSubscriptions([
  const FilterSubscription(
    url: 'https://easylist.to/easylist/easylist.txt',
  ),
  const FilterSubscription(
    url: 'https://easylist.to/easylist/easyprivacy.txt',
  ),
]);
```

`updateSubscriptions()` returns `Future<void>`. Await it before reading state that depends on the updated filters.

## Manage Adblock State

Useful `AdblockService` members:

| API                  | Description                                                         |
| -------------------- | ------------------------------------------------------------------- |
| `isEnabled`          | Enables or disables blocking without rebuilding filters.            |
| `isReady`            | `ValueNotifier<bool>` that becomes `true` when the engine is ready. |
| `ruleCount`          | Current number of loaded rules.                                     |
| `ruleCountStream`    | Emits rule count changes after rebuilds.                            |
| `repository`         | Active `FilterRepository`, available after initialization.          |
| `orchestrator`       | Active injection orchestrator, available after initialization.      |
| `trafficInterceptor` | Active traffic interceptor, available after initialization.         |

Toggle blocking:

```dart
adblockService.isEnabled = false;
adblockService.isEnabled = true;
```

Clear cached filter lists and compiled engines:

```dart
await adblockService.clearCache();
```

`clearCache()` clears the in-memory engine and completes after the background cache clear job finishes.

## Observe Events

Use `StreamWebViewObserver` when you want to show logs or counters in the UI.

```dart
final observer = StreamWebViewObserver(delegates: const <WebViewObserver>[]);

await adblockService.init(
  subscriptions: const [
    FilterSubscription(url: 'https://easylist.to/easylist/easylist.txt'),
  ],
  observer: observer,
);

final subscription = observer.events.listen((event) {
  switch (event) {
    case RequestBlocked(:final url):
      debugPrint('Blocked: $url');
    case EngineCompiled(:final totalRules):
      debugPrint('Compiled rules: $totalRules');
    case EngineRestoredFromCache(:final totalRules):
      debugPrint('Restored rules: $totalRules');
    default:
      debugPrint('Adblock event: $event');
  }
});

// Later, when you no longer need the observer:
await subscription.cancel();
observer.dispose();
```

`RequestAllowed` events are disabled by default because they can be emitted very often. Enable them only if your UI or analytics needs them:

```dart
await adblockService.init(
  subscriptions: const [
    FilterSubscription(url: 'https://easylist.to/easylist/easylist.txt'),
  ],
  observer: observer,
  observabilityOptions: const WebViewObservabilityOptions(
    emitAllowedRequests: true,
  ),
);
```

Other observability options:

| Option                    | Default | Controls                      |
| ------------------------- | ------- | ----------------------------- |
| `emitBlockedRequests`     | `true`  | `RequestBlocked` events.      |
| `emitAllowedRequests`     | `false` | `RequestAllowed` events.      |
| `emitCosmeticInjections`  | `true`  | `CosmeticCssInjected` events. |
| `emitScriptletInjections` | `true`  | `ScriptletInjected` events.   |

## Configure Filter List Requests

Use `FilterHttpOptions` to configure how remote filter lists are downloaded.

```dart
await adblockService.init(
  subscriptions: const [
    FilterSubscription(url: 'https://easylist.to/easylist/easylist.txt'),
  ],
  httpOptions: const FilterHttpOptions(
    connectTimeout: Duration(seconds: 15),
    receiveTimeout: Duration(seconds: 60),
    headers: {
      'User-Agent': 'MyApp/1.0',
    },
    proxy: 'http://proxy.example.com:8080',
  ),
);
```

`proxy` supports `http://`, `https://`, `socks4://`, and `socks5://` URLs.

## WebView API

`WebView` accepts these commonly used parameters:

| Parameter                | Description                                                   |
| ------------------------ | ------------------------------------------------------------- |
| `initialUrl`             | URL loaded when the widget is created.                        |
| `adblockService`         | Optional `AdblockService`. Omit it to disable ad blocking.    |
| `enablePullToRefresh`    | Enables pull-to-refresh where supported. Defaults to `false`. |
| `pullToRefreshSettings`  | Colors and size for pull-to-refresh.                          |
| `gestureRecognizers`     | Gestures consumed by the WebView.                             |
| `onWebViewCreated`       | Gives you a `WebViewController`.                              |
| `onLoadStart`            | Called when navigation starts.                                |
| `onLoadStop`             | Called when navigation finishes.                              |
| `onProgressChanged`      | Called with loading progress from 0 to 100.                   |
| `onUpdateVisitedHistory` | Called when visited history changes.                          |
| `onReceivedError`        | Called when a resource loading error occurs.                  |

Controller methods:

| Method                              | Description                                                  |
| ----------------------------------- | ------------------------------------------------------------ |
| `loadUrl(String url)`               | Loads a URL.                                                 |
| `goBack()`                          | Navigates back.                                              |
| `goForward()`                       | Navigates forward.                                           |
| `canGoBack()`                       | Returns whether back navigation is available.                |
| `canGoForward()`                    | Returns whether forward navigation is available.             |
| `reload()`                          | Reloads the current page.                                    |
| `stopLoading()`                     | Stops loading.                                               |
| `getUrl()`                          | Returns the current URL as `String?`.                        |
| `evaluateJavascript(String source)` | Runs JavaScript after the page is ready enough to handle it. |

Example with navigation controls:

```dart
WebViewController? controller;

WebView(
  initialUrl: 'https://example.com',
  adblockService: adblockService,
  onWebViewCreated: (createdController) {
    controller = createdController;
  },
  onLoadStop: (url) async {
    final title = await controller?.evaluateJavascript('document.title');
    debugPrint('Loaded $url with title: $title');
  },
)
```

## Pull To Refresh

```dart
WebView(
  initialUrl: 'https://example.com',
  enablePullToRefresh: true,
  pullToRefreshSettings: const WebViewPullToRefreshSettings(
    color: Colors.blue,
    backgroundColor: Colors.white,
  ),
)
```

Pull-to-refresh is only active on platforms supported by `flutter_inappwebview`.

## Filter Format Notes

The package supports common hosts/domain lists and a practical subset of Adblock Plus network and cosmetic rules. Heavy Adblock Plus features such as regular-expression network rules and procedural cosmetics are intentionally not supported.

## Android Rendering Note

If you see visual glitches when closing a screen that contains `WebView`, first try updating Flutter to the latest stable version. As of Flutter 3.44, enabling Flutter's experimental HCPP renderer can also help on affected Android devices.

Add this application-level flag to your Android manifest:

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableHcpp"
    android:value="true" />
```

This is an Android rendering workaround, not an adblock setting, so the package does not enable it automatically.
