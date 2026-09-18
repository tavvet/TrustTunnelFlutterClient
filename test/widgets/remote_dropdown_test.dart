import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/theme/light_theme.dart';
import 'package:trusttunnel/widgets/menu/custom_dropdown_menu.dart';

void main() {
  testWidgets('TV dropdown selects with D-pad and returns focus to the form', (tester) async {
    String? selected;
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: LightTheme().data,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              CustomDropdownMenu<String>.expanded(
                value: 'QUIC',
                values: const ['QUIC', 'HTTP/2'],
                toText: (value) => value,
                labelText: 'Protocol',
                onChanged: (value) => selected = value,
              ),
              FilledButton(onPressed: () => submitted = true, child: const Text('Submit')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, 'HTTP/2');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(submitted, isTrue);
  });
}
