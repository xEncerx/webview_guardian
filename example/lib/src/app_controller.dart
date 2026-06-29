// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_guardian/webview_guardian.dart';
import 'package:webview_guardian_example/src/subscription_storage.dart';

class AppController extends ChangeNotifier {
  AppController({SubscriptionStorage? storage}) : _storage = storage ?? SubscriptionStorage();

  static const defaultSubscriptionUrl = 'https://easylist.to/easylist/easylist.txt';

  final SubscriptionStorage _storage;
  final AdblockService adblockService = AdblockService();
  final StreamWebViewObserver observer = StreamWebViewObserver(delegates: const []);

  final List<String> _subscriptionUrls = [];
  final List<LogEntry> _logs = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Directory? _adblockDirectory;
  bool _isInitializing = true;
  bool _isUpdatingSubscriptions = false;
  bool _isDisposed = false;
  String? _statusMessage;
  int _blockedRequests = 0;
  int _allowedRequests = 0;
  int _cosmeticInjections = 0;
  int _scriptletInjections = 0;
  int _ruleCount = 0;

  bool get isInitializing => _isInitializing;
  bool get isUpdatingSubscriptions => _isUpdatingSubscriptions;
  bool get isReady => adblockService.isReady.value;
  bool get isEnabled => adblockService.isEnabled;
  String? get statusMessage => _statusMessage;
  String? get adblockDirectoryPath => _adblockDirectory?.path;
  int get blockedRequests => _blockedRequests;
  int get allowedRequests => _allowedRequests;
  int get cosmeticInjections => _cosmeticInjections;
  int get scriptletInjections => _scriptletInjections;
  int get ruleCount => _ruleCount;
  UnmodifiableListView<String> get subscriptionUrls => UnmodifiableListView(_subscriptionUrls);
  UnmodifiableListView<LogEntry> get logs => UnmodifiableListView(_logs);

  Future<void> init() async {
    _subscriptions
      ..add(observer.events.listen(_handleEvent))
      ..add(observer.errors.listen(_handleError))
      ..add(
        adblockService.ruleCountStream.listen((count) {
          _ruleCount = count;
          _safeNotifyListeners();
        }),
      );
    adblockService.isReady.addListener(_safeNotifyListeners);

    try {
      _adblockDirectory = await _storage.ensureAdblockDirectory();
      final savedUrls = await _storage.load(_adblockDirectory!);
      _subscriptionUrls
        ..clear()
        ..addAll(savedUrls.isEmpty ? const [defaultSubscriptionUrl] : savedUrls);
      await _storage.save(_adblockDirectory!, _subscriptionUrls);

      await adblockService.init(
        subscriptions: _toFilterSubscriptions(_subscriptionUrls),
        observer: observer,
        observabilityOptions: const WebViewObservabilityOptions(emitAllowedRequests: true),
        storagePath: _adblockDirectory!.path,
      );
      _statusMessage = 'Adblock service initialized.';
    } on Object catch (error) {
      _statusMessage = 'Initialization failed: $error';
      _addLog(LogEntry.error('Initialization failed', '$error'));
    } finally {
      _isInitializing = false;
      _safeNotifyListeners();
    }
  }

  Future<String?> addSubscription(String rawUrl) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid URL.';
    }
    if (_subscriptionUrls.contains(url)) {
      return 'This subscription is already added.';
    }

    _subscriptionUrls.add(url);
    await _persistAndUpdateSubscriptions();
    return null;
  }

  Future<void> removeSubscription(String url) async {
    _subscriptionUrls.remove(url);
    await _persistAndUpdateSubscriptions();
  }

  Future<void> restoreDefaultSubscription() async {
    if (_subscriptionUrls.contains(defaultSubscriptionUrl)) return;

    _subscriptionUrls.add(defaultSubscriptionUrl);
    await _persistAndUpdateSubscriptions();
  }

  void setAdblockEnabled(bool value) {
    adblockService.isEnabled = value;
    _statusMessage = value ? 'Ad blocking enabled.' : 'Ad blocking disabled.';
    _safeNotifyListeners();
  }

  Future<void> clearCache() async {
    _statusMessage = 'Clearing cache...';
    _safeNotifyListeners();

    await adblockService.clearCache();
    _statusMessage = 'Cache cleared.';
    _addLog(LogEntry.info('Cache cleared', 'Cached filters were removed.'));
    _safeNotifyListeners();
  }

  Future<void> _persistAndUpdateSubscriptions() async {
    final directory = _adblockDirectory;
    if (directory == null) return;

    _isUpdatingSubscriptions = true;
    _statusMessage = 'Updating filter subscriptions...';
    _safeNotifyListeners();

    await _storage.save(directory, _subscriptionUrls);
    await adblockService.updateSubscriptions(_toFilterSubscriptions(_subscriptionUrls));

    _isUpdatingSubscriptions = false;
    _statusMessage = 'Subscriptions updated.';
    _safeNotifyListeners();
  }

  List<FilterSubscription> _toFilterSubscriptions(List<String> urls) {
    return urls.map((url) => FilterSubscription(url: url)).toList();
  }

  void _handleEvent(WebViewEvent event) {
    switch (event) {
      case FilterListFetchStarted(:final url):
        _addLog(LogEntry.info('Filter fetch started', url));
      case FilterCacheMatch(:final url):
        _addLog(LogEntry.info('Filter cache match', url));
      case EngineCompiled(:final totalRules, :final compilationTime):
        _ruleCount = totalRules;
        _addLog(LogEntry.success('Engine compiled', '$totalRules rules in $compilationTime'));
      case EngineRestoredFromCache(:final totalRules, :final compilationTime):
        _ruleCount = totalRules;
        _addLog(
          LogEntry.success('Engine restored from cache', '$totalRules rules in $compilationTime'),
        );
      case FilterCacheCleared():
        _addLog(LogEntry.info('Filter cache cleared', 'All cached filter data was removed.'));
      case RequestBlocked(:final url):
        _blockedRequests++;
        _addLog(LogEntry.blocked('Request blocked', url));
      case RequestAllowed(:final url):
        _allowedRequests++;
        _addLog(LogEntry.allowed('Request allowed', url));
      case ScriptletInjected(:final hostname, :final scriptletName):
        _scriptletInjections++;
        _addLog(LogEntry.info('Scriptlet injected', '$scriptletName on $hostname'));
      case CosmeticCssInjected(:final hostname, :final selector):
        _cosmeticInjections++;
        _addLog(LogEntry.info('Cosmetic CSS injected', '$selector on $hostname'));
    }
  }

  void _handleError(WebViewError error) {
    _addLog(LogEntry.error(error.runtimeType.toString(), error.message));
  }

  void _addLog(LogEntry entry) {
    _logs.insert(0, entry);
    if (_logs.length > 100) {
      _logs.removeRange(100, _logs.length);
    }
    _safeNotifyListeners();
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    adblockService.isReady.removeListener(_safeNotifyListeners);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    adblockService.dispose();
    observer.dispose();
    super.dispose();
  }
}

class LogEntry {
  const LogEntry({
    required this.title,
    required this.details,
    required this.kind,
    required this.timestamp,
  });

  factory LogEntry.info(String title, String details) {
    return LogEntry(
      title: title,
      details: details,
      kind: LogEntryKind.info,
      timestamp: DateTime.now(),
    );
  }

  factory LogEntry.success(String title, String details) {
    return LogEntry(
      title: title,
      details: details,
      kind: LogEntryKind.success,
      timestamp: DateTime.now(),
    );
  }

  factory LogEntry.blocked(String title, String details) {
    return LogEntry(
      title: title,
      details: details,
      kind: LogEntryKind.blocked,
      timestamp: DateTime.now(),
    );
  }

  factory LogEntry.allowed(String title, String details) {
    return LogEntry(
      title: title,
      details: details,
      kind: LogEntryKind.allowed,
      timestamp: DateTime.now(),
    );
  }

  factory LogEntry.error(String title, String details) {
    return LogEntry(
      title: title,
      details: details,
      kind: LogEntryKind.error,
      timestamp: DateTime.now(),
    );
  }

  final String title;
  final String details;
  final LogEntryKind kind;
  final DateTime timestamp;
}

enum LogEntryKind { info, success, blocked, allowed, error }
