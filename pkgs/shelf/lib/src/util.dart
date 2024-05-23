import 'dart:async';

import 'package:collection/collection.dart';
import 'package:phoenixa/src/shelf_unmodifiable_map.dart';

void catchTopLevelError(void Function() callback,
    void Function(dynamic error, StackTrace) onError) {
  if (Zone.current.inSameErrorZone(Zone.root)) {
    return runZonedGuarded(callback, onError);
  } else {
    return callback();
  }
}

// for same keys in original and updated Map, values from Updated is used.
Map<K, V> updateMap<K, V>(Map<K, V> original, Map<K, V?>? updates) {
  if (updates == null || updates.isEmpty) return original;

  final map = Map.of(original);

  for (var entry in updates.entries) {
    final value = entry.value;
    if (value == null) {
      map.remove(entry.key);
    } else {
      map[entry.key] = value;
    }
  }

  return map;
}

/// Adds header with [name] and [value] to [headers], which  may be null
/// Returns new map without modifying [headers]
Map<String, Object> addHeader(
  Map<String, Object>? headers,
  String name,
  String value,
) {
  headers = headers == null ? {} : Map.from(headers);
  headers[name] = value;
  return headers;
}

/// Remove the header with case-insensitive name [name]
/// Returns new map without modifying headers
Map<String, Object>? removeHeader(
  Map<String, Object>? headers,
  String name,
) {
  headers = headers == null ? {} : Map.from(headers);
  headers.removeWhere((header, value) => equalsIgnoreAsciiCase(header, name));
  return headers;
}

/// Returns the header with the given [name] in [headers].
String? findHeader(Map<String, List<String>?>? headers, String name) {
  if (headers == null || headers.isEmpty) return null;
  if (headers is ShelfUnmodifiableMap) {
    return joinHeaderValues(headers[name]);
  }

  for (var key in headers.keys) {
    if (equalsIgnoreAsciiCase(key, name)) {
      return joinHeaderValues(headers[key]);
    }
  }

  return null;
}

// Update Headers
Map<String, List<String>> updateHeaders(
  Map<String, List<String>> initialHeaders,
  Map<String, Object?>? changeHeaders,
) {
  return updateMap(initialHeaders, _expandToHeadersAll(changeHeaders));
}

Map<String, List<String>?>? _expandToHeadersAll(
  Map<String, Object?>? headers,
) {
  if (headers is Map<String, List<String>>) return headers;
  if (headers == null || headers.isEmpty) return null;

  return Map.fromEntries(headers.entries.map((element) {
    final value = element.value;
    return MapEntry(
        element.key, value == null ? null : expandHeaderValue(value));
  }));
}

Map<String, List<String>>? expandToHeadersAll(
  Map<String, Object>? headers,
) {
  if (headers is Map<String, List<String>>) return headers;
  if (headers == null || headers.isEmpty) return null;

  return Map.fromEntries(headers.entries.map((element) {
    return MapEntry(element.key, expandHeaderValue(element.value));
  }));
}

List<String> expandHeaderValue(Object value) {
  if (value is String) {
    return [value];
  } else if (value is List<String>) {
    return value;
  } else if ((value as dynamic) == null) {
    return const [];
  } else {
    throw ArgumentError('Expected String or List<String>, got: `$value`.');
  }
}

// Multiple Header Values are joined with commas
String? joinHeaderValues(List<String>? values) {
  if (values == null) return null;
  if (values.isEmpty) return '';
  if (values.length == 1) return values.single;
  return values.join(',');
}
