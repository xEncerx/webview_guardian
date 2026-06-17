[![Powered by flutter_inappwebview](https://img.shields.io/badge/Powered%20by-flutter__inappwebview-blue.svg)](https://github.com/pichillilorenzo/flutter_inappwebview) 
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)


# WebView with Adblock

A custom wrapper package for `flutter_inappwebview` that provides an ad-blocking engine out of the box. It supports both network request interception and cosmetic filtering (CSS/JS injection).

### Supported Platforms

| Android | Windows |     iOS      |    macOS     |    Linux     | Web |
| :-----: | :-----: | :----------: | :----------: | :----------: | :-: |
|   ✅    |   ✅    | 🚧 (Planned) | 🚧 (Planned) | 🚧 (Planned) | ❌  |

## Features

- **Network Request Interception:** Blocks network requests matching ad, tracker, and malware domains.
- **Cosmetic Filters (CSS/JS Injection):** Hides ad placeholders and injects scriptlets to bypass anti-adblockers.
- **High Performance & Low Latency:**
  - **Isolates:** Parsing and compilation of filter lists are offloaded to a background Isolate, preventing UI blocking.
  - **Advanced Matching Algorithms:** Uses **Hostname Trie Search** for domain rules and **Token Dispatch** (searching by 5-character patterns inside the URL) for incredibly fast request matching.
- **Filter Engine Caching:** Compiled rules are serialized and cached locally, allowing the engine to start instantly on subsequent app launches.
- **Multiple Filter Formats:** Supports `Hosts`, `Domain`, and `Adblock Plus` formats.
  _(Note: To guarantee low latency on mobile, the Adblock Plus parser intentionally ignores heavy rules like regex and procedural cosmetics)._
- **Auto-Updates:** Keep your filter lists fresh with background timers.
- **Rich Observability:** Monitor the adblock engine's state and blocked requests using `WebViewObserver` or `StreamWebViewObserver` (with reactive streams).

## Table of Contents

- [WebView with Adblock](#webview-with-adblock)
    - [Supported Platforms](#supported-platforms)
  - [Features](#features)
  - [Table of Contents](#table-of-contents)
  - [Quick Start](#quick-start)
    - [1. Initialize the AdblockService](#1-initialize-the-adblockservice)
    - [2. Use the WebView Widget](#2-use-the-webview-widget)
    - [3. Reacting to Service Readiness](#3-reacting-to-service-readiness)
  - [Core Components Usage](#core-components-usage)
    - [A. AdblockService Configuration](#a-adblockservice-configuration)
      - [Network Configuration with FilterHttpOptions](#network-configuration-with-filterhttpoptions)
    - [B. WebView Widget](#b-webview-widget)
      - [WebView Widget Callbacks](#webview-widget-callbacks)
    - [C. WebViewController](#c-webviewcontroller)
      - [Available Methods](#available-methods)
  - [Observing Events](#observing-events)
    - [1. Using StreamWebViewObserver (Recommended for UI)](#1-using-streamwebviewobserver-recommended-for-ui)
    - [2. Using WebViewObserver Directly (For Simple Logging/Debugging)](#2-using-webviewobserver-directly-for-simple-loggingdebugging)
    - [WebViewEvent Types](#webviewevent-types)
    - [WebViewError Types](#webviewerror-types)
  - [Cache and Memory Management](#cache-and-memory-management)

## Quick Start

The ad-blocking functionality is entirely **optional**. The `WebView` widget will function as a standard browser if no `AdblockService` is provided.

For the best performance, `AdblockService` should be initialized as a **singleton** (e.g., using `get_it` or provider) when your app starts, and then passed to the `WebView` widget.

### 1. Initialize the AdblockService

```dart
import 'package:webview_guardian/webview_guardian.dart';

// Initialize this once in your main() or DI setup
final adblockService = AdblockService();

await adblockService.init(
  subscriptions: [
    FilterSubscription(
      url: 'https://easylist.to/easylist/easylist.txt',
      // updateInterval is optional. If omitted, updates only on app start.
      updateInterval: const Duration(hours: 1),
    ),
  ],
);
```

### 2. Use the WebView Widget

```dart
import 'package:flutter/material.dart';
import 'package:webview_guardian/webview_guardian.dart';

class MyBrowserScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browser')),
      body: WebView(
        initialUrl: 'https://example.com',
        // Pass your singleton AdblockService here
        adblockService: adblockService,
        onWebViewCreated: (controller) {
          // Use WebViewController to manage navigation
        },
      ),
    );
  }
}
```

### 3. Reacting to Service Readiness

Since `isReady` is a `ValueNotifier<bool>`, you can reactively listen to its state:

```dart
// Using ValueListenableBuilder
ValueListenableBuilder<bool>(
  valueListenable: adblockService.isReady,
  builder: (context, isReady, child) {
    return Text(isReady ? 'Adblock ready' : 'Loading...');
  },
)

// Or listen directly
adblockService.isReady.addListener(() {
  if (adblockService.isReady.value) {
    print('Filter engine is ready!');
  }
});
```

## Core Components Usage

### A. AdblockService Configuration

`AdblockService` orchestrates everything: background updates, isolate management, and rule evaluation.

- **`isEnabled`**: You can toggle the ad-blocker on and off dynamically by setting `adblockService.isEnabled = true/false`.
- **`isReady`**: A `ValueNotifier<bool>` that indicates whether the filter engine is loaded and ready.
- **`ruleCount` & `ruleCountStream`**: You can easily retrieve the total number of currently active rules synchronously via `ruleCount`, or build reactive UIs (like `StreamBuilder`) using the `ruleCountStream` to get real-time updates when the engine recompiles.
- **`init()`**: Takes a list of `FilterSubscription`s, optional `FilterHttpOptions` for network requests, and an optional `WebViewObserver`. Call it once before using `updateSubscriptions()` or `clearCache()`.

#### Network Configuration with FilterHttpOptions

When initializing `AdblockService`, you can customize network behavior using `FilterHttpOptions`:

```dart
await adblockService.init(
  subscriptions: mySubscriptions,
  httpOptions: FilterHttpOptions(
    connectTimeout: const Duration(seconds: 15),  // Connection timeout
    receiveTimeout: const Duration(seconds: 60), // Response timeout
    headers: {
      'User-Agent': 'MyApp/1.0',
      'Accept': 'text/plain',
    },
    proxy: 'http://proxy.example.com:8080',      // Optional proxy
  ),
);
```

**FilterHttpOptions Parameters:**

| Parameter        | Type                  | Default | Description                                                                                  |
| ---------------- | --------------------- | ------- | -------------------------------------------------------------------------------------------- |
| `connectTimeout` | `Duration`            | 15s     | Maximum time to wait for establishing a connection.                                          |
| `receiveTimeout` | `Duration`            | 60s     | Maximum time to wait for a complete response.                                                |
| `headers`        | `Map<String, String>` | `{}`    | Custom headers added to all filter list requests.                                            |
| `proxy`          | `String?`             | `null`  | Proxy URL for requests. Supports `http://`, `https://`, `socks4://` and `socks5://` formats. |

### B. WebView Widget

The `WebView` widget is a wrapper around `InAppWebView`.

- **`initialUrl`**: The starting page.
- **`adblockService`**: If provided, intercepts requests and applies cosmetic injections.
- **`enablePullToRefresh`**: Whether to enable pull-to-refresh functionality. Defaults to false.
- **`pullToRefreshSettings`**: Customization for the pull-to-refresh behavior and appearance. Use `WebViewPullToRefreshSettings`.

#### WebView Widget Callbacks

| Callback                 | Parameters                       | Description                                   |
| ------------------------ | -------------------------------- | --------------------------------------------- |
| `onWebViewCreated`       | `(WebViewController controller)` | Called when the controller is ready.          |
| `onLoadStart`            | `(Uri? url)`                     | Called when a page starts loading.            |
| `onLoadStop`             | `(Uri? url)`                     | Called when a page finishes loading.          |
| `onProgressChanged`      | `(int progress)`                 | Called when loading progress changes (0-100). |
| `onUpdateVisitedHistory` | `(Uri? url, bool? isReload)`     | Called when visited history is updated.       |
| `onReceivedError`        | `(Uri url, String errorDetails)` | Called when a resource loading error occurs.  |

### C. WebViewController

When `onWebViewCreated` fires, it yields a `WebViewController`. This acts as a facade over `InAppWebViewController` to safely manage browser navigation, history, and scripts without exposing the underlying implementation details.

#### Available Methods

| Method                              | Returns           | Description                     |
| ----------------------------------- | ----------------- | ------------------------------- |
| `loadUrl(String url)`               | `Future<void>`    | Loads the given URL.            |
| `goBack()`                          | `Future<void>`    | Navigates back in history.      |
| `goForward()`                       | `Future<void>`    | Navigates forward in history.   |
| `canGoBack()`                       | `Future<bool>`    | Checks if can navigate back.    |
| `canGoForward()`                    | `Future<bool>`    | Checks if can navigate forward. |
| `reload()`                          | `Future<void>`    | Reloads the current page.       |
| `stopLoading()`                     | `Future<void>`    | Stops the current page loading. |
| `getUrl()`                          | `Future<String?>` | Returns the current URL.        |
| `evaluateJavascript(String source)` | `Future<dynamic>` | Evaluates JavaScript code.      |

## Observing Events

You can monitor the internal workings of the adblock engine using `StreamWebViewObserver` or a simple `WebViewObserver` implementation.

### 1. Using StreamWebViewObserver (Recommended for UI)

`StreamWebViewObserver` is a special `WebViewObserver` that broadcasts events and errors to multiple delegate observers and exposes them as streams for reactive UI updates:

```dart
import 'package:webview_guardian/webview_guardian.dart';

// Create delegate observers for logging, analytics, etc.
class MyLogger implements WebViewObserver {
  @override
  void onEvent(WebViewEvent event) => print('Event: $event');

  @override
  void onError(WebViewError error) => print('Error: $error');
}

// Create StreamWebViewObserver with delegates
final observer = StreamWebViewObserver(delegates: [MyLogger()]);

// Pass it to the service during init
await adblockService.init(
  subscriptions: mySubscriptions,
  observer: observer,
);

// Now you can use streams for reactive UI updates
StreamBuilder<WebViewEvent>(
  stream: observer.events,
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      final event = snapshot.data!;
      if (event is RequestBlocked) {
        return Text('Blocked: ${event.url}');
      } else if (event is EngineCompiled) {
        return Text('Engine ready: ${event.totalRules} rules');
      }
    }
    return const SizedBox.shrink();
  },
);

// Listen to errors
observer.errors.listen((error) {
  print('Adblock Error: ${error.message}');
});

// Dispose observers you create when they are no longer needed.
observer.dispose();
```

### 2. Using WebViewObserver Directly (For Simple Logging/Debugging)

For simple use cases, you can implement `WebViewObserver` directly without streams:

```dart
class MyObserver implements WebViewObserver {
  @override
  void onEvent(WebViewEvent event) {
    if (event is RequestBlocked) {
      print('Blocked: ${event.url}');
    } else if (event is EngineCompiled) {
      print('Compiled ${event.totalRules} rules in ${event.compilationTime}');
    }
  }

  @override
  void onError(WebViewError error) {
    print('Adblock Error: ${error.message}');
  }
}

// During init:
await adblockService.init(
  subscriptions: mySubscriptions,
  observer: MyObserver(),
);
```

### WebViewEvent Types

| Event                     | Trigger                                        | Description                                      |
| ------------------------- | ---------------------------------------------- | ------------------------------------------------ |
| `FilterListFetchStarted`  | When fetching a filter list begins             | Contains the URL being fetched.                  |
| `EngineCompiled`          | When the filter engine finishes compiling      | Contains total rules count and compilation time. |
| `EngineRestoredFromCache` | When the engine is loaded from cache           | Contains cached rules count and restore time.    |
| `FilterCacheCleared`      | When the filter cache is cleared               | Indicates all cached data was removed.           |
| `FilterCacheMatch`        | When a filter list matches cache (no download) | Contains the URL that matched cache.             |
| `RequestBlocked`          | When a network request is blocked              | Contains the blocked URL.                        |
| `RequestAllowed`          | When a network request is allowed              | Contains the allowed URL.                        |
| `ScriptletInjected`       | When a scriptlet is injected into a page       | Contains hostname and scriptlet name.            |
| `CosmeticCssInjected`     | When cosmetic CSS is injected into a page      | Contains hostname and CSS selector.              |

### WebViewError Types

| Error                | Trigger                             | Description                                  |
| -------------------- | ----------------------------------- | -------------------------------------------- |
| `FilterFetchFailed`  | Failed to download filter list      | Network or parsing error during fetch.       |
| `CacheRestoreFailed` | Failed to restore engine from cache | Corrupted or incompatible cache file.        |
| `EngineBuildFailed`  | Failed to compile filter rules      | Error during rule compilation.               |
| `EngineInitFailed`   | Failed to initialize engine         | General initialization failure.              |
| `IsolateCrashError`  | Background isolate crashed          | The parsing isolate terminated unexpectedly. |

## Cache and Memory Management

- **`await clearCache()`**: Clears all downloaded filters and compiled engine files from the device storage. It also clears the in-memory engine immediately and completes after the cache clear job finishes.
- **`await updateSubscriptions()`**: Replaces the currently active subscriptions and completes after the effective background update finishes. Multiple pending updates are collapsed so only the latest subscription list is built.
- **`dispose()`**: Cancels all update timers and shuts down the background isolate. Make sure to call this if your app completely tears down the service. Observers passed to `init()` remain caller-owned and should be disposed by the code that created them.
