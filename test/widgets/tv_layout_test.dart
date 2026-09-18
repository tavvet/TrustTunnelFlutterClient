import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/light_theme.dart';
import 'package:trusttunnel/data/model/routing_mode.dart';
import 'package:trusttunnel/feature/routing/routing_details/widgets/routing_details_screen_app_bar_action.dart';
import 'package:trusttunnel/widgets/menu/custom_dropdown_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/roboto/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/roboto/Roboto-Medium.ttf'));
    await fonts.load();
  });

  testWidgets('routing actions fit the TV menu with large system text', (tester) async {
    await _pumpTv(
      tester,
      Align(
        alignment: Alignment.topRight,
        child: RoutingDetailsScreenAppBarAction(
          profileName: 'Home network',
          pickedRoutingMode: RoutingMode.vpn,
          onClearRulesPressed: (_) {},
          onDefaultModePicked: (_, _) {},
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Change default routing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV profile dropdown contains long names and remains selectable', (tester) async {
    const name = 'Home network profile with a long descriptive name for all streaming devices';
    String? selected;
    await _pumpTv(
      tester,
      Center(
        child: SizedBox(
          width: 400,
          child: CustomDropdownMenu<String>.expanded(
            value: name,
            values: const [name, 'Default profile'],
            labelText: 'Routing profile',
            toText: (value) => value,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final menuLabel = find.text(name).last;
    final defaultLabel = find.text('Default profile').last;
    final focusedMenuItem = find.ancestor(of: menuLabel, matching: find.byType(InkWell)).first;
    expect(tester.getRect(menuLabel).top, greaterThanOrEqualTo(tester.getRect(focusedMenuItem).top));
    expect(tester.getRect(menuLabel).bottom, lessThanOrEqualTo(tester.getRect(focusedMenuItem).bottom));
    expect(tester.getRect(menuLabel).bottom, lessThanOrEqualTo(tester.getRect(defaultLabel).top));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, 'Default profile');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpTv(WidgetTester tester, Widget body) async {
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
          textScaler: const TextScaler.linear(1.3),
        ),
        child: child!,
      ),
      home: Scaffold(body: body),
    ),
  );
  await tester.pumpAndSettle();
}
