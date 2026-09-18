import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/theme/light_theme.dart';
import 'package:trusttunnel/widgets/inputs/custom_text_field.dart';

void main() {
  testWidgets('D-pad leaves text field scopes and reaches the submit button on TV', (tester) async {
    var submitted = false;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            const CustomTextField(label: 'First', autofocus: true),
            const SizedBox(height: 24),
            const CustomTextField(label: 'Second'),
            FilledButton(onPressed: () => submitted = true, child: const Text('Submit')),
          ],
        ),
      ),
    );
    await tester.pump();
    final fields = tester.widgetList<EditableText>(find.byType(EditableText)).toList();
    expect(fields[0].focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(fields[1].focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(submitted, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(fields[1].focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(fields[0].focusNode.hasFocus, isTrue);
  });

  testWidgets('remote select reopens the keyboard after it was dismissed', (tester) async {
    await tester.pumpWidget(_app(const CustomTextField(label: 'Server', autofocus: true)));
    await tester.pump();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);

    tester.testTextInput.hide();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(tester.testTextInput.isVisible, isTrue);
    expect(field.focusNode.hasFocus, isTrue);
  });

  testWidgets('remote select still activates text field suffix buttons', (tester) async {
    var toggled = false;
    await tester.pumpWidget(
      _app(
        CustomTextField.customSuffixIcon(
          label: 'Password',
          autofocus: true,
          suffixIcon: IconButton(onPressed: () => toggled = true, icon: const Icon(Icons.visibility)),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(toggled, isTrue);
  });

  testWidgets('ordinary navigation mode preserves text cursor arrow keys', (tester) async {
    await tester.pumpWidget(
      _app(
        const CustomTextField(value: 'server', label: 'Server', autofocus: true),
        navigationMode: NavigationMode.traditional,
      ),
    );
    await tester.pump();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    field.controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(field.controller.selection.baseOffset, 2);
    expect(field.focusNode.hasFocus, isTrue);
  });
}

Widget _app(Widget child, {NavigationMode navigationMode = NavigationMode.directional}) => MaterialApp(
  theme: LightTheme().data,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(navigationMode: navigationMode),
    child: child!,
  ),
  home: Scaffold(body: child),
);
