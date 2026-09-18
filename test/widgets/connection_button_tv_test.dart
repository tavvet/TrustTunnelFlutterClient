import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/light_theme.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_card_connection_button.dart';
import 'package:trusttunnel/widgets/buttons/custom_floating_action_button.dart';
import 'package:trusttunnel/widgets/rotating_wrapper.dart';

void main() {
  setUp(() {
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
  });

  testWidgets('connection button keeps remote focus through every VPN state', (tester) async {
    final state = ValueNotifier(VpnState.disconnected);
    addTearDown(state.dispose);
    var activations = 0;
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder(
          valueListenable: state,
          builder: (context, value, child) => ServersCardConnectionButton(
            serverId: 'test',
            vpnManagerState: value,
            onPressed: () => activations++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final focus = FocusManager.instance.primaryFocus;
    final buttonElement = tester.element(find.byType(IconButton));

    for (final next in [
      VpnState.connecting,
      VpnState.connected,
      VpnState.waitingForNetwork,
      VpnState.waitingForRecovery,
      VpnState.recovering,
      VpnState.disconnected,
    ]) {
      state.value = next;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.element(find.byType(IconButton)), same(buttonElement));
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(focus!.hasFocus, isTrue);
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.isSelected, next != VpnState.disconnected);
      expect(
        button.tooltip,
        next == VpnState.disconnected
            ? 'Connect'
            : next == VpnState.connected
            ? 'Disconnect'
            : 'Cancel',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
    }
    expect(activations, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending connection rotates only the icon, keeping its focused border still', (tester) async {
    await tester.pumpWidget(
      _app(ServersCardConnectionButton(serverId: 'test', vpnManagerState: VpnState.connecting, onPressed: () {})),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.descendant(of: find.byType(IconButton), matching: find.byType(RotatingWidget)), findsOneWidget);
    expect(find.ancestor(of: find.byType(IconButton), matching: find.byType(RotatingWidget)), findsNothing);
    final before = tester.getRect(find.byType(IconButton));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.getRect(find.byType(IconButton)), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV add button has a stable focus outline and one focus stop', (tester) async {
    var adds = 0;
    var next = 0;
    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomFloatingActionButton.extended(icon: Icons.add, label: 'Add server', onPressed: () => adds++),
            TextButton(onPressed: () => next++, child: const Text('Next')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byType(FloatingActionButton);
    final idleRect = tester.getRect(button);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final focusedShape = tester.widget<FloatingActionButton>(button).shape! as OutlinedBorder;
    expect(focusedShape.side.width, 3);
    expect(focusedShape.side.color.a, 1);
    expect(tester.getRect(button), idleRect);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(adds, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final idleShape = tester.widget<FloatingActionButton>(button).shape! as OutlinedBorder;
    expect(idleShape.side.style, BorderStyle.none);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(next, 1);
    expect(adds, 1);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: LightTheme().data,
  localizationsDelegates: Localization.localizationDelegates,
  supportedLocales: Localization.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
    child: child!,
  ),
  home: Scaffold(body: Center(child: child)),
);
