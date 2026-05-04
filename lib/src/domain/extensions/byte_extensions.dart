import 'dart:typed_data';

/// Extension methods for Uint8List to provide additional functionality for byte manipulation.
extension FilterByteExtensions on Uint8List {
  /// Checks if all bytes in the specified range are ASCII characters (0-127).
  bool isAsciiOnly(int start, int end) {
    for (var i = start; i < end; i++) {
      if (this[i] > 127) return false;
    }
    return true;
  }

  /// Creates a view of the byte list from the specified start index to the end index.
  Uint8List view([int start = 0, int? end]) {
    return Uint8List.sublistView(this, start, end);
  }

  /// Finds the index of the first occurrence of a line ending (CR or LF) in the list.
  ///
  /// Returns the index of the line ending if found, or -1 if not found.
  int indexOfLineEnd([int start = 0]) {
    for (var i = start; i < length; i++) {
      final byte = this[i];
      if (byte == 10 || byte == 13) return i;
    }
    return -1;
  }

  /// Converts a range of bytes in the list to an ASCII string.
  String getAsciiString(int start, int end) {
    return String.fromCharCodes(this, start, end);
  }
}
