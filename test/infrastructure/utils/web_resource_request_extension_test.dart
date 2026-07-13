import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

class MockWebResourceRequest extends Mock implements WebResourceRequest {}

void main() {
  group('WebResourceRequestX.getResourceType', () {
    late MockWebResourceRequest request;

    setUp(() {
      request = MockWebResourceRequest();
      when(() => request.headers).thenReturn({});
    });

    void setupUrl(String urlString) {
      when(() => request.url).thenReturn(WebUri(urlString));
    }

    test('should return document for main frame', () {
      setupUrl('https://example.com/script.js');
      expect(request.getResourceType(true), ResourceType.document);
    });

    test('should detect XHR by X-Requested-With header (XMLHttpRequest)', () {
      setupUrl('https://example.com/api/data');
      when(() => request.headers).thenReturn({'X-Requested-With': 'XMLHttpRequest'});
      expect(request.getResourceType(false), ResourceType.xmlHttpRequest);
    });

    test('should detect Fetch by x-requested-with header (Fetch) - case insensitive key', () {
      setupUrl('https://example.com/api/data');
      when(() => request.headers).thenReturn({'x-requested-with': 'Fetch'});
      expect(request.getResourceType(false), ResourceType.xmlHttpRequest);
    });

    group('Heuristic by URL extension', () {
      test('should detect script by .js extension', () {
        setupUrl('https://example.com/app.js');
        expect(request.getResourceType(false), ResourceType.script);
      });

      test('should detect script by .ts extension', () {
        setupUrl('https://example.com/app.ts');
        expect(request.getResourceType(false), ResourceType.script);
      });

      test('should detect stylesheet by .css extension', () {
        setupUrl('https://example.com/style.css');
        expect(request.getResourceType(false), ResourceType.stylesheet);
      });

      test('should detect image by .png extension', () {
        setupUrl('https://example.com/img.png');
        expect(request.getResourceType(false), ResourceType.image);
      });

      test('should detect image by .jpg extension', () {
        setupUrl('https://example.com/img.jpg');
        expect(request.getResourceType(false), ResourceType.image);
      });

      test('should detect image by .jpeg extension', () {
        setupUrl('https://example.com/img.jpeg');
        expect(request.getResourceType(false), ResourceType.image);
      });

      test('should detect image by .gif extension', () {
        setupUrl('https://example.com/img.gif');
        expect(request.getResourceType(false), ResourceType.image);
      });

      test('should detect image by .svg extension', () {
        setupUrl('https://example.com/img.svg');
        expect(request.getResourceType(false), ResourceType.image);
      });

      test('should detect image by .ico extension', () {
        setupUrl('https://example.com/favicon.ico');
        expect(request.getResourceType(false), ResourceType.image);
      });

      test('should detect image by .webp extension', () {
        setupUrl('https://example.com/img.webp');
        expect(request.getResourceType(false), ResourceType.image);
      });

      test('should detect media by .mp4 extension', () {
        setupUrl('https://example.com/video.mp4');
        expect(request.getResourceType(false), ResourceType.media);
      });

      test('should detect media by .mp3 extension', () {
        setupUrl('https://example.com/audio.mp3');
        expect(request.getResourceType(false), ResourceType.media);
      });

      test('should detect media by .webm extension', () {
        setupUrl('https://example.com/video.webm');
        expect(request.getResourceType(false), ResourceType.media);
      });

      test('should detect media by .m3u8 extension', () {
        setupUrl('https://example.com/stream.m3u8');
        expect(request.getResourceType(false), ResourceType.media);
      });

      test('should detect xmlHttpRequest by .xml extension', () {
        setupUrl('https://example.com/data.xml');
        expect(request.getResourceType(false), ResourceType.xmlHttpRequest);
      });

      test('should detect xmlHttpRequest by .json extension', () {
        setupUrl('https://example.com/data.json');
        expect(request.getResourceType(false), ResourceType.xmlHttpRequest);
      });

      test('should detect font by .woff extension', () {
        setupUrl('https://example.com/font.woff');
        expect(request.getResourceType(false), ResourceType.font);
      });

      test('should detect font by .woff2 extension', () {
        setupUrl('https://example.com/font.woff2');
        expect(request.getResourceType(false), ResourceType.font);
      });

      test('should detect subdocument by .html extension', () {
        setupUrl('https://example.com/frame.html');
        expect(request.getResourceType(false), ResourceType.subdocument);
      });

      test('should be case-insensitive for extensions', () {
        setupUrl('https://example.com/APP.JS');
        expect(request.getResourceType(false), ResourceType.script);
        setupUrl('https://example.com/IMG.PNG');
        expect(request.getResourceType(false), ResourceType.image);
      });

      test('should classify extensionless URLs without useful headers as other', () {
        setupUrl('https://example.com/path/to/resource');
        expect(request.getResourceType(false), ResourceType.other);
      });
    });

    group('Heuristic by Accept header', () {
      test('should detect image by Accept header', () {
        setupUrl('https://example.com/resource');
        when(
          () => request.headers,
        ).thenReturn({'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8'});
        expect(request.getResourceType(false), ResourceType.image);
      });

      test('should detect stylesheet by Accept header', () {
        setupUrl('https://example.com/resource');
        when(() => request.headers).thenReturn({'accept': 'text/css,*/*;q=0.1'});
        expect(request.getResourceType(false), ResourceType.stylesheet);
      });

      test('should detect subdocument by Accept header', () {
        setupUrl('https://example.com/resource');
        when(() => request.headers).thenReturn({'Accept': 'text/html,application/xhtml+xml'});
        expect(request.getResourceType(false), ResourceType.subdocument);
      });

      test('should detect xmlHttpRequest by Accept header', () {
        setupUrl('https://example.com/resource');
        when(() => request.headers).thenReturn({'Accept': 'application/json, text/plain, */*'});
        expect(request.getResourceType(false), ResourceType.xmlHttpRequest);
      });

      test('should detect media by Accept header (video)', () {
        setupUrl('https://example.com/resource');
        when(() => request.headers).thenReturn({
          'Accept':
              'video/webm,video/ogg,video/*;q=0.9,application/ogg;q=0.7,audio/*;q=0.6,*/*;q=0.5',
        });
        expect(request.getResourceType(false), ResourceType.media);
      });

      test('should detect media by Accept header (audio)', () {
        setupUrl('https://example.com/resource');
        when(() => request.headers).thenReturn({'Accept': 'audio/webm,audio/ogg,audio/*;q=0.9'});
        expect(request.getResourceType(false), ResourceType.media);
      });

      test('should detect script by Accept header', () {
        setupUrl('https://example.com/resource');
        when(() => request.headers).thenReturn({'Accept': 'application/javascript,*/*'});
        expect(request.getResourceType(false), ResourceType.script);
      });

      test('should detect font by Accept header', () {
        setupUrl('https://example.com/resource');
        when(
          () => request.headers,
        ).thenReturn({'Accept': 'font/woff2;q=1.0,font/woff;q=0.9,*/*;q=0.8'});
        expect(request.getResourceType(false), ResourceType.font);
      });
    });

    test('should classify unknown extensionless requests with Accept */* as other', () {
      setupUrl('https://api.example/v1/ads');
      when(() => request.headers).thenReturn({'Accept': '*/*'});
      expect(request.getResourceType(false), ResourceType.other);
    });
  });
}
