import 'dart:convert';
import 'dart:typed_data';

import 'package:webview_guardian/src/domain/extensions/extensions.dart';

/// Zero-allocation UTF-8 encoding and decoding utilities.
class Utf8 {
  const Utf8._();

  /// Calculates the maximum possible byte length for a UTF-8 encoded string.
  ///
  /// Worst case: each UTF-16 code unit -> 3 UTF-8 bytes.
  static int getMaxLength(String v) => v.length * 3;

  /// Encodes [v] as UTF-8 directly into [buffer] at [offset].
  ///
  /// Returns the number of bytes written.
  ///
  /// Bounds are guaranteed by the caller via ensuring [buffer] has at least
  /// [getMaxLength] bytes available from [offset].
  @pragma('vm:unsafe:no-bounds-checks')
  static int encode(String v, Uint8List buffer, int offset) {
    var pos = offset;
    for (var i = 0; i < v.length; i++) {
      var c = v.codeUnitAt(i);
      if (c <= 0x7F) {
        buffer[pos++] = c;
      } else if (c <= 0x7FF) {
        buffer[pos++] = 0xC0 | (c >> 6);
        buffer[pos++] = 0x80 | (c & 0x3F);
      } else if (c >= 0xD800 && c <= 0xDBFF) {
        // High surrogate — combine with next low surrogate for U+10000..U+10FFFF.
        final hi = c;
        if (++i < v.length) {
          final lo = v.codeUnitAt(i);
          if (lo >= 0xDC00 && lo <= 0xDFFF) {
            c = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
            buffer[pos++] = 0xF0 | (c >> 18);
            buffer[pos++] = 0x80 | ((c >> 12) & 0x3F);
            buffer[pos++] = 0x80 | ((c >> 6) & 0x3F);
            buffer[pos++] = 0x80 | (c & 0x3F);
          } else {
            // Unpaired high surrogate — encode replacement char U+FFFD.
            buffer[pos++] = 0xEF;
            buffer[pos++] = 0xBF;
            buffer[pos++] = 0xBD;
            i--; // re-process lo
          }
        } else {
          buffer[pos++] = 0xEF;
          buffer[pos++] = 0xBF;
          buffer[pos++] = 0xBD;
        }
      } else if (c >= 0xDC00 && c <= 0xDFFF) {
        // Unpaired low surrogate.
        buffer[pos++] = 0xEF;
        buffer[pos++] = 0xBF;
        buffer[pos++] = 0xBD;
      } else {
        buffer[pos++] = 0xE0 | (c >> 12);
        buffer[pos++] = 0x80 | ((c >> 6) & 0x3F);
        buffer[pos++] = 0x80 | (c & 0x3F);
      }
    }
    return pos - offset;
  }

  /// Decode [len] bytes at [offset] as UTF-8.
  ///
  /// Fast path: if all bytes are ASCII, build string directly
  /// (skips UTF-8 validation, ~20% faster for short ASCII strings).
  @pragma('vm:unsafe:no-bounds-checks')
  static String decode(Uint8List bytes, int offset, int len) {
    var ascii = true;
    for (var i = 0; i < len; i++) {
      if (bytes[offset + i] > 0x7F) {
        ascii = false;
        break;
      }
    }
    if (ascii) {
      return String.fromCharCodes(bytes, offset, offset + len);
    }
    return utf8.decode(bytes.view(offset, offset + len));
  }
}
