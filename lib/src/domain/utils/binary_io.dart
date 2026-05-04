import 'dart:typed_data';

import 'package:webview_guardian/src/domain/entities/resource_type.dart';
import 'package:webview_guardian/src/domain/extensions/byte_extensions.dart';
import 'package:webview_guardian/src/domain/utils/utf8.dart';

/// A simple binary writer for serializing data in a compact format.
class BinaryWriter {
  Uint8List _buffer = Uint8List(1024 * 1024); // Start with 1MB
  late ByteData _data = ByteData.sublistView(_buffer);
  int _offset = 0;

  static const Endian _endian = Endian.little;

  void _ensureCapacity(int needed) {
    if (_offset + needed > _buffer.length) {
      var newSize = _buffer.length * 2;
      while (_offset + needed > newSize) {
        newSize *= 2;
      }
      final newBuffer = Uint8List(newSize)..setRange(0, _offset, _buffer);
      _buffer = newBuffer;
      _data = ByteData.sublistView(_buffer);
    }
  }

  /// Writes an unsigned 8-bit integer to the buffer.
  void writeUint8(int value) {
    _ensureCapacity(1);
    _data.setUint8(_offset, value);
    _offset += 1;
  }

  /// Writes a signed 32-bit integer to the buffer.
  void writeInt32(int value) {
    _ensureCapacity(4);
    _data.setInt32(_offset, value, _endian);
    _offset += 4;
  }

  /// Writes a signed 64-bit integer to the buffer.
  void writeInt64(int value) {
    _ensureCapacity(8);
    _data.setInt64(_offset, value, _endian);
    _offset += 8;
  }

  /// Writes a boolean value as a single byte (1 for true, 0 for false).
  void writeBool(bool value) {
    writeUint8(value ? 1 : 0);
  }

  /// Writes a UTF-8 encoded string to the buffer, prefixed with its length as a 32-bit integer.
  void writeString(String value) {
    if (value.isEmpty) {
      writeInt32(0);
      return;
    }

    // Reserve space for the length prefix
    _ensureCapacity(4);
    final lenOffset = _offset;
    _offset += 4;

    final maxBytes = Utf8.getMaxLength(value);
    _ensureCapacity(maxBytes);

    final bytesWritten = Utf8.encode(value, _buffer, _offset);

    // Patch the actual written length into the prefix
    _data.setInt32(lenOffset, bytesWritten, _endian);
    _offset += bytesWritten;
  }

  /// Writes a nullable string. First writes a boolean indicating presence, then the string if present.
  void writeNullableString(String? value) {
    writeBool(value != null);
    if (value != null) {
      writeString(value);
    }
  }

  /// Writes a nullable set of strings. First writes a boolean indicating presence, then the count and strings if present.
  void writeNullableStringSet(Set<String>? value) {
    writeBool(value != null);
    if (value != null) {
      writeInt32(value.length);
      value.forEach(writeString);
    }
  }

  /// Writes a nullable list of strings. First writes a boolean indicating presence, then the count and strings if present.
  void writeNullableStringList(List<String>? value) {
    writeBool(value != null);
    if (value != null) {
      writeInt32(value.length);
      value.forEach(writeString);
    }
  }

  /// Writes a list of strings. First writes the count as a 32-bit integer, then each string.
  void writeStringList(List<String> value) {
    writeInt32(value.length);
    value.forEach(writeString);
  }

  /// Writes a set of [ResourceType] values. First writes the count as an unsigned 8-bit integer, then each value as its index.
  void writeResourceTypes(Set<ResourceType> types) {
    writeUint8(types.length);
    for (final type in types) {
      writeUint8(type.index);
    }
  }

  /// Writes a list of unsigned 32-bit integers. First aligns the offset to 4 bytes, then writes the count and the integers.
  void writeUint32List(Uint32List list) {
    // 1. Align offset to 4 bytes for zero-copy sublistView on read
    final padding = (4 - (_offset % 4)) % 4;
    for (var i = 0; i < padding; i++) {
      writeUint8(0);
    }

    writeInt32(list.length);

    final byteLength = list.length * 4;
    _ensureCapacity(byteLength);

    // Convert to bytes with same endianness
    final listBytes = Uint8List.sublistView(list);
    // If the system is little endian (which almost all are) and we use little, direct copy works.
    if (Endian.host == _endian) {
      _buffer.setRange(_offset, _offset + byteLength, listBytes);
    } else {
      // Slow path for big-endian machines
      for (var i = 0; i < list.length; i++) {
        _data.setUint32(_offset + (i * 4), list[i], _endian);
      }
    }
    _offset += byteLength;
  }

  /// Writes raw bytes to the buffer.
  void writeBytes(Uint8List value) {
    _ensureCapacity(value.length);
    _buffer.setRange(_offset, _offset + value.length, value);
    _offset += value.length;
  }

  /// Returns the written data as a [Uint8List], slicing the internal buffer to the actual data length.
  Uint8List toBytes() => _buffer.view(0, _offset);
}

/// A simple binary reader for deserializing data in the format written by [BinaryWriter].
class BinaryReader {
  /// Creates a [BinaryReader] instance.
  BinaryReader(this._buffer) : _data = ByteData.sublistView(_buffer);

  final Uint8List _buffer;
  final ByteData _data;
  int _offset = 0;

  static const Endian _endian = Endian.little;

  /// Reads an unsigned 8-bit integer from the buffer.
  int readUint8() {
    final value = _data.getUint8(_offset);
    _offset += 1;
    return value;
  }

  /// Reads a signed 32-bit integer from the buffer.
  int readInt32() {
    final value = _data.getInt32(_offset, _endian);
    _offset += 4;
    return value;
  }

  /// Reads a signed 64-bit integer from the buffer.
  int readInt64() {
    final value = _data.getInt64(_offset, _endian);
    _offset += 8;
    return value;
  }

  /// Reads a boolean value that was stored as a single byte (1 for true, 0 for false).
  bool readBool() {
    return readUint8() == 1;
  }

  /// Reads a UTF-8 encoded string from the buffer, first reading its length as a 32-bit integer.
  String readString() {
    final length = readInt32();
    if (length == 0) return '';
    final result = Utf8.decode(_buffer, _offset, length);
    _offset += length;
    return result;
  }

  /// Reads a nullable string. First reads a boolean indicating presence, then the string if present.
  String? readNullableString() {
    return readBool() ? readString() : null;
  }

  /// Reads a nullable set of strings. First reads a boolean indicating presence, then the count and strings if present.
  Set<String>? readNullableStringSet() {
    if (!readBool()) return null;
    final length = readInt32();
    final set = <String>{};
    for (var i = 0; i < length; i++) {
      set.add(readString());
    }
    return set;
  }

  /// Reads a nullable list of strings. First reads a boolean indicating presence, then the count and strings if present.
  List<String>? readNullableStringList() {
    if (!readBool()) return null;
    final length = readInt32();
    final list = <String>[];
    for (var i = 0; i < length; i++) {
      list.add(readString());
    }
    return list;
  }

  /// Reads a list of strings. First reads the count as a 32-bit integer, then each string.
  List<String> readStringList() {
    final length = readInt32();
    final list = <String>[];
    for (var i = 0; i < length; i++) {
      list.add(readString());
    }
    return list;
  }

  /// Reads a set of [ResourceType] values. First reads the count as an unsigned 8-bit integer, then each value as its index.
  Set<ResourceType> readResourceTypes() {
    final length = readUint8();
    final set = <ResourceType>{};
    for (var i = 0; i < length; i++) {
      set.add(ResourceType.values[readUint8()]);
    }
    return set;
  }

  /// Reads a list of unsigned 32-bit integers. First aligns the offset to 4 bytes, then reads the count and the integers.
  Uint32List readUint32List() {
    // 1. Consume padding to align offset to 4 bytes
    final padding = (4 - (_offset % 4)) % 4;
    _offset += padding;

    final length = readInt32();
    if (length == 0) return Uint32List(0);

    final byteLength = length * 4;

    Uint32List result;
    if (Endian.host == _endian) {
      result = Uint32List.sublistView(_buffer, _offset, _offset + byteLength);
    } else {
      // Needs copy for endian conversion
      result = Uint32List(length);
      for (var i = 0; i < length; i++) {
        result[i] = _data.getUint32(_offset + (i * 4), _endian);
      }
    }

    _offset += byteLength;
    return result;
  }

  /// Reads remaining bytes from the buffer.
  Uint8List readRemainingBytes() {
    final remaining = _buffer.length - _offset;
    if (remaining == 0) return Uint8List(0);
    final bytes = _buffer.view(_offset);
    _offset = _buffer.length;
    return bytes;
  }
}
