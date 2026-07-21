import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'benchmark_support.dart';

abstract base class BenchmarkSuite<T> {
  const BenchmarkSuite(this.runner);

  final BenchmarkRunner runner;

  FutureOr<T> run();
}

final class BenchmarkFixtures {
  const BenchmarkFixtures({
    required this.small,
    required this.medium,
    required this.large,
    required this.hosts,
    required this.controlled,
    required this.domainList,
    required this.hashes,
  });

  factory BenchmarkFixtures.load() {
    final directory = Directory('benchmark/fixtures/noads_ru');
    checkBenchmarkInvariant(directory.existsSync(), 'Run benchmarks from the package root.');
    final bytes = <String, Uint8List>{};
    final hashes = <String, String>{};
    final manifest = jsonDecode(File('${directory.path}/SOURCE.json').readAsStringSync());
    final files = (manifest as Map<String, dynamic>)['files']! as List<dynamic>;
    for (final entry in files.cast<Map<String, dynamic>>()) {
      final path = entry['path']! as String;
      final data = File('${directory.path}/$path').readAsBytesSync();
      final hash = sha256.convert(data).toString();
      checkBenchmarkInvariant(data.length == entry['bytes'], 'Fixture size mismatch for $path.');
      checkBenchmarkInvariant(hash == entry['sha256'], 'Fixture hash mismatch for $path.');
      bytes[path] = data;
      hashes[path] = hash;
    }
    final controlled = Uint8List.fromList(utf8.encode(_controlledFilters()));
    final domainList = Uint8List.fromList(
      utf8.encode('ads.bench.invalid\ntracker.bench.invalid\nmedia.bench.invalid\n'),
    );
    hashes
      ..['generated/controlled-filters'] = sha256.convert(controlled).toString()
      ..['generated/domain-list'] = sha256.convert(domainList).toString();
    return BenchmarkFixtures(
      small: bytes['ads_list.txt']!,
      medium: bytes['ads_list_extended.txt']!,
      large: bytes['ads_list_extended_plus.txt']!,
      hosts: bytes['blocker.txt']!,
      controlled: controlled,
      domainList: domainList,
      hashes: hashes,
    );
  }

  final Uint8List small;
  final Uint8List medium;
  final Uint8List large;
  final Uint8List hosts;
  final Uint8List controlled;
  final Uint8List domainList;
  final Map<String, String> hashes;
}

String _controlledFilters() {
  final buffer = StringBuffer(r'''
[Adblock Plus 2.0]
||bench-trie.invalid^
bench-token-unique
||bench-priority.invalid^$important
@@||bench-priority.invalid^$important
b~m
bench.example##.bench-domain
bench.example##.bench-duplicate
##.bench-duplicate
bench.example##.bench-excepted
bench.example#@#.bench-excepted
bench.example#$#body { --guardian-benchmark: 1; }
bench.example#%#//scriptlet('remove-attr', 'data-ad')
bench.example#%#//scriptlet('nano-sib', 'alias-extensionless')
bench.example#%#//scriptlet('remove-class.js', 'canonical-explicit')
bench.example#%#//scriptlet('ra.js', 'alias-explicit')
''');
  for (var i = 0; i < 3005; i++) {
    buffer.writeln('##.bench-generic-$i');
  }
  return buffer.toString();
}

void checkBenchmarkInvariant(bool condition, String message) {
  if (!condition) throw StateError(message);
}
