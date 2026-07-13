import 'package:meta/meta.dart';

@immutable
/// Represents a subscription to a remote filter list.
class FilterSubscription {
  /// Creates a [FilterSubscription] instance.
  const FilterSubscription({
    required this.url,
    this.updateInterval,
  });

  /// The URL from which the filter list is fetched.
  final String url;

  /// The interval at which the filter list should be updated.
  final Duration? updateInterval;

  /// Creates a copy of this [FilterSubscription] but with the given fields replaced with the new values.
  FilterSubscription copyWith({
    String? id,
    String? url,
    String? lastEtag,
    Duration? updateInterval,
  }) {
    return FilterSubscription(
      url: url ?? this.url,
      updateInterval: updateInterval ?? this.updateInterval,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterSubscription &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          updateInterval == other.updateInterval;

  @override
  int get hashCode => url.hashCode ^ updateInterval.hashCode;
}
