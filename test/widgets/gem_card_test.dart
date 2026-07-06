// Widget tests for the reusable [GemCard]: that a fully-populated gem renders
// every optional slot, that a sparse gem collapses the empty slots (and shows
// the "New" tag instead of fabricated metrics), and that the save toggle is
// driven by state + a callback rather than touching persistence itself.
//
// Cards are built without a photoUrl so they take the brand-tinted fallback
// path and never hit the network, keeping the tests fast and deterministic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:explorife/models/gem.dart';
import 'package:explorife/screens/explore/gem_card.dart';

Gem _gem({
  String id = 'g1',
  String name = 'Hidden Rooftop',
  String? category,
  String? tagline,
  String? dropperHandle,
}) =>
    Gem(
      id: id,
      gemName: name,
      category: category,
      tagline: tagline,
      dropperHandle: dropperHandle,
      savedAt: DateTime(2026, 1, 1),
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 360, child: child)),
      ),
    );

void main() {
  setUpAll(() {
    // Don't reach out to fonts.google.com during tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('renders every slot for a fully-populated gem', (tester) async {
    await tester.pumpWidget(_host(GemCard(
      gem: _gem(
        category: 'hiking',
        tagline: 'best sunset in town',
        dropperHandle: 'toan',
      ),
      categoryIcon: Icons.hiking,
      variant: GemCardVariant.full,
      isSaved: true,
      distanceLabel: '1.2 km',
      rating: 4.5,
      savesLabel: '320 saves',
      onToggleSave: () {},
    )));

    expect(find.text('Hidden Rooftop'), findsOneWidget);
    expect(find.text('best sunset in town'), findsOneWidget);
    expect(find.text('Hiking'), findsOneWidget); // category pill
    expect(find.text('@toan'), findsOneWidget);
    expect(find.text('1.2 km'), findsOneWidget); // distance pill
    expect(find.text('4.5'), findsOneWidget); // rating
    expect(find.text('320 saves'), findsOneWidget);
    // Real metrics present → no "New" placeholder.
    expect(find.text('New'), findsNothing);
    // isSaved → solid bookmark.
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsNothing);
  });

  testWidgets('collapses empty slots and shows "New" for a sparse gem',
      (tester) async {
    await tester.pumpWidget(_host(GemCard(
      gem: _gem(id: 'g2', name: 'Plain Spot'),
      categoryIcon: Icons.public,
      isSaved: false,
      onToggleSave: () {},
    )));

    expect(find.text('Plain Spot'), findsOneWidget);
    // No community metrics yet → the "New" tag stands in.
    expect(find.text('New'), findsOneWidget);
    // No tagline, no category pill, no distance pill.
    expect(find.byIcon(Icons.near_me), findsNothing); // distance pill icon
    // Not saved → outline bookmark.
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsNothing);
  });

  testWidgets('save toggle fires its callback without firing the card tap',
      (tester) async {
    var saveTaps = 0;
    var cardTaps = 0;
    await tester.pumpWidget(_host(GemCard(
      gem: _gem(category: 'food'),
      categoryIcon: Icons.restaurant,
      isSaved: false,
      onTap: () => cardTaps++,
      onToggleSave: () => saveTaps++,
    )));

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pump();

    expect(saveTaps, 1);
    expect(cardTaps, 0);
  });

  testWidgets('omits the save toggle entirely when no callback is given',
      (tester) async {
    await tester.pumpWidget(_host(GemCard(
      gem: _gem(),
      categoryIcon: Icons.public,
    )));

    expect(find.byIcon(Icons.bookmark_border), findsNothing);
    expect(find.byIcon(Icons.bookmark), findsNothing);
  });
}
