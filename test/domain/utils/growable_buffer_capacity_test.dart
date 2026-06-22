import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_guardian/src/domain/utils/binary_io.dart';
import 'package:webview_guardian/src/domain/utils/growable_buffers.dart';

void main() {
  group('BinaryWriter', () {
    test('starts with small capacity and returns exact written bytes', () {
      final writer = BinaryWriter();

      expect(writer.capacity, lessThanOrEqualTo(BufferCapacityPolicy.initialByteCapacity));

      writer.writeUint8(7);

      final bytes = writer.toBytes();
      expect(bytes, [7]);
      expect(bytes.length, 1);
    });

    test('grows when writes exceed the initial capacity', () {
      final writer = BinaryWriter();
      final initialCapacity = writer.capacity;
      final payload = Uint8List.fromList(List.generate(initialCapacity + 1, (i) => i & 0xFF));

      writer.writeBytes(payload);

      expect(writer.capacity, greaterThan(initialCapacity));
      expect(writer.toBytes(), payload);
    });
  });

  group('Uint32ListBuilder', () {
    test('starts with small capacity and returns exact written words', () {
      final builder = Uint32ListBuilder();

      expect(builder.capacity, lessThanOrEqualTo(BufferCapacityPolicy.initialUint32Capacity));

      builder.add(42);

      final words = builder.toList();
      expect(words, [42]);
      expect(words.length, 1);
    });

    test('grows when writes exceed the initial capacity', () {
      final builder = Uint32ListBuilder();
      final initialCapacity = builder.capacity;

      for (var i = 0; i <= initialCapacity; i++) {
        builder.add(i);
      }

      expect(builder.capacity, greaterThan(initialCapacity));
      expect(builder.toList(), List<int>.generate(initialCapacity + 1, (i) => i));
    });
  });
}
