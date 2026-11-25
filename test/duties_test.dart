import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:aksharsevak/screens/meetings_screen.dart';
import 'package:aksharsevak/theme.dart';
import 'support.dart';

// My duties: program items of coming meetings that name this person (Ed) as presenter.
void item(Fake f, int n, String what, String who, int minutes, num pos, {String meeting = mid}) =>
    f.put(rec('program-item', id(n), {'id': id(n), 'meetingId': meeting, 'pos': pos, 'item': what, 'presenter': who, 'minutes': minutes, 'medium': 'Hall'}));

void main() {
  test('only coming items that name me, with their start time, soonest first', () async {
    final (f, s) = await setupStore();
    const old = '66666666-6666-4666-8666-666666666666';
    f.put(rec('meeting', old, {'id': old, 'sabhaId': sid, 'date': '2026-11-01', 'start': '17:00', 'venue': 'Hall', 'mc': ''}));
    item(f, 1, 'Opening prayer', 'Someone', 10, 1);
    item(f, 2, 'Kirtan', 'ed', 15, 2); // me, capitals ignored
    item(f, 3, 'Talk', 'Ed Patel', 20, 3); // my name inside a longer one
    item(f, 4, 'Quiz', 'Bob', 5, 4);
    item(f, 5, 'No presenter', '', 5, 5);
    item(f, 6, 'Old duty', 'Ed', 5, 1, meeting: old); // meeting has passed
    await s.refresh();
    final d = s.myDuties(today: '2026-11-25');
    expect(d.map((x) => x.item.body['item']), ['Kirtan', 'Talk']);
    expect(d.first.startMinutes, 17 * 60 + 10); // after the 10-minute prayer
    expect(d.last.startMinutes, 17 * 60 + 25);
  });

  test('a person with no name gets nothing, and a very short presenter text does not match everybody', () async {
    final (f, s) = await setupStore();
    item(f, 1, 'X', 'e', 5, 1);
    await s.refresh();
    expect(s.myDuties(today: '2026-11-25'), isEmpty);
  });

  testWidgets('the My duties screen lists them, and says so when there are none', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (f, s) = await setupStore();
    addTearDown(s.dispose);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: MeetingsScreen(store: s, onSignOut: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My duties'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No duties yet'), findsOneWidget);

    item(f, 1, 'Kirtan', 'Ed', 15, 1);
    await s.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Kirtan'), findsOneWidget);
    expect(find.textContaining('5:00 PM'), findsOneWidget);
  });
}
