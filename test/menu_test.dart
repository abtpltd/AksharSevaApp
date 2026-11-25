import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aksharsevak/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:aksharsevak/screens/meetings_screen.dart';
import 'package:aksharsevak/theme.dart';
import 'package:aksharsevak/vault.dart';
import 'support.dart';

const para = '44444444-4444-4444-8444-444444444444';
const pm = '55555555-5555-4555-8555-555555555555';

void addParaSabha(Fake f) {
  f.put(rec('sabha', para, {'id': para, 'name': 'Para Sabha', 'kind': 'flexible'}));
  f.put(rec('meeting', pm, {'id': pm, 'sabhaId': para, 'date': '2026-12-02', 'start': '19:00', 'venue': 'Home', 'mc': ''}));
}

void main() {
  scrollerTests();
  pushTests();
  cursorTests();
  screenTests();
  test('Ravi (weekly) is a regular meeting, Para (flexible) is called as needed', () async {
    final (f, s) = await setupStore();
    f.docs['sabha:$sid']!['body']['kind'] = 'weekly';
    addParaSabha(f);
    await s.refresh();
    expect(s.isAsNeeded(s.meeting(mid)!), false);
    expect(s.isAsNeeded(s.meeting(pm)!), true);
  });

  test('notices: the first read says nothing, other people\'s changes are reported, my own are not', () async {
    final (f, s) = await setupStore();
    expect(s.notices, isEmpty);
    await s.add('donor', mid, {'name': 'Mine', 'occasion': ''}); // my own add
    await s.refresh(quiet: true);
    expect(s.notices, isEmpty);

    f.put(rec('donor', id(1), {'id': id(1), 'meetingId': mid, 'pos': 5, 'name': 'Other', 'occasion': ''}));
    f.put(rec('donor', id(2), {'id': id(2), 'meetingId': mid, 'pos': 6, 'name': 'Other2', 'occasion': ''}));
    f.put(rec('program-item', id(3), {'id': id(3), 'meetingId': mid, 'pos': 1, 'item': 'Kirtan', 'medium': 'Live', 'presenter': '', 'minutes': 5, 'remark': ''}));
    addParaSabha(f);
    await s.refresh(quiet: true);
    final t = s.notices.map((n) => n.text).toList();
    expect(t, contains('2 donors added to Ravi Sabha · 2026-11-29'));
    expect(t, contains('1 program item added to Ravi Sabha · 2026-11-29'));
    expect(t, contains('New meeting: Para Sabha · 2026-12-02'));
    expect(s.unread, 3);

    // a change by someone else, and a removal
    f.put(rec('donor', id(1), {'id': id(1), 'meetingId': mid, 'pos': 5, 'name': 'Changed', 'occasion': ''}, 2));
    f.docs.remove('donor:${id(2)}');
    await s.refresh(quiet: true);
    expect(s.notices.first.text, anyOf('1 donor removed from Ravi Sabha · 2026-11-29', '1 donor changed in Ravi Sabha · 2026-11-29'));
    expect(s.notices.map((n) => n.text), containsAll(['1 donor changed in Ravi Sabha · 2026-11-29', '1 donor removed from Ravi Sabha · 2026-11-29']));

    // a whole meeting deleted: one line, not one per item
    final before = s.notices.length;
    f.docs.remove('meeting:$mid');
    f.docs.removeWhere((k, v) => v['body']['meetingId'] == mid);
    await s.refresh(quiet: true);
    expect(s.notices.length, before + 1);
    expect(s.notices.first.text, 'Meeting deleted: Ravi Sabha · 2026-11-29');
    expect(s.notices.first.meetingId, isNull);

    s.markAllRead();
    expect(s.unread, 0);
  });

  testWidgets('side menu: entries, meetings as needed, notifications, my duties; title bar is dark', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (f, s) = await setupStore();
    addTearDown(s.dispose);
    f.docs['sabha:$sid']!['body']['kind'] = 'weekly';
    addParaSabha(f);
    await s.refresh();
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: MeetingsScreen(store: s, onSignOut: () {})));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor, null); // from the theme
    expect(Theme.of(tester.element(find.byType(AppBar))).appBarTheme.backgroundColor, maroon);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    for (final t in ['Home', 'My duties', 'Notifications', 'Sabhas', 'Ravi Sabha', 'Meetings as needed', 'Sign out']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('Para Sabha'), findsNothing); // not weekly: only under Meetings as needed

    await tester.tap(find.text('Meetings as needed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Para Sabha'), findsOneWidget);
    expect(find.textContaining('Ravi Sabha'), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My duties'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No duties yet'), findsOneWidget);

    f.put(rec('donor', id(1), {'id': id(1), 'meetingId': mid, 'pos': 5, 'name': 'Other', 'occasion': ''}));
    await s.refresh(quiet: true);
    await tester.pumpAndSettle();
    expect(s.unread, 2); // the Para meeting and the donor
    expect(find.text('2'), findsWidgets); // bell badge
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('1 donor added to Ravi Sabha · 2026-11-29'), findsOneWidget);
    expect(s.unread, 0);
  });

  test('the vault keeps and forgets a token', () async {
    final v = MemoryVault();
    expect(await v.read(), isNull);
    await v.write('abc');
    expect(await v.read(), 'abc');
    await v.clear();
    expect(await v.read(), isNull);
  });
}

void scrollerTests() {
  test('scroller messages: I add one at the end, another person\'s appears on the next read, and neither makes a notice', () async {
    final (f, s) = await setupStore();
    expect(s.tickerOf(mid), isEmpty);
    expect(await s.add('ticker', mid, {'text': 'Parking is full'}), true, reason: s.message);
    expect(s.tickerOf(mid).map((r) => r.body['text']), ['Parking is full']);
    const other = '66666666-6666-4666-8666-666666666666';
    f.put(rec('ticker', other, {'id': other, 'meetingId': mid, 'pos': 9, 'text': 'Prasad after sabha'}));
    await s.refresh(quiet: true);
    expect(s.tickerOf(mid).map((r) => r.body['text']), ['Parking is full', 'Prasad after sabha']);
    expect(s.notices, isEmpty);
    expect(await s.delete(s.tickerOf(mid).first), true);
    expect(s.tickerOf(mid).length, 1);
  });
}

void pushTests() {
  test('device registration: sent with the token, a server without push is not an error, sign-out never fails', () async {
    final seen = <String>[];
    var status = 200;
    final api = Api('http://localhost:3000', client: MockClient((r) async {
      seen.add('${r.method} ${r.url.path} ${r.body}');
      return http.Response(status == 200 ? '{"ok":true}' : '{"error":"Push messages are not set up on this server"}', status);
    }));
    api.useToken('t');
    expect(await api.registerDevice('x' * 30), true);
    expect(seen.single, startsWith('POST /api/push/register'));
    status = 503;
    expect(await api.registerDevice('x' * 30), false);
    status = 500;
    await api.forgetDevice('x' * 30); // does not throw
    status = 401;
    await expectLater(api.registerDevice('x' * 30), throwsA(isA<ApiError>()));
  });
}

void cursorTests() {
  test('announcer place: the first tap makes it, later taps move it (the last of quick taps wins), a competing move is taken, finishing removes it', () async {
    final (f, s) = await setupStore();
    expect(s.cursorOf(mid), isNull);
    await s.setCursor(mid, 0);
    expect(s.cursorOf(mid)!.body['donor'], 0);
    final first = s.cursorOf(mid)!.id;
    final a = s.setCursor(mid, 1);
    final b = s.setCursor(mid, 2);
    final c = s.setCursor(mid, 3);
    await Future.wait([a, b, c]);
    expect(s.cursorOf(mid)!.id, first);
    expect(s.cursorOf(mid)!.body['donor'], 3);
    // another phone moved it meanwhile (version clash): this phone reads theirs and sends its own tap on top
    f.docs['cursor:$first']!['version'] = 40;
    f.docs['cursor:$first']!['body']['donor'] = 9;
    await s.setCursor(mid, 4);
    expect(s.cursorOf(mid)!.body['donor'], 4);
    expect(s.cursorOf(mid)!.version, 41);
    await s.endCursor(mid);
    expect(s.cursorOf(mid), isNull);
    expect(f.docs.containsKey('cursor:$first'), false);
  });
}

void screenTests() {
  test('hall screen settings: defaults, a change makes the record, the next change updates it, a clash is taken and the change kept', () async {
    final (f, s) = await setupStore();
    expect(s.screenOf(mid), {'tickerOn': true, 'tickerSpeed': 3, 'autoDonors': false, 'autoSpeed': 4});
    expect(await s.setScreen(mid, {'tickerOn': false}), true, reason: s.message);
    expect(s.screenOf(mid)['tickerOn'], false);
    expect(await s.setScreen(mid, {'tickerSpeed': 5}), true);
    expect(s.screenOf(mid), {'tickerOn': false, 'tickerSpeed': 5, 'autoDonors': false, 'autoSpeed': 4});
    final key = f.docs.keys.firstWhere((k) => k.startsWith('screen:'));
    f.docs[key]!['version'] = 30; // another phone changed it first
    f.docs[key]!['body']['autoDonors'] = true;
    expect(await s.setScreen(mid, {'tickerSpeed': 1}), true);
    expect(s.screenOf(mid)['tickerSpeed'], 1);
    expect(s.screenOf(mid)['autoDonors'], true); // their change is kept too
  });

  test('hall slide remote: none at first, Next and Back move it within the slides, other settings keep it', () async {
    final (f, s) = await setupStore();
    for (final h in ['One', 'Two', 'Three']) {
      await s.add('slide', mid, {'block': {'kind': 'text', 'label': 'L', 'heading': h, 'lines': ['a']}});
    }
    final n = s.slidesOf(mid).length;
    expect(n, 3);
    expect(s.hallSlide(mid), isNull);
    expect(await s.moveHallSlide(mid, 1), true, reason: s.message);
    expect(s.hallSlide(mid), 1);
    expect(await s.moveHallSlide(mid, -1), true);
    expect(s.hallSlide(mid), 0);
    expect(await s.moveHallSlide(mid, -1), false); // already at the first slide
    expect(s.hallSlide(mid), 0);
    await s.moveHallSlide(mid, 1);
    await s.setScreen(mid, {'tickerSpeed': 2});
    expect(s.hallSlide(mid), 1); // a settings change does not lose the position
    final key = f.docs.keys.firstWhere((k) => k.startsWith('screen:'));
    expect(f.docs[key]!['body']['slide'], 1);
    for (var i = 0; i < n + 2; i++) { await s.moveHallSlide(mid, 1); }
    expect(s.hallSlide(mid), n - 1); // never past the last slide
  });

  test('after the review: a read asked for while another runs is not lost; finishing removes every announcer place; ties pick the same record as the desktop', () async {
    final (f, s) = await setupStore();
    final a = s.refresh(quiet: true);
    f.put(rec('donor', id(7), {'id': id(7), 'meetingId': mid, 'pos': 9, 'name': 'Late', 'occasion': ''}));
    await s.refresh(quiet: true); // asked while the first is running: must still end with fresh data
    await a;
    expect(s.donorsOf(mid).map((r) => r.body['name']), contains('Late'));

    // two announcer places (two phones started together): Finish removes both
    f.put(rec('cursor', id(8), {'id': id(8), 'meetingId': mid, 'donor': 1}));
    f.put(rec('cursor', id(9), {'id': id(9), 'meetingId': mid, 'donor': 2}));
    await s.refresh(quiet: true);
    await s.endCursor(mid);
    await s.refresh(quiet: true);
    expect(s.cursorOf(mid), isNull);

    // equal versions: the larger id wins, as on the desktop
    f.put(rec('screen', id(1), {'id': id(1), 'meetingId': mid, 'tickerSpeed': 2}));
    f.put(rec('screen', id(2), {'id': id(2), 'meetingId': mid, 'tickerSpeed': 4}));
    await s.refresh(quiet: true);
    expect(s.screenOf(mid)['tickerSpeed'], 4);
  });
}
