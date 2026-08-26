import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/screens/stories/submit_story_screen.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SubmitStoryScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'submit button is always visible in a sticky footer on a phone-sized viewport',
      (tester) async {
    await pumpAt(tester, const Size(390, 844)); // iPhone 14-ish

    expect(tester.takeException(), isNull);
    // No scrolling needed: the button lives in bottomNavigationBar, not the
    // scrollable form content, so it must be visible immediately.
    expect(find.text('SUBMIT STORY 📖'), findsOneWidget);

    // Scrolling the form to its end must not push the button away either.
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('SUBMIT STORY 📖'), findsOneWidget);
  });

  testWidgets(
      'submit button is always visible in a sticky footer on a desktop-sized viewport',
      (tester) async {
    await pumpAt(tester, const Size(1280, 900));

    expect(tester.takeException(), isNull);
    expect(find.text('SUBMIT STORY 📖'), findsOneWidget);

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('SUBMIT STORY 📖'), findsOneWidget);
  });
}
