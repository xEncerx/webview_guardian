import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// Extension on [WebResourceRequest] to determine [ResourceType] efficiently.
extension WebResourceRequestX on WebResourceRequest {
  /// Detects [ResourceType] of the request as quickly as possible.
  ResourceType getResourceType(bool isMainFrame) {
    // 0. Check for Main Frame
    if (isMainFrame) return ResourceType.document;

    final headers = this.headers;
    // 1. Heuristic by X-Requested-With header (commonly used for XHR/Fetch)
    if (headers != null) {
      final requestedWith = headers['X-Requested-With'] ?? headers['x-requested-with'];
      if (requestedWith != null) {
        if (requestedWith == 'XMLHttpRequest' || requestedWith == 'Fetch') {
          return ResourceType.xmlHttpRequest;
        }
      }
    }
    // 2. Heuristic by URL extension
    // Take only the path to avoid parsing domains and query parameters.
    final path = url.path;
    final pathLength = path.length;
    if (pathLength > 2) {
      var dotIndex = -1;
      // Search for the last dot from the end.
      // Limit search to 15 characters from the end (to avoid traversing long URLs without extensions)
      final limit = pathLength > 15 ? pathLength - 15 : 0;
      for (var i = pathLength - 1; i >= limit; i--) {
        final code = path.codeUnitAt(i);
        if (code == 0x2E /* '.' */ ) {
          dotIndex = i;
          break;
        }
        if (code == 0x2F /* '/' */ ) {
          // If we encounter '/', it's the end of the path segment, so no extension here.
          break;
        }
      }
      if (dotIndex != -1) {
        final extLength = pathLength - dotIndex - 1;
        // Bitwise OR with 0x20 converts ASCII uppercase letters to lowercase (A->a),
        // digits remain unaffected if we check specific codes.
        if (extLength == 2) {
          final c1 = path.codeUnitAt(dotIndex + 1) | 0x20;
          final c2 = path.codeUnitAt(dotIndex + 2) | 0x20;
          if (c1 == 0x6A && c2 == 0x73) return ResourceType.script; // js
          if (c1 == 0x74 && c2 == 0x73) return ResourceType.script; // ts
        } else if (extLength == 3) {
          final c1 = path.codeUnitAt(dotIndex + 1) | 0x20;
          final c2 = path.codeUnitAt(dotIndex + 2) | 0x20;
          final c3 = path.codeUnitAt(dotIndex + 3) | 0x20;
          if (c1 == 0x63 && c2 == 0x73 && c3 == 0x73) return ResourceType.stylesheet; // css
          if (c1 == 0x70 && c2 == 0x6E && c3 == 0x67) return ResourceType.image; // png
          if (c1 == 0x6A && c2 == 0x70 && c3 == 0x67) return ResourceType.image; // jpg
          if (c1 == 0x67 && c2 == 0x69 && c3 == 0x66) return ResourceType.image; // gif
          if (c1 == 0x73 && c2 == 0x76 && c3 == 0x67) return ResourceType.image; // svg
          if (c1 == 0x69 && c2 == 0x63 && c3 == 0x6F) return ResourceType.image; // ico
          if (c1 == 0x6D && c2 == 0x70 && c3 == 0x34) return ResourceType.media; // mp4
          if (c1 == 0x6D && c2 == 0x70 && c3 == 0x33) return ResourceType.media; // mp3
          if (c1 == 0x78 && c2 == 0x6D && c3 == 0x6C) return ResourceType.xmlHttpRequest; // xml
        } else if (extLength == 4) {
          final c1 = path.codeUnitAt(dotIndex + 1) | 0x20;
          final c2 = path.codeUnitAt(dotIndex + 2) | 0x20;
          final c3 = path.codeUnitAt(dotIndex + 3) | 0x20;
          final c4 = path.codeUnitAt(dotIndex + 4) | 0x20;
          if (c1 == 0x77 && c2 == 0x65 && c3 == 0x62 && c4 == 0x70) {
            return ResourceType.image; // webp
          }
          if (c1 == 0x6A && c2 == 0x70 && c3 == 0x65 && c4 == 0x67) {
            return ResourceType.image; // jpeg
          }
          if (c1 == 0x77 && c2 == 0x65 && c3 == 0x62 && c4 == 0x6D) {
            return ResourceType.media; // webm
          }
          if (c1 == 0x6D && c2 == 0x33 && c3 == 0x75 && c4 == 0x38) {
            return ResourceType.media; // m3u8
          }
          if (c1 == 0x6A && c2 == 0x73 && c3 == 0x6F && c4 == 0x6E) {
            return ResourceType.xmlHttpRequest; // json
          }
          if (c1 == 0x77 && c2 == 0x6F && c3 == 0x66 && c4 == 0x66) {
            return ResourceType.font; // woff
          }
          if (c1 == 0x68 && c2 == 0x74 && c3 == 0x6D && c4 == 0x6C) {
            return ResourceType.subdocument; // html
          }
        } else if (extLength == 5) {
          final c1 = path.codeUnitAt(dotIndex + 1) | 0x20;
          final c2 = path.codeUnitAt(dotIndex + 2) | 0x20;
          final c3 = path.codeUnitAt(dotIndex + 3) | 0x20;
          final c4 = path.codeUnitAt(dotIndex + 4) | 0x20;
          final c5 = path.codeUnitAt(dotIndex + 5) | 0x20;
          if (c1 == 0x77 && c2 == 0x6F && c3 == 0x66 && c4 == 0x66 && c5 == 0x32) {
            return ResourceType.font; // woff2
          }
        }
      }
    }
    // 3. Heuristic by Accept header (executed last)
    if (headers != null) {
      final accept = headers['Accept'] ?? headers['accept'];
      if (accept != null) {
        if (accept.contains('image/')) return ResourceType.image;
        if (accept.contains('text/css')) return ResourceType.stylesheet;
        if (accept.contains('text/html')) return ResourceType.subdocument;
        if (accept.contains('application/json')) return ResourceType.xmlHttpRequest;
        if (accept.contains('video/') || accept.contains('audio/')) {
          return ResourceType.media;
        }
        if (accept.contains('application/javascript') || accept.contains('text/javascript')) {
          return ResourceType.script;
        }
        if (accept.contains('font/')) return ResourceType.font;
      }
    }
    // Default value for everything else
    return ResourceType.subdocument;
  }
}
