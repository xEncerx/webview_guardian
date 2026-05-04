// ignore_for_file: discarded_futures

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

class MockFilterRepository extends Mock implements FilterRepository {}

class MockInAppWebViewController extends Mock implements InAppWebViewController {}

class MockWebResourceRequest extends Mock implements WebResourceRequest {}

void main() {
  group('Traffic Interceptors', () {
    late MockFilterRepository repository;
    late MockInAppWebViewController controller;
    late MockWebResourceRequest request;

    setUpAll(() {
      registerFallbackValue(
        NetworkRequest(
          url: 'https://example.com',
          host: 'example.com',
          resourceType: ResourceType.document,
          sourceHost: 'example.com',
        ),
      );
    });

    setUp(() {
      repository = MockFilterRepository();
      controller = MockInAppWebViewController();
      request = MockWebResourceRequest();

      when(() => request.url).thenReturn(WebUri('https://ads.example.com/script.js'));
      when(() => request.isForMainFrame).thenReturn(false);
      when(() => request.headers).thenReturn({'Accept': 'application/javascript'});
    });

    group('WindowsInterceptorAdapter', () {
      late WindowsInterceptorAdapter adapter;

      setUp(() {
        adapter = WindowsInterceptorAdapter(repository);
      });

      test('should block request when repository returns Block', () {
        when(() => repository.lookupNetworkRequest(any())).thenReturn(const Block());

        final intercept = adapter.shouldInterceptRequest!;
        final response = intercept(controller, request) as WebResourceResponse?;

        expect(response, isNotNull);
        expect(response!.statusCode, 200);
        expect(response.reasonPhrase, 'Forbidden');
        expect(response.data, isEmpty);
      });

      test('should allow request when repository returns Allow', () {
        when(() => repository.lookupNetworkRequest(any())).thenReturn(const Allow());

        final intercept = adapter.shouldInterceptRequest!;
        final response = intercept(controller, request) as WebResourceResponse?;

        expect(response, isNull);
      });

      test('should track main frame URI and use it as source for subsequent requests', () {
        // 1. Main frame request
        when(() => request.isForMainFrame).thenReturn(true);
        when(() => request.url).thenReturn(WebUri('https://example.com'));
        when(() => repository.lookupNetworkRequest(any())).thenReturn(const Allow());

        adapter.shouldInterceptRequest!(controller, request);

        final capturedMain = verify(() => repository.lookupNetworkRequest(captureAny())).captured;
        expect((capturedMain.last as NetworkRequest).sourceHost, 'example.com');

        // 2. Subresource request
        when(() => request.isForMainFrame).thenReturn(false);
        when(() => request.url).thenReturn(WebUri('https://ads.example.com/banner.jpg'));

        adapter.shouldInterceptRequest!(controller, request);

        final capturedSub = verify(() => repository.lookupNetworkRequest(captureAny())).captured;
        expect((capturedSub.last as NetworkRequest).sourceHost, 'example.com');
      });

      test('onEngineUpdated does not throw', () async {
        expect(() => adapter.onEngineUpdated(), returnsNormally);
      });
    });

    group('AndroidInterceptorAdapter', () {
      late AndroidInterceptorAdapter adapter;

      setUp(() {
        adapter = AndroidInterceptorAdapter(repository);
      });

      test('should block request when repository returns Block', () {
        when(() => repository.lookupNetworkRequest(any())).thenReturn(const Block());

        final intercept = adapter.shouldInterceptRequest!;
        final response = intercept(controller, request) as WebResourceResponse?;

        expect(response, isNotNull);
        expect(response!.statusCode, 200);
        expect(response.data, isEmpty);
      });

      test('should allow request when repository returns Allow', () {
        when(() => repository.lookupNetworkRequest(any())).thenReturn(const Allow());

        final intercept = adapter.shouldInterceptRequest!;
        final response = intercept(controller, request) as WebResourceResponse?;

        expect(response, isNull);
      });
    });

    group('TrafficInterceptorFactory', () {
      test('creates WindowsInterceptorAdapter on Windows', () {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final interceptor = TrafficInterceptorFactory.create(repository);
        expect(interceptor, isA<WindowsInterceptorAdapter>());
        debugDefaultTargetPlatformOverride = null;
      });

      test('creates AndroidInterceptorAdapter on Android', () {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final interceptor = TrafficInterceptorFactory.create(repository);
        expect(interceptor, isA<AndroidInterceptorAdapter>());
        debugDefaultTargetPlatformOverride = null;
      });

      test('throws on unsupported platform', () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        expect(
          () => TrafficInterceptorFactory.create(repository),
          throwsUnsupportedError,
        );
        debugDefaultTargetPlatformOverride = null;
      });
    });
  });
}
