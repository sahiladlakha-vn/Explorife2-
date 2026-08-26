// Widget tests for the reusable [NavItem]. Scope is deliberately narrow:
//   1. selected rendering — white (inverted) icon inside a solid, glowing
//      orange circle;
//   2. resting rendering — muted icon, transparent circle, no glow;
//   3. onTap fires its callback.
// Animation timing/curve is NOT under test — only the end-state styling that
// `isSelected` drives.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:explorife/core/theme/app_theme.dart';
import 'package:explorife/widgets/common/bottom_nav.dart';

Widget _host({required bool isSelected, VoidCallback? onTap}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: NavItem(
            icon: Icons.map_outlined,
            isSelected: isSelected,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('selected: white icon inside a glowing orange circle',
      (tester) async {
    await tester.pumpWidget(_host(isSelected: true));

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, Colors.white);

    final circle = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final decoration = circle.decoration as BoxDecoration;
    expect(decoration.color, AppTheme.primary);
    expect(decoration.boxShadow, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('resting: muted icon, transparent circle, no glow', (tester) async {
    await tester.pumpWidget(_host(isSelected: false));

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, AppTheme.lightMute);

    final circle = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final decoration = circle.decoration as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.boxShadow, isNull);
  });

  testWidgets('tap fires the callback once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(isSelected: false, onTap: () => taps++));

    await tester.tap(find.byType(NavItem));
    expect(taps, 1);
  });
}
