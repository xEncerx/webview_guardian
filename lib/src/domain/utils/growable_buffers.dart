import 'dart:typed_data';

/// Capacity defaults and growth logic for buffers that are usually small but may grow large.
abstract final class BufferCapacityPolicy {
  /// Initial byte capacity for binary serialization buffers.
  static const int initialByteCapacity = 256;

  /// Initial word capacity for flattened trie buffers.
  static const int initialUint32Capacity = 64;

  /// Returns a doubled capacity that can hold [requiredCapacity].
  static int grow(int currentCapacity, int requiredCapacity) {
    var newCapacity = currentCapacity <= 0 ? 1 : currentCapacity;
    while (newCapacity < requiredCapacity) {
      newCapacity *= 2;
    }
    return newCapacity;
  }
}

/// Growable [Uint32List] builder that keeps appends amortized O(1).
class Uint32ListBuilder {
  /// Creates a builder with a small initial capacity by default.
  Uint32ListBuilder([int initialCapacity = BufferCapacityPolicy.initialUint32Capacity])
    : _buffer = Uint32List(initialCapacity <= 0 ? 1 : initialCapacity);

  Uint32List _buffer;
  int _length = 0;

  /// Number of written words.
  int get length => _length;

  /// Current allocated word capacity.
  int get capacity => _buffer.length;

  /// Appends [value] to the buffer.
  void add(int value) {
    _ensureCapacity(_length + 1);
    _buffer[_length++] = value;
  }

  /// Replaces the written word at [index].
  void set(int index, int value) {
    _buffer[index] = value;
  }

  /// Returns a view over the written words only.
  Uint32List toList() {
    return Uint32List.sublistView(_buffer, 0, _length);
  }

  void _ensureCapacity(int requiredCapacity) {
    if (requiredCapacity <= _buffer.length) return;

    final newBuffer = Uint32List(
      BufferCapacityPolicy.grow(_buffer.length, requiredCapacity),
    )..setRange(0, _length, _buffer);
    _buffer = newBuffer;
  }
}
