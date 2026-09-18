import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/server/server_import/service/local_import_session.dart';

void main() {
  final sessions = <LocalImportSession>[];
  late HttpClient client;

  Future<LocalImportSession> start({
    Future<void> Function(String)? onImport,
    Duration lifetime = const Duration(minutes: 1),
  }) async {
    final session = await LocalImportSession.start(
      onImport: onImport ?? (_) async {},
      addresses: [InternetAddress.loopbackIPv4],
      lifetime: lifetime,
    );
    sessions.add(session);
    return session;
  }

  Future<_Response> post(
    LocalImportSession session,
    Object body, {
    String? origin,
    String? host,
    bool omitOrigin = false,
    bool chunked = false,
  }) async {
    final request = await client.postUrl(session.url.resolve('/import'));
    request.headers.contentType = ContentType.json;
    if (!omitOrigin) request.headers.set('Origin', origin ?? session.url.origin);
    if (host != null) request.headers.set(HttpHeaders.hostHeader, host);
    final bytes = utf8.encode(jsonEncode(body));
    if (!chunked) request.contentLength = bytes.length;
    request.add(bytes);
    return _read(await request.close());
  }

  setUp(() {
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });

  tearDown(() async {
    client.close(force: true);
    for (final session in sessions) {
      await session.close();
    }
    sessions.clear();
  });

  test('page is local, has hardened headers, and never embeds the pairing secret', () async {
    final session = await start();
    final token = Uri.splitQueryString(session.qrUrl.fragment)['token']!;
    expect(token.length, greaterThanOrEqualTo(43));
    expect(session.pairingCode, matches(r'^\d{6}$'));
    expect(session.url.hasQuery, isFalse);
    expect(session.url.hasFragment, isFalse);
    expect(session.urls, [session.url]);

    final request = await client.getUrl(session.url);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value('Cache-Control'), 'no-store');
    expect(response.headers.value('Referrer-Policy'), 'no-referrer');
    expect(response.headers.value('Content-Security-Policy'), contains("default-src 'none'"));
    expect(response.headers.value('Access-Control-Allow-Origin'), isNull);
    expect(body, contains('Send a server to your TV'));
    expect(body, contains('This HTTP connection is not encrypted'));
    expect(body, isNot(contains(token)));
    expect(body, isNot(contains('<script src=')));
  });

  test('manual code imports once, preserves link data and closes the endpoint', () async {
    final imported = <String>[];
    final session = await start(onImport: (link) async => imported.add(link));
    const link = 'tt://?opaque_Payload+with=Characters-123';
    final response = await post(session, {'code': session.pairingCode, 'link': ' $link\n'});
    expect(response.status, HttpStatus.ok);
    expect(jsonDecode(response.body)['ok'], isTrue);
    expect(imported, [link]);
    expect(await session.done, LocalImportSessionEndReason.imported);
    expect(session.isClosed, isTrue);
    await session.close();
    await expectLater(client.getUrl(session.url), throwsA(isA<SocketException>()));
  });

  test('status exposes only the remaining session duration and is never cached', () async {
    var calls = 0;
    final session = await start(onImport: (_) async => calls++);
    final token = Uri.splitQueryString(session.qrUrl.fragment)['token']!;
    final beforeRequest = session.expiresAt.difference(DateTime.now()).inMilliseconds;
    final request = await client.getUrl(session.url.resolve('/status'));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    final afterRequest = max(0, session.expiresAt.difference(DateTime.now()).inMilliseconds);
    final payload = jsonDecode(body) as Map<String, dynamic>;

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType?.mimeType, 'application/json');
    expect(response.headers.value('Cache-Control'), 'no-store');
    expect(response.headers.value('Access-Control-Allow-Origin'), isNull);
    expect(payload.keys, ['remainingMilliseconds']);
    expect(payload['remainingMilliseconds'], inInclusiveRange(afterRequest, beforeRequest));
    expect(body, isNot(contains(token)));
    expect(body, isNot(contains(session.pairingCode)));
    expect(calls, 0);
    expect(session.isClosed, isFalse);
  });

  test('status retains the Host, Origin, query and method restrictions', () async {
    final session = await start();
    final statusUrl = session.url.resolve('/status');

    final originRequest = await client.getUrl(statusUrl);
    originRequest.headers.set('Origin', 'http://evil.example');
    expect((await _read(await originRequest.close())).status, HttpStatus.forbidden);

    final hostRequest = await client.getUrl(statusUrl);
    hostRequest.headers.set(HttpHeaders.hostHeader, 'evil.example');
    expect((await _read(await hostRequest.close())).status, HttpStatus.forbidden);

    final queryRequest = await client.getUrl(statusUrl.replace(query: 'token=not-allowed'));
    expect((await _read(await queryRequest.close())).status, HttpStatus.badRequest);

    final allowedRequest = await client.getUrl(statusUrl);
    allowedRequest.headers.set('Origin', session.url.origin);
    expect((await _read(await allowedRequest.close())).status, HttpStatus.ok);

    final postRequest = await client.postUrl(statusUrl);
    postRequest.headers.set('Origin', session.url.origin);
    expect((await _read(await postRequest.close())).status, HttpStatus.notFound);
  });

  test('QR token authenticates without a manual code', () async {
    var calls = 0;
    final session = await start(onImport: (_) async => calls++);
    final token = Uri.splitQueryString(session.qrUrl.fragment)['token'];
    final response = await post(session, {'token': token, 'link': 'tt://?payload'});
    expect(response.status, HttpStatus.ok);
    expect(calls, 1);
    expect(await session.done, LocalImportSessionEndReason.imported);
  });

  test('missing and incorrect authentication never reaches the decoder', () async {
    var calls = 0;
    final session = await start(onImport: (_) async => calls++);
    for (final credentials in [
      <String, String>{},
      {'token': 'incorrect'},
      {'code': 'incorrect'},
    ]) {
      final response = await post(session, {...credentials, 'link': 'tt://?payload'});
      expect(response.status, HttpStatus.unauthorized);
      expect(calls, 0);
    }
    expect(session.isClosed, isFalse);
  });

  test('fifth incorrect manual code globally ends the session', () async {
    var calls = 0;
    final session = await start(onImport: (_) async => calls++);
    final wrongCode = session.pairingCode == '000000' ? '111111' : '000000';
    for (var i = 0; i < 5; i++) {
      final response = await post(session, {'code': wrongCode, 'link': 'tt://?payload'});
      expect(response.status, i == 4 ? HttpStatus.tooManyRequests : HttpStatus.unauthorized);
    }
    expect(await session.done, LocalImportSessionEndReason.expired);
    expect(session.isClosed, isTrue);
    expect(calls, 0);
  });

  test('foreign or missing Origin and unadvertised Host are rejected', () async {
    var calls = 0;
    final session = await start(onImport: (_) async => calls++);
    final body = {'code': session.pairingCode, 'link': 'tt://?payload'};
    for (final origin in ['http://evil.example', 'null', 'https://${session.url.authority}']) {
      expect((await post(session, body, origin: origin)).status, HttpStatus.forbidden);
    }
    expect((await post(session, body, omitOrigin: true)).status, HttpStatus.forbidden);
    expect((await post(session, body, host: 'evil.example')).status, HttpStatus.forbidden);
    expect((await post(session, body, host: 'localhost:${session.url.port}')).status, HttpStatus.forbidden);
    expect(calls, 0);
  });

  test('URL query secrets and cross-origin page reads are rejected', () async {
    final session = await start();
    final queryRequest = await client.getUrl(session.url.replace(query: 'token=not-allowed'));
    expect((await _read(await queryRequest.close())).status, HttpStatus.badRequest);
    final originRequest = await client.getUrl(session.url);
    originRequest.headers.set('Origin', 'http://evil.example');
    expect((await _read(await originRequest.close())).status, HttpStatus.forbidden);
  });

  test('invalid JSON shape and non-TrustTunnel links do not reach the decoder', () async {
    var calls = 0;
    final session = await start(onImport: (_) async => calls++);
    expect((await post(session, ['unexpected'])).status, HttpStatus.badRequest);
    for (final link in ['https://example.com', 'tt://host?payload', 'tt://?', 'tt://?payload#fragment', '']) {
      final response = await post(session, {'code': session.pairingCode, 'link': link});
      expect(response.status, HttpStatus.unprocessableEntity);
    }
    expect(calls, 0);
  });

  test('body limit applies to declared and chunked bodies and link has its own limit', () async {
    var calls = 0;
    final session = await start(onImport: (_) async => calls++);
    final oversizedBody = {'code': session.pairingCode, 'link': 'tt://?${'a' * (33 * 1024)}'};
    expect((await post(session, oversizedBody)).status, HttpStatus.requestEntityTooLarge);
    expect((await post(session, oversizedBody, chunked: true)).status, HttpStatus.requestEntityTooLarge);
    final oversizedLink = {'code': session.pairingCode, 'link': 'tt://?${'a' * (16 * 1024)}'};
    expect((await post(session, oversizedLink)).status, HttpStatus.unprocessableEntity);
    expect(calls, 0);
  });

  test('decoder error is sanitized and the session allows a valid retry', () async {
    var calls = 0;
    final session = await start(
      onImport: (_) async {
        calls++;
        if (calls == 1) throw const FormatException('SENSITIVE_CONFIG_VALUE');
      },
    );
    final body = {'code': session.pairingCode, 'link': 'tt://?payload'};
    final response = await post(session, body);
    expect(response.status, HttpStatus.unprocessableEntity);
    expect(response.body, isNot(contains('SENSITIVE_CONFIG_VALUE')));
    expect(session.isClosed, isFalse);
    expect((await post(session, body)).status, HttpStatus.ok);
    expect(calls, 2);
  });

  test('concurrent submissions invoke the decoder only once', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final session = await start(
      onImport: (_) async {
        calls++;
        entered.complete();
        await release.future;
      },
    );
    final body = {'code': session.pairingCode, 'link': 'tt://?payload'};
    final first = post(session, body);
    await entered.future;
    expect((await post(session, body)).status, HttpStatus.conflict);
    expect(calls, 1);
    release.complete();
    expect((await first).status, HttpStatus.ok);
    expect(await session.done, LocalImportSessionEndReason.imported);
  });

  test('expiry shuts down even a partially uploaded request', () async {
    var calls = 0;
    final session = await start(lifetime: const Duration(milliseconds: 300), onImport: (_) async => calls++);
    final socket = await Socket.connect(session.url.host, session.url.port);
    addTearDown(socket.destroy);
    final socketClosed = Completer<void>();
    socket.listen((_) {}, onDone: socketClosed.complete, onError: (_) => socketClosed.complete());
    socket.write(
      'POST /import HTTP/1.1\r\nHost: ${session.url.authority}\r\nOrigin: ${session.url.origin}\r\n'
      'Content-Type: application/json\r\nContent-Length: 1000\r\n\r\n{"code":',
    );
    await socket.flush();
    expect(await session.done.timeout(const Duration(seconds: 2)), LocalImportSessionEndReason.expired);
    await socketClosed.future.timeout(const Duration(seconds: 2));
    expect(calls, 0);
    expect(session.isClosed, isTrue);
  });

  test('cancellation during decode cannot report a successful import', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final session = await start(
      onImport: (_) async {
        entered.complete();
        await release.future;
      },
    );
    final response = post(session, {'code': session.pairingCode, 'link': 'tt://?payload'}).then<Object>(
      (value) => value,
      onError: (Object error) => error,
    );
    await entered.future;
    await session.close();
    release.complete();
    expect(await session.done, LocalImportSessionEndReason.closed);
    final result = await response;
    expect(result, isNot(isA<_Response>()));
  });

  test('accepted import closes even when its sender disconnects before the response', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final session = await start(
      onImport: (_) async {
        entered.complete();
        await release.future;
      },
    );
    final socket = await Socket.connect(session.url.host, session.url.port);
    final body = jsonEncode({'code': session.pairingCode, 'link': 'tt://?payload'});
    socket.write(
      'POST /import HTTP/1.1\r\nHost: ${session.url.authority}\r\nOrigin: ${session.url.origin}\r\n'
      'Content-Type: application/json\r\nContent-Length: ${utf8.encode(body).length}\r\n\r\n$body',
    );
    await socket.flush();
    await entered.future;
    socket.destroy();
    release.complete();
    expect(await session.done.timeout(const Duration(seconds: 2)), LocalImportSessionEndReason.imported);
    expect(session.isClosed, isTrue);
  });

  test('no usable LAN address produces a useful setup error', () async {
    await expectLater(
      LocalImportSession.start(onImport: (_) async {}, addresses: []),
      throwsA(isA<SocketException>().having((error) => error.message, 'message', contains('Wi-Fi or Ethernet'))),
    );
  });
}

Future<_Response> _read(HttpClientResponse response) async => _Response(
  response.statusCode,
  await utf8.decoder.bind(response).join(),
);

class _Response {
  final int status;
  final String body;

  _Response(this.status, this.body);
}
