import 'dart:convert';

import 'package:http_parser/http_parser.dart';
import 'package:stream_channel/stream_channel.dart';

import 'hijack_exception.dart';
import 'message.dart';
import 'util.dart';

/// HTTP Request
class Request extends Message {
  /// Instance Variables
  final Uri url;
  final String method;
  final String handlerPath;
  final String protocolVersion;
  final Uri requestedUri;

  /// Callback wrapper for hijacking this request
  /// Will be null if the instance of request cant be hijacked
  final _OnHijack? _onHijack;
  bool get canHijack => _onHijack != null && !_onHijack!.called;

  /// If its non null and requested resource hasn't been modified since
  /// this date and time, server should return a 304 not modified.
  ///
  /// This is parsed from if-modified-since header in headers. if they don't
  /// have a if-modified-since then it will be null
  ///
  /// It will throw `format exception` if incoming request has an invalid
  /// if-modified-since header.
  DateTime? get ifModifiedSince {
    if (_ifModifiedSinceCache != null) return _ifModifiedSinceCache;
    if (!headers.containsKey('if-modified-since')) return null;
    _ifModifiedSinceCache = parseHttpDate(headers['if-modified-since']!);
    return _ifModifiedSinceCache;
  }

  DateTime? _ifModifiedSinceCache;

  /// Constructor - Creates a request object
  ///
  /// [handlerPath] must be rootRelative
  /// [url]'s path must be fully relative. It must have same query parameters
  /// as [requestedUri].
  /// [handlerPath] and [url] must combine to be the path component of
  /// [requestedUri].
  /// If only one is passed, other would be inferred.
  ///
  /// The default value for [protocolVersion] is '1.1'.
  ///
  /// ## 'onHijack'
  ///
  /// [onHijack] allows handlers to take control of the underlying socket
  /// for the request. It should be passed by the adapters that can provide
  /// access to the bidirectional socket underlying the HTTP connection stream.
  ///
  /// The [onHijack] callback will only be called once per request. It will be
  /// passed another callback which takes a byte [StreamChannel]. [onHijack]
  /// must pass the channel for the connection stream to this callback, although
  /// it may do so asynchronously.
  ///
  /// If a request is hijacked, the adapter should expect to receive a
  /// [HijackException] from the handler. This is a special exception used to
  /// indicate that hijacking has occurred. The adapter should avoid either
  /// sending a response or notifying the user of an error if a
  /// [HijackException] is caught.
  ///
  /// An adapter can check whether a request was hijacked using [canHijack],
  /// which will be 'false' for a hijacked request. The adapter may throw an
  /// error if a [hijackException] is received for a non-hijacked request, or if
  /// no [HijackException] is received for a hijacked request.
  Request(
    String method,
    Uri requestedUri, {
    String? protocolVersion,
    Map<String, Object>? headers,
    String? handlerPath,
    Uri? url,
    Object? body,
    Encoding? encoding,
    Map<String, Object>? context,
    void Function(void Function(StreamChannel<List<int>>))? onHijack,
  }) : this._(method, requestedUri,
            protocolVersion: protocolVersion,
            headers: headers,
            url: url,
            handlerPath: handlerPath,
            body: body,
            encoding: encoding,
            context: context,
            onHijack: onHijack == null ? null : _OnHijack(onHijack));

  /// Private Constructor
  /// Has the same signature as [Request.new] except that accepts [onHijack] as
  /// [_onHijack].
  ///
  /// Any [Request] created by calling [change] will pass [_onHijack] from the
  /// source [Request] to ensure that [hijack] can only be called once, even
  /// from a changed [Request].
  Request._(
    this.method,
    this.requestedUri, {
    String? protocolVersion,
    Map<String, Object>? headers,
    String? handlerPath,
    Uri? url,
    Object? body,
    Encoding? encoding,
    Map<String, Object>? context,
    _OnHijack? onHijack,
  })  : protocolVersion = protocolVersion ?? '1.1',
        url = _computeUrl(requestedUri, handlerPath, url),
        handlerPath = _computeHandlerPath(requestedUri, handlerPath, url),
        _onHijack = onHijack,
        super(body, encoding: encoding, headers: headers, context: context) {
    if (method.isEmpty) {
      throw ArgumentError.value(method, 'method', 'cannot be empty');
    }

    try {
      // Trigger URI parsing methods that may throw format exception (in Request
      // constructor or in handlers / routing).
      requestedUri.pathSegments;
      requestedUri.queryParametersAll;
    } on FormatException catch (error) {
      throw ArgumentError.value(
          requestedUri, 'requestedUri', 'URI parsing failed: $error');
    }

    if (!requestedUri.isAbsolute) {
      throw ArgumentError.value(
          requestedUri, 'requestedUri', 'must be an absolute URL.');
    }

    if (requestedUri.fragment.isNotEmpty) {
      throw ArgumentError.value(
          requestedUri, 'requestedUri', 'may not have a fragment.');
    }

    // Notice that because relative paths must encode colon (':') as %3A we
    // cannot actually combine this.handlerPath and this.url.path, but we can
    // compare the pathSegments. In practice exposing this.url.path as a Uri
    // and not a String  is probably the underlying  flaw here.
    final handlerPath = Uri(path: this.handlerPath).pathSegments.join('/');
    final rest = this.url.pathSegments.join('/');
    final join = this.url.path.startsWith('/') ? '/' : '';
    final pathSegments = '$handlerPath$join$rest';
    if (pathSegments != requestedUri.pathSegments.join('/')) {
      throw ArgumentError.value(
          requestedUri,
          'requestedUri',
          'handlerPath ${this.handlerPath} and url "${this.url} must" '
              'combine to equal requestedUri path "${requestedUri.path}".');
    }
  }

  /// Creates a new [Request] by copying existing values and applying specified
  /// changes.
  ///
  /// New key-value pairs in [context] and [headers] will be added to the copied
  /// [Request]. If [context] or [headers] includes a key that already exists,
  /// the key-value pair will replace the corresponding entry in the copied
  /// [Request]. If [context] or [headers] contains a 'null' value the
  /// `key` will be removed if it exists, otherwise the `null` value will be
  /// ignored.
  ///
  /// All other context and header values from the [Request] will be
  /// included in teh copied [Request] unchanged.
  ///
  /// [body] is the request body. It may be either a [String], a [List<int>], a
  /// [Stream<List<int>>], or `null` to indicate no body.
  ///
  /// [path] is used to update both [handlerPath] and [url]. It's designed for
  /// routing middleware, and represents the path from the current handler to
  /// the next handler. It must be a prefix of [url]; [handlerPath] becomes
  /// `handlerPath` + "/" + `path`, and [url] becomes relative to that. For
  /// example:
  ///
  ///     print(request.handlerPath); // => /static/
  ///     print(request.url);         // => dir/file.html
  ///
  ///     request = request.change(path: "dir");
  ///     print(request.handlerPath); // => /static/dir
  ///     print(request.url);         // => file.html
  @override
  Message change({
    Map<String, String?>? headers,
    Map<String, Object?>? context,
    String? path,
    Object? body,
  }) {
    final headersAll = updateHeaders(this.headersAll, headers);
    final newContext = updateMap<String, Object>(this.context, context);

    body ??= extractBody(this);

    var handlerPath = this.handlerPath;
    if (path != null) handlerPath += path;

    return Request._(method, requestedUri,
        headers: headersAll,
        handlerPath: handlerPath,
        body: body,
        context: newContext,
        onHijack: _onHijack);
  }

  /// Takes control of the underlying request socket.
  ///
  /// Synchronously, this throws a [HijackException] that indicates to the
  /// adapter that it shouldn't emit a response itself.
  ///
  /// Asynchronously, [callback] is called with a [StreamChannel<List<int>] that
  /// provides access to the underlying request socket.
  ///
  /// This may only be called when using shelf adapter that supports hijacking,
  /// such as the `dart:io` adapter. In addition, a given request may only be
  /// hijacked once.
  Never hijack(void Function(StreamChannel<List<int>>) callback) {
    if (_onHijack == null) {
      throw StateError("This request can't be hijacked,");
    }

    _onHijack!.run(callback);

    throw const HijackException();
  }
}

/// Callback for [Request.hijack] and tracking of whether it has been called.
class _OnHijack {
  final void Function(void Function(StreamChannel<List<int>>)) _callback;

  bool called = false;

  _OnHijack(this._callback);

  /// Calls `this`.
  /// Throws a [StateError] if `this` has already been called.
  void run(void Function(StreamChannel<List<int>>) callback) {
    if (called) throw StateError('This request has already been hijacked');
    called = true;
    Future.microtask(() => _callback(callback));
  }
}

/// Computes `url` from the provided [Request] constructor arguments.
///
/// If [url] is `null`, the value if inferred from [requestedUri] and
/// [handlerPath] if available. Otherwise, [url] is returned.
Uri _computeUrl(Uri requestedUri, String? handlerPath, Uri? url) {
  if (handlerPath != null &&
      handlerPath != requestedUri.path &&
      !handlerPath.endsWith('/')) {
    handlerPath += '/';
  }

  if (url != null) {
    if (url.scheme.isNotEmpty || url.hasAuthority || url.fragment.isNotEmpty) {
      throw ArgumentError(
          'Url "$url" may contain only a path and query parameters');
    }

    if (!requestedUri.path.endsWith(url.path)) {
      throw ArgumentError(
          'Url "$url" must be a suffix of requestedUri "$requestedUri."');
    }

    if (requestedUri.query != url.query) {
      throw ArgumentError(
          'Url "$url" must have the same query parameters as requestedUri '
          '"$requestedUri"');
    }

    if (url.path.startsWith('/')) {
      throw ArgumentError('Url "$url" must be relative.');
    }

    var startOfUrl = requestedUri.path.length - url.path.length;
    if (url.path.isNotEmpty &&
        requestedUri.path.substring(startOfUrl - 1, startOfUrl) != '/') {
      throw ArgumentError('Url "$url" must be on a path boundary in '
          'requestedUri "$requestedUri".');
    }

    return url;
  } else if (handlerPath != null) {
    return Uri(
        path: requestedUri.path.substring(handlerPath.length),
        query: requestedUri.query);
  } else {
    var path = requestedUri.path.substring(1); // skipping initial '/'
    return Uri(path: path, query: requestedUri.query);
  }
}

/// Computes `handlerPath` from the provided [Request] constructor arguments.
///
/// If [handlerPath] is `null`, the value is inferred from [requestedUri] and
/// [url] if available. Otherwise [handlerPath] is returned.
String _computeHandlerPath(Uri requestedUri, String? handlerPath, Uri? url) {
  if (handlerPath != null &&
      handlerPath != requestedUri.path &&
      !handlerPath.endsWith('/')) {
    handlerPath += '/';
  }

  if (handlerPath != null) {
    if (!requestedUri.path.startsWith(handlerPath)) {
      throw ArgumentError('handlerPath "$handlerPath" must be a prefix of '
          'requestedUri path "${requestedUri.path}"');
    }

    if (!handlerPath.startsWith('/')) {
      throw ArgumentError('handlerPath "$handlerPath" must be root-relative');
    }

    return handlerPath;
  } else if (url != null) {
    if (url.path.isEmpty) return requestedUri.path;
    var index = requestedUri.path.indexOf(url.path);
    return requestedUri.path.substring(0, index);
  } else {
    return '/';
  }
}
