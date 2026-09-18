import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/light_theme.dart';
import 'package:trusttunnel/data/model/vpn_log.dart';
import 'package:trusttunnel/data/model/vpn_log_action.dart';
import 'package:trusttunnel/data/model/vpn_log_protocol.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/data/repository/vpn_repository.dart';
import 'package:trusttunnel/feature/settings/query_log/widgets/query_log_screen_view.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

void main() {
  testWidgets('TV remote reaches the log and scrolls in both directions', (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await _open(tester, repository);
    for (var i = 0; i < 80; i++) {
      repository.logs.add(
        VpnLog(
          action: VpnLogAction.tunnel,
          protocol: VpnLogProtocol.tcp,
          timeStamp: DateTime(2026).add(Duration(seconds: i)),
          source: '192.0.2.1:443',
          destination: '198.51.100.1:443',
        ),
      );
    }
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(QueryLogScreenView),
        matching: find.byType(Scrollable),
      ),
    );
    final before = scrollable.position.pixels;
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    final unfocusedPixel = await _framePixel(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(await _framePixel(tester), isNot(equals(unfocusedPixel)));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(before));
    final afterUp = scrollable.position.pixels;
    repository.logs.add(
      VpnLog(
        action: VpnLogAction.tunnel,
        protocol: VpnLogProtocol.tcp,
        timeStamp: DateTime(2026, 1, 2),
        source: '192.0.2.1:443',
        destination: '198.51.100.1:443',
      ),
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, afterUp, reason: 'New entries must not reset the reader');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, lessThan(afterUp));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Navigation'))).hasFocus, isTrue);
    expect(await _framePixel(tester), unfocusedPixel);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a short log lets Up leave the list for the toolbar', (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await _open(tester, repository, topAction: true);
    repository.logs.add(
      VpnLog(
        action: VpnLogAction.tunnel,
        protocol: VpnLogProtocol.tcp,
        timeStamp: DateTime(2026),
        source: '192.0.2.1:443',
        destination: '198.51.100.1:443',
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Navigation'))).hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Toolbar'))).hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty TV logs add no invisible focus stop', (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await _open(tester, repository);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Navigation'))).hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _open(WidgetTester tester, _Repository repository, {bool topAction = false}) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: LightTheme().data,
      localizationsDelegates: Localization.localizationDelegates,
      supportedLocales: Localization.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
        child: child!,
      ),
      home: Scaffold(
        body: Column(
          children: [
            if (topAction) TextButton(onPressed: () {}, child: const Text('Toolbar')),
            Expanded(
              child: Row(
                children: [
                  TextButton(autofocus: true, onPressed: () {}, child: const Text('Navigation')),
                  Expanded(
                    child: VpnScope(
                      appWindowController: null,
                      vpnRepository: repository,
                      child: const RepaintBoundary(key: ValueKey('logBoundary'), child: QueryLogScreenView()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Repository implements VpnRepository {
  final logs = StreamController<VpnLog>.broadcast();

  Future<void> dispose() => logs.close();

  @override
  Future<Stream<VpnLog>> listenToLogs() async => logs.stream;
  @override
  Future<Stream<VpnState>> listenToStates() async => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<List<int>> _framePixel(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('logBoundary')));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final offset = (85 * image.width + 40) * 4;
      return bytes.sublist(offset, offset + 4);
    } finally {
      image.dispose();
    }
  }))!;
}
