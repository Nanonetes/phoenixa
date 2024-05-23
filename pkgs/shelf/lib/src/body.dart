import 'dart:convert';

// Shared Interface of Requests and Response
class Body {
  // Private Constructors
  Body._(this._stream, this.encoding, this.contentLength);

  // Instance Variables
  Stream<List<int>>? _stream;
  final Encoding? encoding;
  final int? contentLength;

  // Factory Constructors
  factory Body(Object? body, [Encoding? encoding]) {
    // Data is Body Type
    if (body is Body) return body;

    Stream<List<int>> stream;
    int? contentLength;

    // Null handling
    if (body == null) {
      contentLength = 0;
      stream = Stream.fromIterable([]);
    }

    // Body for String
    else if (body is String) {
      if (encoding == null) {
        var encoded = utf8.encode(body);
        if (!_isPlainAscii(encoded, body.length)) encoding = utf8;
        contentLength = encoded.length;
        stream = Stream.fromIterable([encoded]);
      } else {
        var encoded = encoding.encode(body);
        contentLength = encoded.length;
        stream = Stream.fromIterable([encoded]);
      }
    }

    // Body for List of integers
    else if (body is List<int>) {
      contentLength = body.length;
      stream = Stream.fromIterable([body]);
    }

    // Body for Lists
    else if (body is List) {
      contentLength = body.length;
      stream = Stream.value(body.cast());
    }

    // Body for a Stream which is a List of integers
    else if (body is Stream<List<int>>) {
      stream = body;
    }

    // Body for Untyped Stream
    else if (body is Stream) {
      stream = body.cast();
    }

    // Error handling
    else {
      throw ArgumentError(
          'Response body "$body" must be a body, String, List or Stream');
    }

    return Body._(stream, encoding, contentLength);
  }

  static bool _isPlainAscii(List<int> bytes, int codeUnits) {
    // Most non Ascii code units will produce multiple bytes and make
    // text longer

    if (bytes.length != codeUnits) return false;

    // Non-ascii code units between U+0080 and U+009F produce 8-bit characters
    // with the high bit set
    return bytes.every((byte) => byte & 0x80 == 0);
  }

  Stream<List<int>> read() {
    if (_stream == null) {
      throw StateError(
          'The "read" method can only be called once on a "shelf.Request/shelf.Response object"');
    }
    var stream = _stream!;
    _stream = null;
    return stream;
  }
}
