import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aksharsevak/screens/meetings_screen.dart';
import 'support.dart';

void main() {
  testWidgets('meetings list, open a meeting, add a donor and a program item from the phone screens', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (f, s) = await setupStore();
    await tester.pumpWidget(MaterialApp(home: MeetingsScreen(store: s, onSignOut: () {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ravi Sabha'), findsOneWidget);
    await tester.tap(find.textContaining('Ravi Sabha'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing added yet.'), findsOneWidget);

    // program item
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Item'), 'Kirtan');
    await tester.enterText(find.widgetWithText(TextField, 'Presenter'), 'Sevak');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Kirtan'), findsOneWidget);
    expect(find.textContaining('5:00 PM'), findsOneWidget);

    // donor tab
    await tester.tap(find.text('Donors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add donor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ramesh');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Ramesh'), findsOneWidget);
    expect(f.docs.keys.where((k) => k.startsWith('donor:')).length, 1);

    // someone else deletes the meeting: the screen says so
    f.docs.removeWhere((k, v) => k.startsWith('meeting:'));
    await s.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('deleted by someone else'), findsOneWidget);
    s.dispose();
  });

  testWidgets('a person who is not confirmed can read but sees no add buttons', (tester) async {
    final (f, s) = await setupStore();
    s.canWrite = false;
    await tester.pumpWidget(MaterialApp(home: MeetingsScreen(store: s, onSignOut: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ravi Sabha'));
    await tester.pumpAndSettle();
    expect(find.text('Add item'), findsNothing);
    s.dispose();
  });
}
