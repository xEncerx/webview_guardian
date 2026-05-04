/// Represents the final action to be taken for an intercepted network request.
sealed class FilterDecision {
  const FilterDecision();
}

/// Indicates that the request did not match any blocking rules and should proceed.
final class Allow extends FilterDecision {
  /// Creates an [Allow] instance.
  const Allow();
}

/// Indicates that the request matched a blocking rule and must be aborted.
final class Block extends FilterDecision {
  /// Creates a [Block] instance.
  const Block();
}
