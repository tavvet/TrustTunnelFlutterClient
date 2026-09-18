import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:trusttunnel/feature/server/server_import/service/local_import_page.dart';

enum LocalImportSessionEndReason { imported, expired, closed }

/// A short-lived, single-use import endpoint on the local network.
///
/// HTTP does not encrypt the submitted configuration. Use a trusted local
/// network. The QR secret stays in the browser fragment until the POST body.
class LocalImportSession {
  static const _maxBodyBytes = 32 * 1024;
  static const _maxLinkBytes = 16 * 1024;
  static const _maxCodeAttempts = 5;
  static const _bodyTimeout = Duration(seconds: 10);

  final HttpServer _server;
  final Future<void> Function(String link) _onImport;
  final String _token;
  final String _pageNonce;
  final Set<String> _allowedHosts;
  final Completer<LocalImportSessionEndReason> _done = Completer();
  late final Timer _expirationTimer;
  Future<void>? _closing;
  bool _importing = false;
  bool _isClosed = false;
  int _failedCodeAttempts = 0;
  int _activeRequests = 0;

  final List<Uri> urls;
  final String pairingCode;
  final DateTime expiresAt;

  LocalImportSession._({
    required HttpServer server,
    required Future<void> Function(String link) onImport,
    required List<InternetAddress> addresses,
    required String token,
    required String pageNonce,
    required this.pairingCode,
    required Duration lifetime,
  }) : _server = server,
       _onImport = onImport,
       _token = token,
       _pageNonce = pageNonce,
       expiresAt = DateTime.now().add(lifetime),
       urls = List.unmodifiable(
         addresses.map((address) => Uri(scheme: 'http', host: address.address, port: server.port, path: '/')),
       ),
       _allowedHosts = addresses.map((address) => '${address.address}:${server.port}').toSet() {
    _expirationTimer = Timer(lifetime, () => unawaited(_finish(LocalImportSessionEndReason.expired)));
    _server.idleTimeout = _bodyTimeout;
    _server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object _) => unawaited(close()),
    );
  }

  /// The first LAN address, without either pairing credential.
  Uri get url => urls.first;

  /// The fragment is handled by the page and is never sent in an HTTP URL.
  Uri get qrUrl => url.replace(fragment: 'token=$_token');

  bool get isClosed => _isClosed;

  Future<LocalImportSessionEndReason> get done => _done.future;

  /// [addresses] is an explicit interface override, including loopback for tests.
  static Future<LocalImportSession> start({
    required Future<void> Function(String link) onImport,
    Duration lifetime = const Duration(minutes: 5),
    List<InternetAddress>? addresses,
  }) async {
    if (lifetime <= Duration.zero) {
      throw ArgumentError.value(lifetime, 'lifetime', 'Must be positive');
    }
    final interfaces = addresses ?? await _discoverAddresses();
    final usableAddresses = <String, InternetAddress>{
      for (final address in interfaces)
        if (address.type == InternetAddressType.IPv4 && !address.isLinkLocal && address.address != '0.0.0.0')
          address.address: address,
    }.values.toList(growable: false);
    if (usableAddresses.isEmpty) {
      throw const SocketException('No local network address found. Connect the TV to Wi-Fi or Ethernet and try again.');
    }

    final random = Random.secure();
    String randomSecret() => base64Url.encode(List.generate(32, (_) => random.nextInt(256))).replaceAll('=', '');
    final token = randomSecret();
    final nonce = randomSecret();
    final code = random.nextInt(1000000).toString().padLeft(6, '0');
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    return LocalImportSession._(
      server: server,
      onImport: onImport,
      addresses: usableAddresses,
      token: token,
      pageNonce: nonce,
      pairingCode: code,
      lifetime: lifetime,
    );
  }

  static Future<List<InternetAddress>> _discoverAddresses() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    // Tunnel, cellular and virtual interfaces do not identify the TV's LAN.
    final excluded = RegExp(
      r'^(lo|tun|tap|utun|ppp|ipsec|wg|rmnet|v4-rmnet|clat|ccmni|docker|veth|virbr)',
      caseSensitive: false,
    );
    final addresses = <InternetAddress>[];
    for (final interface in interfaces) {
      if (excluded.hasMatch(interface.name)) continue;
      for (final address in interface.addresses) {
        final bytes = address.rawAddress;
        final isPrivate =
            bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
            (bytes[0] == 192 && bytes[1] == 168);
        if (isPrivate && !address.isLoopback && !address.isLinkLocal) addresses.add(address);
      }
    }
    return addresses;
  }

  Future<void> _handle(HttpRequest request) async {
    _activeRequests++;
    try {
      _setResponseHeaders(request.response);
      if (_isClosed || !DateTime.now().isBefore(expiresAt)) {
        await _reply(request, HttpStatus.gone, 'This session has ended. Open a new import session on your TV.');
        return;
      }
      if (_activeRequests > 8) {
        await _reply(request, HttpStatus.serviceUnavailable, 'Please wait a moment and try again.');
        return;
      }
      if (!_isAllowedRequest(request)) {
        await _reply(request, HttpStatus.forbidden, 'Open the address shown on your TV.');
        return;
      }
      // Do not accept secrets or configuration data in query strings.
      if (request.uri.hasQuery || request.uri.hasFragment) {
        await _reply(request, HttpStatus.badRequest, 'Open the address shown on your TV without a query string.');
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/status') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'remainingMilliseconds': max(0, expiresAt.difference(DateTime.now()).inMilliseconds)}),
        );
        await request.response.close();
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(localImportPage(nonce: _pageNonce, remaining: expiresAt.difference(DateTime.now())));
        await request.response.close();
        return;
      }
      if (request.method != 'POST' || request.uri.path != '/import') {
        await _reply(request, HttpStatus.notFound, 'This page is not available.');
        return;
      }
      if (_importing) {
        await _reply(request, HttpStatus.conflict, 'An import is already in progress. Please wait.');
        return;
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        await _reply(request, HttpStatus.unsupportedMediaType, 'Send the link using this page.');
        return;
      }

      final payload = jsonDecode(await _readBody(request));
      if (payload is! Map<String, dynamic>) {
        throw const FormatException();
      }
      if (_importing || _isClosed || !DateTime.now().isBefore(expiresAt)) {
        await _reply(request, HttpStatus.conflict, 'This session is busy or has ended. Check your TV.');
        return;
      }
      if (!_isAuthenticated(payload)) {
        final lockedOut = _failedCodeAttempts >= _maxCodeAttempts;
        try {
          await _reply(
            request,
            lockedOut ? HttpStatus.tooManyRequests : HttpStatus.unauthorized,
            lockedOut
                ? 'Too many incorrect codes. Open a new import session on your TV.'
                : 'The pairing code is incorrect or the QR session is no longer valid.',
          );
        } finally {
          if (lockedOut) await _finish(LocalImportSessionEndReason.expired);
        }
        return;
      }
      final value = payload['link'];
      if (value is! String || !_isValidLink(value)) {
        await _reply(request, HttpStatus.unprocessableEntity, 'Paste a valid TrustTunnel link beginning with tt://?.');
        return;
      }
      // Other requests may have finished reading their bodies while this one did.
      if (_importing || _isClosed || !DateTime.now().isBefore(expiresAt)) {
        await _reply(request, HttpStatus.conflict, 'This session is busy or has ended. Check your TV.');
        return;
      }
      _importing = true;
      try {
        await _onImport(value.trim());
      } catch (_) {
        _importing = false;
        if (!_isClosed) {
          await _reply(
            request,
            HttpStatus.unprocessableEntity,
            'This link could not be imported. Check the link and try again.',
          );
        }
        return;
      }
      if (_isClosed || !DateTime.now().isBefore(expiresAt)) return;
      _expirationTimer.cancel();
      try {
        await _reply(request, HttpStatus.ok, 'Link received. Review the server details on your TV.', success: true);
      } finally {
        // Acceptance is single-use even when the sender disconnects before the
        // acknowledgement arrives. Do not expire an already accepted import.
        await _finish(LocalImportSessionEndReason.imported);
      }
    } on _BodyTooLarge {
      await _safeReply(
        request,
        HttpStatus.requestEntityTooLarge,
        'The link is too large. Paste only the TrustTunnel link.',
      );
    } on TimeoutException {
      await _safeReply(request, HttpStatus.requestTimeout, 'The request timed out. Try again.');
    } on FormatException {
      await _safeReply(request, HttpStatus.badRequest, 'The request could not be read. Try again.');
    } on HttpException {
      // The browser disconnected, or the session expired while reading a body.
    } on SocketException {
      // Connection errors must never include submitted data in application logs.
    } catch (_) {
      await _safeReply(request, HttpStatus.internalServerError, 'The import could not be completed. Try again.');
    } finally {
      _activeRequests--;
    }
  }

  bool _isAllowedRequest(HttpRequest request) {
    final hosts = request.headers[HttpHeaders.hostHeader];
    if (hosts == null || hosts.length != 1 || !_allowedHosts.contains(hosts.single)) return false;
    final origins = request.headers['origin'];
    if (origins == null) return request.method == 'GET';
    return origins.length == 1 && origins.single == 'http://${hosts.single}';
  }

  bool _isAuthenticated(Map<String, dynamic> payload) {
    if (_failedCodeAttempts >= _maxCodeAttempts) return false;
    if (payload['token'] case final String token) {
      return _constantTimeEquals(token, _token);
    }
    if (payload.containsKey('code')) {
      final code = payload['code'];
      if (_failedCodeAttempts < _maxCodeAttempts && code is String && _constantTimeEquals(code, pairingCode))
        return true;
      _failedCodeAttempts++;
    }
    return false;
  }

  static bool _constantTimeEquals(String supplied, String expected) {
    var difference = supplied.length ^ expected.length;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^ (i < supplied.length ? supplied.codeUnitAt(i) : 0);
    }
    return difference == 0;
  }

  static bool _isValidLink(String value) {
    if (utf8.encode(value).length > _maxLinkBytes) return false;
    final link = value.trim();
    if (!link.startsWith('tt://?')) return false;
    final uri = Uri.tryParse(link);
    return uri != null && uri.host.isEmpty && uri.path.isEmpty && uri.query.isNotEmpty && !uri.hasFragment;
  }

  static Future<String> _readBody(HttpRequest request) async {
    if (request.contentLength > _maxBodyBytes) throw const _BodyTooLarge();
    final bytes = <int>[];
    final stream = StreamIterator(request);
    final stopwatch = Stopwatch()..start();
    try {
      while (await stream.moveNext().timeout(_bodyTimeout - stopwatch.elapsed)) {
        if (bytes.length + stream.current.length > _maxBodyBytes) throw const _BodyTooLarge();
        bytes.addAll(stream.current);
      }
      return utf8.decode(bytes);
    } finally {
      await stream.cancel();
    }
  }

  void _setResponseHeaders(HttpResponse response) {
    response.persistentConnection = false;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('X-Frame-Options', 'DENY');
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'none'; script-src 'nonce-$_pageNonce'; style-src 'nonce-$_pageNonce'; "
          "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
    );
  }

  static Future<void> _reply(HttpRequest request, int status, String message, {bool success = false}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'ok': success, 'message': message}));
    await request.response.close();
  }

  Future<void> _safeReply(HttpRequest request, int status, String message) async {
    if (_isClosed) return;
    try {
      await _reply(request, status, message);
    } catch (_) {
      // A closed peer needs no further response.
    }
  }

  Future<void> close() => _finish(LocalImportSessionEndReason.closed);

  Future<void> _finish(LocalImportSessionEndReason reason) {
    if (_closing != null) return _closing!;
    _isClosed = true;
    _expirationTimer.cancel();
    _done.complete(reason);
    return _closing = _server.close(force: true).then<void>((_) {});
  }
}

class _BodyTooLarge implements Exception {
  const _BodyTooLarge();
}
