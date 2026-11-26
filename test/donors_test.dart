import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:aksharsevak/donor_name.dart';
import 'package:aksharsevak/screens/meetings_screen.dart';
import 'support.dart';

void main() {
  test('how a donor is shown matches the back office', () {
    final r = {'name': 'Ramesh Patel', 'kind': 'satsangi', 'company': 'Patel Hardware'};
    expect(donorText(r), 'Ramesh Patel (Patel Hardware)');
    expect(donorText(r, family: true), 'Ramesh Patel & Family (Patel Hardware)');
    expect(donorText(r, style: 'name'), 'Ramesh Patel');
    expect(donorText(r, style: 'company', family: true), 'Patel Hardware');
    expect(donorText({'name': 'Ramesh Patel', 'kind': 'satsangi'}, style: 'company'), 'Ramesh Patel');
    expect(donorText({'name': 'Patel Hardware', 'kind': 'company', 'company': 'x'}, family: true), 'Patel Hardware');
  });
  test('the directory is searched by name or company, names that start with it first', () {
    final all = [
      {'name': 'Ramesh Patel', 'kind': 'satsangi', 'company': 'Zenith'},
      {'name': 'Mahesh Shah', 'kind': 'satsangi'},
      {'name': 'Patel Hardware', 'kind': 'company'},
      {'name': 'Anil Kumar', 'kind': 'satsangi', 'company': 'Patel Motors'},
    ];
    expect(matchContacts(all, 'patel').map((c) => c['name']), ['Patel Hardware', 'Ramesh Patel', 'Anil Kumar']);
    expect(matchContacts(all, ' '), isEmpty);
    expect(matchContacts(all, 'zzz'), isEmpty);
  });

  testWidgets('a donor is picked from the directory with & Family, or typed once and saved to the directory', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (f, s) = await setupStore();
    expect(await s.addContact('Ramesh Patel', 'satsangi', 'Patel Hardware', false), isTrue);
    expect(await s.addContact('ramesh  patel', 'satsangi', 'patel hardware', false), isFalse);
    await tester.pumpWidget(MaterialApp(home: MeetingsScreen(store: s, onSignOut: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ravi Sabha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Donors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add donor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Rame');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ramesh Patel (Patel Hardware)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('& Family'));
    await tester.pumpAndSettle();
    expect(find.text('On the slide: Ramesh Patel & Family (Patel Hardware)'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Ramesh Patel & Family (Patel Hardware)'), findsOneWidget);
    final donor = s.donorsOf(s.meetings.first.id).single.body;
    expect(donor['contactId'], s.contacts.single.id);
    expect(donor['family'], true);

    // a visitor, typed once and kept in the directory
    await tester.tap(find.text('Add donor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Visitor Shah');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to the donor directory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(s.contacts.map((c) => c.body['name']), containsAll(['Ramesh Patel', 'Visitor Shah']));
    expect(f.docs.keys.where((k) => k.startsWith('donor-contact:')).length, 2);
    expect(s.donorsOf(s.meetings.first.id).length, 2);
    s.dispose();
  });
}
