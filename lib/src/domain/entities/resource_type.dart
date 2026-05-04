/// Defines the type of a network resource.
enum ResourceType {
  /// A subdocument resource, such as an iframe.
  subdocument,

  /// The main document resource.
  document,

  /// An image resource.
  image,

  /// A cascading stylesheet resource.
  stylesheet,

  /// A JavaScript resource.
  script,

  /// A web font resource.
  font,

  /// An XMLHttpRequest or fetch resource.
  xmlHttpRequest,

  /// A media resource, such as audio or video.
  media,

  /// A WebSocket connection resource.
  websocket,

  /// Any other type of resource not explicitly classified.
  other,
}
