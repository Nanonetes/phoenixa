import 'package:collection/collection.dart';
import 'package:http_parser/http_parser.dart';

import 'util.dart';

final _emptyHeaders = Headers._empty();

// Unmodifiable, key-intensive header map
class Headers extends UnmodifiableMapView<String, List<String>> {
  // Private Constructors
  Headers._(Map<String, List<String>> values)
      : super(CaseInsensitiveMap.from(Map.fromEntries(values.entries
            .where((element) => element.value.isNotEmpty)
            .map((element) =>
                MapEntry(element.key, List.unmodifiable(element.value))))));

  Headers._empty() : super(const {});

  // Factory Constructors
  factory Headers.from(Map<String, List<String>>? values) {
    // No header
    if (values == null || values.isEmpty) {
      return _emptyHeaders;
    }

    // Header as a value
    else if (values is Headers) {
      return values;
    }

    // Common case
    else {
      return Headers._(values);
    }
  }

  factory Headers.empty() => _emptyHeaders;

  // Instance Variables
  late final Map<String, String> singleValues = UnmodifiableMapView(
    CaseInsensitiveMap.from(
      map((key, value) => MapEntry(key, joinHeaderValues(value)!)),
    ),
  );
}
