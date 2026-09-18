import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/theme/light_theme.dart';
import 'package:trusttunnel/widgets/common/custom_arrow_list_tile.dart';
import 'package:trusttunnel/widgets/common/custom_checkbox_list_tile.dart';
import 'package:trusttunnel/widgets/common/custom_list_tile_separated.dart';
import 'package:trusttunnel/widgets/common/custom_radio_list_tile.dart';
import 'package:trusttunnel/widgets/hover_theme_provider.dart';

void main() {
  setUp(() {
    final previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = previousStrategy);
  });

  testWidgets('settings and server rows visibly highlight keyboard focus', (tester) async {
    for (final row in <Widget>[
      CustomArrowListTile(title: 'Settings row', onTap: () {}),
      CustomListTileSeparated(title: 'Server row', onTileTap: () {}),
    ]) {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        _app(
          Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: Material(
                color: Colors.white,
                child: SizedBox(width: 400, child: HoverThemeProvider(child: row)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = await _cornerPixel(tester, boundaryKey);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final after = await _cornerPixel(tester, boundaryKey);
      expect(after, isNot(equals(before)), reason: '${row.runtimeType} must show the focused row');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('D-pad moves from settings row to server row and activates them', (tester) async {
    var settingsOpened = 0;
    var serverOpened = 0;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            CustomArrowListTile(title: 'Settings', onTap: () => settingsOpened++),
            CustomListTileSeparated(title: 'Server', onTileTap: () => serverOpened++),
          ],
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(settingsOpened, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(serverOpened, 1);
    expect(settingsOpened, 1);
  });

  testWidgets('checkbox has one focus stop and toggles with the remote select key', (tester) async {
    final changes = <bool>[];
    var nextActivated = false;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            CustomCheckboxListTile(value: false, title: const Text('Checkbox'), onChanged: changes.add),
            TextButton(onPressed: () => nextActivated = true, child: const Text('Next')),
          ],
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(changes, [true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(nextActivated, isTrue, reason: 'The decorative checkbox must not take a second focus stop');
    expect(changes, [true]);
  });

  testWidgets('radio rows have one focus stop and disabled rows are skipped', (tester) async {
    final changes = <int?>[];
    var nextActivated = false;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            CustomRadioListTile(value: 1, groupValue: 0, title: 'Radio', onChanged: changes.add),
            CustomRadioListTile(value: 2, groupValue: 0, title: 'Disabled', enabled: false, onChanged: changes.add),
            TextButton(onPressed: () => nextActivated = true, child: const Text('Next')),
          ],
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(changes, [1]);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(nextActivated, isTrue, reason: 'The nested radio and disabled row must not receive focus');
    expect(changes, [1]);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: LightTheme().data,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
    child: child!,
  ),
  home: Scaffold(body: child),
);

Future<List<int>> _cornerPixel(WidgetTester tester, GlobalKey boundaryKey) async {
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final offset = (4 * image.width + 4) * 4;
      return bytes.sublist(offset, offset + 4);
    } finally {
      image.dispose();
    }
  }))!;
}
