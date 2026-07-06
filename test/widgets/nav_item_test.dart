// Widget tests for the reusable [NavItem]. Scope is deliberately narrow:
//   1. selected rendering — orange icon sitting inside the warm pill;
//   2. resting rendering — gray icon, no pill (transparent);
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
  testWidgets('selected: orange icon inside the warm pill', (tester) async {
    await tester.pumpWidget(_host(isSelected: true));

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, AppTheme.primary);

    final pill = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final decoration = pill.decoration as BoxDecoration;
    expect(
      decoration.color,
      AppTheme.primary.withValues(alpha: AppTheme.navPillOpacity),
    );
  });

  testWidgets('resting: gray icon, no pill', (tester) async {
    await tester.pumpWidget(_host(isSelected: false));

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, AppTheme.textSecondary);

    final pill = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final decoration = pill.decoration as BoxDecoration;
    expect(decoration.color, Colors.transparent);
  });

  testWidgets('tap fires the callback once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(isSelected: false, onTap: () => taps++));

    await tester.tap(find.byType(NavItem));
    expect(taps, 1);
  });
}
