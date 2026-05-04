import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Customization for the pull-to-refresh behavior and appearance in WebView.
@immutable
class WebViewPullToRefreshSettings {
  /// Creates a [WebViewPullToRefreshSettings] instance.
  const WebViewPullToRefreshSettings({
    this.color,
    this.backgroundColor,
    this.size,
    this.enabled = true,
  });

  /// Creates a [WebViewPullToRefreshSettings] from a JSON string.
  factory WebViewPullToRefreshSettings.fromJson(String source) =>
      WebViewPullToRefreshSettings.fromMap(json.decode(source) as Map<String, dynamic>);

  /// Creates a [WebViewPullToRefreshSettings] from a map.
  factory WebViewPullToRefreshSettings.fromMap(Map<String, dynamic> map) {
    return WebViewPullToRefreshSettings(
      color: map['color'] != null ? Color(map['color'] as int) : null,
      backgroundColor: map['backgroundColor'] != null ? Color(map['backgroundColor'] as int) : null,
      size: map['size'] != null ? map['size'] as int : null,
      enabled: map['enabled'] as bool,
    );
  }

  /// The color of the refresh indicator. Defaults to the theme's primary color.
  final Color? color;

  /// The background color of the refresh indicator. Defaults to the theme's surface color.
  final Color? backgroundColor;

  /// The size of the refresh indicator.
  final int? size;

  /// Whether pull-to-refresh is enabled. Defaults to true.
  final bool enabled;

  /// Creates a copy of this settings with the given fields replaced by the new values.
  WebViewPullToRefreshSettings copyWith({
    Color? color,
    Color? backgroundColor,
    int? size,
    bool? enabled,
  }) {
    return WebViewPullToRefreshSettings(
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      size: size ?? this.size,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Converts this settings to a map for serialization.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'color': color?.toARGB32(),
      'backgroundColor': backgroundColor?.toARGB32(),
      'size': size,
      'enabled': enabled,
    };
  }

  /// Converts this settings to a JSON string.
  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'WebViewPullToRefreshSettings(color: $color, backgroundColor: $backgroundColor, size: $size, enabled: $enabled)';
  }

  @override
  bool operator ==(covariant WebViewPullToRefreshSettings other) {
    if (identical(this, other)) return true;

    return other.color == color &&
        other.backgroundColor == backgroundColor &&
        other.size == size &&
        other.enabled == enabled;
  }

  @override
  int get hashCode {
    return color.hashCode ^ backgroundColor.hashCode ^ size.hashCode ^ enabled.hashCode;
  }
}

/// Mapping extension to convert between [PullToRefreshSettings] and [WebViewPullToRefreshSettings].
extension PullToRefreshSettingsMapper on WebViewPullToRefreshSettings {
  /// Converts this [WebViewPullToRefreshSettings] to a [PullToRefreshSettings] that can be used by the underlying web view.
  PullToRefreshSettings toPullToRefreshSettings() {
    return PullToRefreshSettings(
      color: color,
      backgroundColor: backgroundColor,
      size: PullToRefreshSize.fromValue(size),
      enabled: enabled,
    );
  }

  /// Creates a [WebViewPullToRefreshSettings] from a [PullToRefreshSettings].
  static WebViewPullToRefreshSettings fromPullToRefreshSettings(PullToRefreshSettings settings) {
    return WebViewPullToRefreshSettings(
      color: settings.color,
      backgroundColor: settings.backgroundColor,
      size: settings.size?.toValue(),
      enabled: settings.enabled ?? true,
    );
  }
}
