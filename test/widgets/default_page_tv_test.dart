import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/theme/light_theme.dart';
import 'package:trusttunnel/widgets/default_page.dart';

void main() {
  testWidgets('TV empty state shows the entire Create action without scrolling at 960x540', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 540);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const contentKey = Key('page-content');
    await tester.pumpWidget(
      MaterialApp(
        theme: LightTheme().data,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: child!,
        ),
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 80),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Scaffold(
                    appBar: AppBar(title: const Text('Servers'), toolbarHeight: 64),
                    body: SizedBox.expand(
                      key: contentKey,
                      child: DefaultPage.responsive(
                        title: 'Create your first server',
                        descriptionText: 'Create a server for secure and anonymous data transfer',
                        imagePath: AssetImages.server,
                        buttonText: 'Create',
                        onButtonPressed: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final contentRect = tester.getRect(find.byKey(contentKey));
    final actionRect = tester.getRect(find.widgetWithText(FilledButton, 'Create'));
    expect(actionRect.top, greaterThanOrEqualTo(contentRect.top));
    expect(actionRect.bottom, lessThanOrEqualTo(contentRect.bottom));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone empty state retains its normal illustration size', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: LightTheme().data,
        home: const Scaffold(
          body: DefaultPage.responsive(title: 'Create your first server', imagePath: AssetImages.server),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Image)).height, 270);
  });
}
