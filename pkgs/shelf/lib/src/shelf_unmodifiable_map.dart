import 'dart:collection';

import 'package:http_parser/http_parser.dart';

class ShelfUnmodifiableMap extends UnmodifiableMapView<String, Object> {
  // if return values are already lowercase, its true
  final bool _ignoreKeyCase;

  // Factory Constructor
  factory ShelfUnmodifiableMap(
    Map<String, Object>? source, {
    bool ignoreKeyCase = false,
  }) {
    if (source is ShelfUnmodifiableMap &&
        (!ignoreKeyCase || source._ignoreKeyCase)) {
      return source;
    }

    if (source == null || source.isEmpty) {
      return const _EmptyShelfUnmodifiableMap();
    }

    if (ignoreKeyCase) {
      source = CaseInsensitiveMap<Object>.from(source);
    } else {
      source = Map<String, Object>.from(source);
    }

    return ShelfUnmodifiableMap._(source, ignoreKeyCase);
  }

  // Factory Constructor to return Empty ShelfUnmodifiableMap
  const factory ShelfUnmodifiableMap.empty() = _EmptyShelfUnmodifiableMap;

  // Private Constructor
  ShelfUnmodifiableMap._(super.source, this._ignoreKeyCase);
}

/// Const implementation of an empty ShelfUnmodifiableMap
class _EmptyShelfUnmodifiableMap extends MapView<String, Object>
    implements ShelfUnmodifiableMap {
  @override
  bool get _ignoreKeyCase => true;

  const _EmptyShelfUnmodifiableMap() : super(const <String, Object>{});

  @override
  void operator []=(String key, Object value) => super[key] = const Object();

  @override
  void addAll(Map<String, Object> other) => super.addAll({});

  @override
  Object putIfAbsent(String key, Object Function() ifAbsent) =>
      super..putIfAbsent(key, () => const Object());

  @override
  Object remove(Object? key) =>
      throw UnsupportedError('Cannot modify unmodifiable map');
}
