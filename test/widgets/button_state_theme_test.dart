import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/extensions/theme_extensions.dart';
import 'package:trusttunnel/common/theme/light_theme.dart';
import 'package:trusttunnel/widgets/buttons/custom_icon_button.dart';
import 'package:trusttunnel/widgets/custom_snack_bar.dart';
import 'package:trusttunnel/widgets/inputs/custom_text_field.dart';

void main() {
  setUp(() {
    final previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = previousStrategy);
  });

  testWidgets('outlined border stays visible through focus, hover, and press without shifting', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(_app(boundaryKey, OutlinedButton(onPressed: () {}, child: const Text('Manual entry'))));
    await tester.pumpAndSettle();
    final initialRect = tester.getRect(find.byType(OutlinedButton));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await _expectVisibleBorder(tester, boundaryKey);
    expect(tester.getRect(find.byType(OutlinedButton)), initialRect);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    await _expectVisibleBorder(tester, boundaryKey);

    await mouse.down(tester.getCenter(find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    await _expectVisibleBorder(tester, boundaryKey);
    expect(tester.getRect(find.byType(OutlinedButton)), initialRect);
    await mouse.up();
    expect(tester.takeException(), isNull);
  });

  testWidgets('button families show a substantial focus ring and keep their bounds', (tester) async {
    final theme = LightTheme().data;
    final filledIcons = theme.extension<CustomFilledIconButtonTheme>()!;
    final buttons = <Widget>[
      FilledButton(onPressed: () {}, child: const Text('Import')),
      ElevatedButton(onPressed: () {}, child: const Text('Save')),
      TextButton(onPressed: () {}, child: const Text('Cancel')),
      IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
      IconButtonTheme(
        data: filledIcons.iconButton,
        child: IconButton(onPressed: () {}, isSelected: false, icon: const Icon(Icons.power_settings_new)),
      ),
      IconButtonTheme(
        data: filledIcons.iconButton,
        child: IconButton(onPressed: () {}, isSelected: true, icon: const Icon(Icons.power_settings_new)),
      ),
    ];
    for (final button in buttons) {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(_app(boundaryKey, button));
      await tester.pumpAndSettle();
      final materialFinder = _buttonMaterial(boundaryKey);
      final initialRect = tester.getRect(materialFinder);
      final initialSide = (tester.widget<Material>(materialFinder).shape! as OutlinedBorder).side;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final focusedSide = (tester.widget<Material>(materialFinder).shape! as OutlinedBorder).side;
      expect(focusedSide.width, greaterThan(initialSide.width), reason: '${button.runtimeType} must mark focus');
      expect(focusedSide.width, greaterThanOrEqualTo(3));
      await _expectVisibleBorder(tester, boundaryKey);
      expect(tester.getRect(materialFinder), initialRect, reason: 'Focus must not shift the layout');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('disabled buttons cannot inherit active focus, hover, or press paint', () {
    final theme = LightTheme().data;
    final filledIcons = theme.extension<CustomFilledIconButtonTheme>()!;
    for (final style in [
      theme.filledButtonTheme.style!,
      theme.elevatedButtonTheme.style!,
      theme.outlinedButtonTheme.style!,
      theme.textButtonTheme.style!,
      theme.iconButtonTheme.style!,
      theme.menuButtonTheme.style!,
      theme.extension<CustomFilledButtonTheme>()!.danger.style!,
      theme.extension<CustomFilledButtonTheme>()!.attention.style!,
      filledIcons.iconButton.style!,
      filledIcons.iconButtonInProgress.style!,
    ]) {
      const disabled = {WidgetState.disabled};
      const disabledActive = {
        WidgetState.disabled,
        WidgetState.focused,
        WidgetState.hovered,
        WidgetState.pressed,
        WidgetState.selected,
      };
      expect(style.side!.resolve(disabledActive), style.side!.resolve(disabled));
      expect(style.overlayColor!.resolve(disabledActive), Colors.transparent);
      expect(style.backgroundColor?.resolve(disabledActive), style.backgroundColor?.resolve(disabled));
    }
  });

  testWidgets('certificate field action contrasts with the light input background', (tester) async {
    await tester.pumpWidget(
      _app(
        GlobalKey(),
        CustomTextField.customSuffixIcon(
          label: 'Certificate',
          readOnly: true,
          suffixIcon: CustomIconButton(icon: Icons.attach_file, onPressed: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final icon = tester.element(find.byIcon(Icons.attach_file));
    final color = IconTheme.of(icon).color!;
    expect(1.05 / (color.computeLuminance() + 0.05), greaterThanOrEqualTo(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('snackbar action and close button keep a visible focus ring on the dark surface', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      _app(
        boundaryKey,
        CustomSnackBar(
          content: const Text('Failed'),
          showCloseIcon: true,
          trailingActions: [TextButton(onPressed: () {}, child: const Text('Retry'))],
        ).content,
      ),
    );
    await tester.pumpAndSettle();
    for (final type in [TextButton, IconButton]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final material = find.descendant(of: find.byType(type), matching: find.byType(Material)).first;
      final side = (tester.widget<Material>(material).shape! as OutlinedBorder).side;
      expect(side.width, 3);
      await _expectVisibleBorder(
        tester,
        boundaryKey,
        button: material,
        background: LightTheme().data.snackBarTheme.backgroundColor!,
      );
    }
    expect(tester.takeException(), isNull);
  });
}

Widget _app(GlobalKey boundaryKey, Widget button) => MaterialApp(
  theme: LightTheme().data,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: boundaryKey,
        child: ColoredBox(
          color: Colors.white,
          child: SizedBox(width: 320, height: 80, child: Center(child: button)),
        ),
      ),
    ),
  ),
);

Finder _buttonMaterial(GlobalKey boundaryKey) =>
    find.descendant(of: find.byKey(boundaryKey), matching: find.byType(Material)).first;

Future<void> _expectVisibleBorder(
  WidgetTester tester,
  GlobalKey boundaryKey, {
  Finder? button,
  Color background = Colors.white,
}) async {
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final boundaryRect = tester.getRect(find.byKey(boundaryKey));
  final buttonRect = tester.getRect(button ?? _buttonMaterial(boundaryKey));
  final contrast = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final x = (buttonRect.center.dx - boundaryRect.left).floor();
      final top = (buttonRect.top - boundaryRect.top).floor();
      var maximumContrast = 1.0;
      // The top centre is clear of text/icons for every button shape. Inspect
      // its actual paint, since an opaque ink overlay can hide a correct side.
      for (var y = top; y < top + 3; y++) {
        final offset = (y * image.width + x) * 4;
        final color = Color.fromARGB(bytes[offset + 3], bytes[offset], bytes[offset + 1], bytes[offset + 2]);
        final foregroundLuminance = color.computeLuminance() + 0.05;
        final backgroundLuminance = background.computeLuminance() + 0.05;
        maximumContrast = math.max(
          maximumContrast,
          math.max(foregroundLuminance, backgroundLuminance) / math.min(foregroundLuminance, backgroundLuminance),
        );
      }
      return maximumContrast;
    } finally {
      image.dispose();
    }
  });
  expect(contrast, greaterThanOrEqualTo(3), reason: 'The painted focus border must stay distinct from its surface');
}
