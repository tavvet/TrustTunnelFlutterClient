import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/light_theme.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/server/server_import/service/local_import_session.dart';
import 'package:trusttunnel/feature/server/server_import/widgets/server_import_screen.dart';

const _server = ServerData.empty(
  name: 'Home VPN',
  ipAddress: '192.0.2.10:443',
  domain: 'vpn.example.com',
  username: 'private-user',
  password: 'never-show-this-password',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/roboto/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/roboto/Roboto-Medium.ttf'));
    await fonts.load();
  });

  testWidgets('large-text review keeps Retry visible after a save error with long server details', (tester) async {
    late _FakeSession session;
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async => _server.copyWith(
          name: 'Home network server for streaming devices and all family computers',
          domain: 'a-very-long-server-domain-name-for-the-family-network.example.com',
        ),
        save: (_) async => throw StateError('Save failed'),
        sessionFactory: ({required onImport}) async => session = _FakeSession(onImport: onImport),
      ),
      textScale: 1.3,
    );
    await session.receive('tt://valid');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final retry = find.widgetWithText(FilledButton, 'Try again');
    expect(Focus.of(tester.element(find.text('Try again'))).hasFocus, isTrue);
    expect(tester.getRect(retry).bottom, lessThanOrEqualTo(524));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows startup, then readable URL, pairing code and QR within the TV viewport', (tester) async {
    final started = Completer<LocalImportSession>();
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async => _server,
        save: (_) async {},
        sessionFactory: ({required onImport}) => started.future,
      ),
    );
    expect(find.text('Preparing import…'), findsOneWidget);
    final session = _FakeSession(onImport: (_) async {});
    started.complete(session);
    await tester.pumpAndSettle();

    expect(find.text(session.url.toString()), findsOneWidget);
    expect(find.textContaining(session.pairingCode), findsOneWidget);
    expect(find.textContaining('remaining'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(QrImageView),
        matching: find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is QrPainter),
      ),
      findsOneWidget,
    );
    final action = find.widgetWithText(FilledButton, 'Cancel');
    expect(tester.getRect(action).bottom, lessThanOrEqualTo(524));
    expect(tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent, 0);
    expect(Focus.of(tester.element(find.text('Cancel'))).hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(session.isClosed, isTrue);
  });

  testWidgets('invalid links stay retryable and never display exception secrets', (tester) async {
    late _FakeSession session;
    var decodeAttempts = 0;
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async {
          if (++decodeAttempts == 1) throw const FormatException('secret tt://bad-password');
          return _server;
        },
        save: (_) async {},
        sessionFactory: ({required onImport}) async => session = _FakeSession(onImport: onImport),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(session.receive('tt://bad'), throwsFormatException);
    await tester.pump();
    expect(find.textContaining('copied the full TrustTunnel link'), findsOneWidget);
    expect(find.textContaining('bad-password'), findsNothing);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(session.isClosed, isFalse);

    await session.receive('tt://valid');
    await tester.pumpAndSettle();
    expect(find.text(_server.name), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('review keeps credentials hidden and D-pad Add saves before returning', (tester) async {
    late _FakeSession session;
    final saved = <ServerData>[];
    ServerData? result;
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async => _server,
        save: (data) async => saved.add(data),
        sessionFactory: ({required onImport}) async => session = _FakeSession(onImport: onImport),
      ),
      onResult: (data) => result = data,
    );
    await session.receive('tt://valid');
    await tester.pumpAndSettle();
    expect(find.text(_server.name), findsOneWidget);
    expect(find.text(_server.ipAddress), findsOneWidget);
    expect(find.text(_server.domain), findsOneWidget);
    expect(find.text(_server.password), findsNothing);
    expect(find.text(_server.username), findsNothing);
    expect(tester.getRect(find.widgetWithText(FilledButton, 'Add')).bottom, lessThanOrEqualTo(524));
    expect(saved, isEmpty);
    expect(result, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(saved, [_server]);
    expect(result, _server);
    expect(find.byType(ServerImportScreen), findsNothing);
    expect(session.isClosed, isTrue);
  });

  testWidgets('failed save keeps the candidate and focused Retry succeeds', (tester) async {
    late _FakeSession session;
    var attempts = 0;
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async => _server,
        save: (_) async {
          if (++attempts == 1) throw StateError('sensitive database details');
        },
        sessionFactory: ({required onImport}) async => session = _FakeSession(onImport: onImport),
      ),
    );
    await session.receive('tt://valid');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Could not save this server. Please try again.'), findsOneWidget);
    expect(find.text(_server.name), findsOneWidget);
    expect(find.textContaining('sensitive database'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(ServerImportScreen), findsNothing);
  });

  testWidgets('D-pad can cancel the reviewed configuration without saving', (tester) async {
    late _FakeSession session;
    var saved = false;
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async => _server,
        save: (_) async => saved = true,
        sessionFactory: ({required onImport}) async => session = _FakeSession(onImport: onImport),
      ),
    );
    await session.receive('tt://valid');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.byType(ServerImportScreen), findsNothing);
    expect(session.isClosed, isTrue);
  });

  testWidgets('expired and unavailable sessions offer a focused fresh-session Retry', (tester) async {
    var starts = 0;
    late _FakeSession session;
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async => _server,
        save: (_) async {},
        sessionFactory: ({required onImport}) async {
          if (++starts == 1) throw StateError('network failure details');
          return session = _FakeSession(onImport: onImport);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('network failure details'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(find.byType(QrImageView), findsOneWidget);

    session.end(LocalImportSessionEndReason.expired);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(starts, 3);
    expect(find.byType(QrImageView), findsOneWidget);
    session.end(LocalImportSessionEndReason.closed);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelling startup closes a session that finishes starting later', (tester) async {
    final started = Completer<LocalImportSession>();
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async => _server,
        save: (_) async {},
        sessionFactory: ({required onImport}) => started.future,
      ),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final session = _FakeSession(onImport: (_) async {});
    started.complete(session);
    await tester.pump();
    expect(session.isClosed, isTrue);
    expect(find.byType(ServerImportScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back closes the endpoint and ignores a decode that finishes after cancellation', (tester) async {
    late _FakeSession session;
    final decoded = Completer<ServerData>();
    var saved = false;
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) => decoded.future,
        save: (_) async => saved = true,
        sessionFactory: ({required onImport}) async => session = _FakeSession(onImport: onImport),
      ),
    );
    final receiving = session.receive('tt://valid');
    final receiveRejected = expectLater(receiving, throwsFormatException);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(session.isClosed, isTrue);
    decoded.complete(_server);
    await receiveRejected;
    await tester.pump();
    expect(saved, isFalse);
    expect(find.byType(ServerImportScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV Home or sleep closes the endpoint until the user starts a new session', (tester) async {
    late _FakeSession session;
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async => _server,
        save: (_) async {},
        sessionFactory: ({required onImport}) async => session = _FakeSession(onImport: onImport),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(session.isClosed, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('covering the import route closes its endpoint', (tester) async {
    late _FakeSession session;
    await _open(
      tester,
      ServerImportScreen(
        decode: (_) async => _server,
        save: (_) async {},
        sessionFactory: ({required onImport}) async => session = _FakeSession(onImport: onImport),
      ),
    );
    final navigator = Navigator.of(tester.element(find.byType(ServerImportScreen)));
    unawaited(navigator.push<void>(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Another page')))));
    await tester.pumpAndSettle();
    expect(session.isClosed, isTrue);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _open(
  WidgetTester tester,
  ServerImportScreen screen, {
  ValueChanged<ServerData?>? onResult,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(960, 540);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: LightTheme().data,
      localizationsDelegates: Localization.localizationDelegates,
      supportedLocales: Localization.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          navigationMode: NavigationMode.directional,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<ServerData>(
                MaterialPageRoute(builder: (_) => screen),
              );
              onResult?.call(result);
            },
            child: const Text('Open import'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open import'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _FakeSession implements LocalImportSession {
  final Future<void> Function(String link) onImport;
  final _done = Completer<LocalImportSessionEndReason>();

  _FakeSession({required this.onImport});

  @override
  final url = Uri.parse('http://192.168.1.20:48123/');

  @override
  Uri get qrUrl => url.replace(fragment: 'token=test-token');

  @override
  List<Uri> get urls => [url];

  @override
  final pairingCode = '123456';

  @override
  final expiresAt = DateTime.now().add(const Duration(minutes: 5));

  @override
  bool isClosed = false;

  @override
  Future<LocalImportSessionEndReason> get done => _done.future;

  Future<void> receive(String link) async {
    await onImport(link);
    if (!isClosed) end(LocalImportSessionEndReason.imported);
  }

  void end(LocalImportSessionEndReason reason) {
    isClosed = true;
    if (!_done.isCompleted) _done.complete(reason);
  }

  @override
  Future<void> close() async => end(LocalImportSessionEndReason.closed);
}
