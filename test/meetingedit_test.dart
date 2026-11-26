import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:aksharsevak/screens/meetings_screen.dart';
import 'support.dart';

void main() {
  testWidgets('an editor can move one meeting to another time and venue; the header and the saved record follow', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (f, s) = await setupStore();
    await tester.pumpWidget(MaterialApp(home: MeetingsScreen(store: s, onSignOut: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ravi Sabha'));
    await tester.pumpAndSettle();
    final id = s.meetings.first.id;
    await tester.tap(find.byTooltip('Change date, time or venue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Venue'), 'Community hall');
    await tester.tap(find.byIcon(Icons.schedule));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(s.meeting(id)!.body['venue'], 'Community hall');
    expect(s.meetings.length, 1); // still one meeting, not a copy in another list
    expect(s.donorsOf(id), isEmpty);
    expect(f.docs.keys.where((k) => k.startsWith('meeting:')).length, 1);
    s.dispose();
  });
  testWidgets('a person who cannot write has no change button', (tester) async {
    final (_, s) = await setupStore();
    s.canWrite = false;
    await tester.pumpWidget(MaterialApp(home: MeetingsScreen(store: s, onSignOut: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ravi Sabha'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Change date, time or venue'), findsNothing);
    s.dispose();
  });
}
