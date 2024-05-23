import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:http_parser/http_parser.dart';

import 'body.dart';
import 'headers.dart';
import 'shelf_unmodifiable_map.dart';
import 'util.dart';

Body extractBody(Message message) => message._body;

// Default Header for no body or specific header
final _defaultHeaders = Headers.from({
  'content-length': ['0'],
});

/// Shared logic between Request and Response
abstract class Message {
  /// Message Constructor
  Message(
    Object? body, {
    Encoding? encoding,
    Map<String, Object>? headers,
    Map<String, Object>? context,
  }) : this._withBody(
          Body(body, encoding),
          headers,
          context,
        );

  // Named Private Constructors
  Message._withBody(
      Body body, Map<String, Object>? headers, Map<String, Object>? context)
      : this._withHeadersAll(
          body,
          Headers.from(_adjustHeaders(expandToHeadersAll(headers), body)),
          context,
        );

  Message._withHeadersAll(
      Body body, Headers headers, Map<String, Object>? context)
      : _body = body,
        _headers = headers,
        context = ShelfUnmodifiableMap(context, ignoreKeyCase: false);

  /// Instance Variables

  final Headers _headers;
  // Header getter for single value
  Map<String, String> get headers => _headers.singleValues;
  // Header getter for multiple values
  Map<String, List<String>> get headersAll => _headers;

  /// Context to be used by middlewares and handlers
  /// for requests, this is used to pass data to inner middleware and handlers
  /// for responses, its used to pass data to outer middleware or handlers.
  final Map<String, Object> context;

  // Streaming Body
  final Body _body;

  // If true, stream returned by [read] wont emit any bytes or buffers.
  //
  // This may have false negatives[The code saying "this is NOT empty" when it
  // actually is (possible).]
  // But it wont have false positives[The code saying "this IS empty" when its
  // not (impossible)]
  bool get isEmpty => _body.contentLength == 0;

  /// Methods

  // Content Length Variable and method
  int? get contentLength {
    if (_contentLengthCache != null) return _contentLengthCache;
    if (!headers.containsKey('content-length')) return null;
    _contentLengthCache = int.parse(headers['content-length']!);
    return _contentLengthCache;
  }

  int? _contentLengthCache;

  // Cached parsed version pf Content-Type Header
  MediaType? get _contentType {
    if (_contentTypeCache != null) return _contentTypeCache;
    final contentTypeValue = headers['content-type'];
    if (contentTypeValue == null) return null;
    return _contentTypeCache = MediaType.parse(contentTypeValue);
  }

  MediaType? _contentTypeCache;

  // MIME Type
  String? get mimeType {
    var contentType = _contentType;
    if (contentType == null) return null;
    return contentType.mimeType;
  }

  // Encoding of message body, passed by charset parameter of Content-Type
  // Header.
  Encoding? get encoding {
    var contentType = _contentType;
    if (contentType == null) return null;
    if (!contentType.parameters.containsKey('charset')) return null;
    return Encoding.getByName(contentType.parameters['charset']);
  }

  // Returns Stream, can be called only once..
  Stream<List<int>> read() => _body.read();

  // Returns [Future] containing body as String.
  // It calls .read() internally, which can only be called once
  Future<String> readAsString([Encoding? encoding]) {
    encoding ??= this.encoding ?? utf8;
    return encoding.decodeStream(read());
  }

  // Creates new message by copying existing values and applying specified
  // changes
  Message change({
    Map<String, String> headers,
    Map<String, Object> context,
    Object? body,
  });

  // Add encoding and content-length to headers, returns a new map without
  // modifying headers
  static Map<String, List<String>> _adjustHeaders(
    Map<String, List<String>>? headers,
    Body body,
  ) {
    var sameEncoding = _sameEncoding(headers, body);
    if (sameEncoding) {
      if (body.contentLength == null ||
          findHeader(headers, 'content-length') == '${body.contentLength}') {
        return headers ?? Headers.empty();
      } else if (body.contentLength == 0 &&
          (headers == null || headers.isEmpty)) {
        return _defaultHeaders;
      }
    }

    var newHeaders = headers == null
        ? CaseInsensitiveMap<List<String>>()
        : CaseInsensitiveMap<List<String>>.from(headers);

    if (!sameEncoding) {
      if (newHeaders['content-type'] == null) {
        newHeaders['content-type'] = [
          'application/octet-stream; charset=${body.encoding!.name}'
        ];
      } else {
        final contentType =
            MediaType.parse(joinHeaderValues(newHeaders['content-type'])!)
                .change(parameters: {'charset': body.encoding!.name});
        newHeaders['content-type'] = [contentType.toString()];
      }
    }

    final explicitOverrideOfZeroLength = body.contentLength == 0 &&
        findHeader(headers, 'content-length') != null;

    if (body.contentLength != null && !explicitOverrideOfZeroLength) {
      final coding = joinHeaderValues(newHeaders['transfer-encoding']);
      if (coding == null || equalsIgnoreAsciiCase(coding, 'identity')) {
        newHeaders['content-length'] = [body.contentLength.toString()];
      }
    }

    return newHeaders;
  }

  //
  static bool _sameEncoding(Map<String, List<String>?>? headers, Body body) {
    if (body.encoding == null) return true;

    var contentType = findHeader(headers, 'content-type');
    if (contentType == null) return false;

    var charset = MediaType.parse(contentType).parameters['charset'];
    return Encoding.getByName(charset) == body.encoding;
  }
}
