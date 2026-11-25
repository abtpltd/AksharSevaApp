import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:aksharsevak/screens/meeting_screen.dart';
import 'package:aksharsevak/screens/slide_screens.dart';
import 'package:aksharsevak/slide_view.dart';
import 'package:aksharsevak/store.dart';
import 'support.dart';

// a 1x1 png
final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Fake seeded() {
  final f = Fake();
  void slide(int n, double pos, Map<String, dynamic> block) => f.put(rec('slide', id(n), {'id': id(n), 'meetingId': mid, 'pos': pos, 'block': {...block, 'id': id(n)}}));
  slide(1, 1, {'kind': 'opening'});
  slide(2, 2, {'kind': 'text', 'label': 'Ravi Sabha', 'heading': 'Every Saturday', 'lines': ['Sports 2 PM', 'Native Sabha 3 PM']});
  slide(3, 3, {'kind': 'prasad', 'label': 'Prasad Seva'});
  slide(4, 4, {'kind': 'closing'});
  return f;
}

List<String> order(Store s) => [for (final r in s.slidesOf(mid)) r.id];

void main() {
  test('a moved slide gets a place between its new neighbours, and only it is saved', () async {
    expect(placeBetween([], 0), 1);
    expect(placeBetween([1, 2], 0), 0);
    expect(placeBetween([1, 2], 2), 3);
    expect(placeBetween([1, 2], 1), 1.5);
    final f = seeded();
    final (_, s) = await setupStoreWith(f);
    f.log.clear();
    expect(await s.moveSlide(mid, 0, 3), true); // opening goes between prasad and closing
    expect(order(s), [id(2), id(3), id(1), id(4)]);
    expect(f.log.where((l) => l.startsWith('PUT')).length, 1);
    expect(await s.moveSlide(mid, 3, 0), true); // closing to the front
    expect(order(s).first, id(4));
    f.log.clear();
    expect(await s.moveSlide(mid, 1, 1), true); // dropped where it was: nothing saved
    expect(await s.moveSlide(mid, 1, 2), true); // one step down is the same place
    expect(f.log.where((l) => l.startsWith('PUT')), isEmpty);
    expect(await s.moveSlide(mid, 9, 0), false);
    s.dispose();
  });

  test('a move another phone made first shows theirs and says so', () async {
    final f = seeded();
    final (_, s) = await setupStoreWith(f);
    f.put(rec('slide', id(2), {'id': id(2), 'meetingId': mid, 'pos': 9.0, 'block': {'id': id(2), 'kind': 'text', 'heading': 'x', 'lines': []}}, 5));
    expect(await s.moveSlide(mid, 1, 0), false);
    expect(s.message, contains('Someone else changed'));
    s.dispose();
  });

  test('pictures: only what the back office accepts is drawn', () {
    expect(pictureBytes('data:image/png;base64,${base64Encode(png)}'), isNotNull);
    for (final v in ['data:image/svg+xml;base64,AAAA', 'http://x/y.png', 'data:image/png;base64,@@@', 5, null]) expect(pictureBytes(v), isNull);
    expect(colorFrom('#C00000'), const Color(0xFFC00000));
    expect(colorFrom('red'), isNull);
    expect(slideTitle({'kind': 'opening'}), 'Opening slide');
    expect(slideTitle({'kind': 'text', 'heading': 'H', 'label': 'L'}), 'H');
    expect(phoneEditable({'kind': 'text'}) && phoneEditable({'kind': 'poster'}) && !phoneEditable({'kind': 'canvas'}), true);
  });

  testWidgets('every slide kind and a free-layout slide draw without errors', (tester) async {
    final blocks = <Map>[
      {'kind': 'opening'}, {'kind': 'closing'}, {'kind': 'text', 'label': 'L', 'heading': 'H', 'lines': ['a']}, {'kind': 'list', 'heading': 'H', 'lines': ['a', 'b']},
      {'kind': 'table', 'rows': [['a', 'b']]}, {'kind': 'prasad', 'label': 'P'}, {'kind': 'poster', 'heading': 'H', 'lines': [], 'image': 'data:image/png;base64,${base64Encode(png)}'},
      {'kind': 'poster', 'heading': 'No picture', 'lines': [], 'image': ''},
      {'kind': 'canvas', 'chrome': 'none', 'bg': '#112233', 'elements': [
        {'type': 'text', 'x': 1, 'y': 1, 'w': 4, 'h': 1, 'rot': 10, 'text': 'Hello', 'size': 30, 'bold': true, 'italic': true, 'underline': true, 'color': '#FFFFFF', 'align': 'center', 'valign': 'middle', 'fill': '#000000', 'border': '#FF0000', 'borderW': 2},
        {'type': 'shape', 'x': 1, 'y': 3, 'w': 2, 'h': 1, 'rot': 0, 'shape': 'ellipse', 'fill': '#00FF00', 'line': '#000000', 'lineW': 2},
        {'type': 'shape', 'x': 4, 'y': 3, 'w': 2, 'h': 1, 'rot': 0, 'shape': 'rect', 'fill': '#00FF00', 'line': '', 'lineW': 1},
        {'type': 'shape', 'x': 7, 'y': 3, 'w': 2, 'h': 1, 'rot': 0, 'shape': 'line', 'fill': '', 'line': '#000000', 'lineW': 3},
        {'type': 'image', 'x': 1, 'y': 5, 'w': 1, 'h': 1, 'rot': 0, 'src': 'data:image/png;base64,${base64Encode(png)}'},
        {'type': 'image', 'x': 1, 'y': 5, 'w': 1, 'h': 1, 'rot': 0, 'src': 'javascript:1'},
        'not a map', {'type': 'weird'},
      ]},
      {'kind': 'something-new'},
    ];
    for (final b in blocks) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SlideView(block: b, donors: [{'name': 'Ramesh', 'occasion': 'Birthday'}])))));
      expect(tester.takeException(), isNull, reason: '${b['kind']}');
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SlideView(block: blocks[0]))));
    expect(find.text('ANNOUNCEMENTS'), findsOneWidget);
  });

  testWidgets('slides tab: thumbnails, drag handles, a round + button, tap opens the preview, swipe goes on', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (_, s) = await setupStoreWith(seeded());
    await tester.pumpWidget(MaterialApp(home: MeetingScreen(store: s, meetingId: mid)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slides'));
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(4));
    expect(find.text('Add slide'), findsNothing); // the round button carries only a plus
    expect(find.byTooltip('Add slide'), findsOneWidget);
    expect(find.byType(SlideView), findsNWidgets(4));
    await tester.tap(find.text('2. Every Saturday'));
    await tester.pumpAndSettle();
    expect(find.text('Slide 2 of 4'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Slide 3 of 4'), findsOneWidget);
    expect(find.text('Change'), findsNothing); // a prasad slide is changed on the back office
    expect(find.textContaining('back office'), findsOneWidget);
    s.dispose();
  });

  testWidgets('add a slide: the preview below follows the typing; a picture slide saves its picture', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    picturePicker = (_) async => PickedPicture(Uint8List.fromList(png), 'png');
    addTearDown(() => picturePicker = pickFromPhone);
    final f = seeded();
    final (_, s) = await setupStoreWith(f);
    await tester.pumpWidget(MaterialApp(home: MeetingScreen(store: s, meetingId: mid)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slides'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add slide'));
    await tester.pumpAndSettle();
    expect(find.text('Preview'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Heading'), 'Diwali night');
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('form-preview')), matching: find.text('Diwali night')), findsOneWidget);
    // empty save is refused with a plain line
    await tester.enterText(find.widgetWithText(TextField, 'Heading'), '');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('Write a heading'), findsOneWidget);
    // picture slide without a picture is refused, with one it is saved
    await tester.tap(find.text('Picture'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Heading'), 'Poster night');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('Add a picture'), findsOneWidget);
    await tester.tap(find.text('Add picture'));
    await tester.pumpAndSettle();
    expect(find.text('Change picture'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = f.docs.values.where((d) => d['kind'] == 'slide' && (d['body'] as Map)['block']['heading'] == 'Poster night').single['body'] as Map;
    expect(saved['block']['kind'], 'poster');
    expect(saved['block']['image'], startsWith('data:image/png;base64,'));
    expect(saved['block']['id'], saved['id']);
    expect(saved['pos'], 5);
    s.dispose();
  });

  testWidgets('a picture that is too big is refused', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    picturePicker = (_) async => PickedPicture(Uint8List(5 * 1024 * 1024), 'jpeg');
    addTearDown(() => picturePicker = pickFromPhone);
    final (_, s) = await setupStoreWith(seeded());
    await tester.pumpWidget(MaterialApp(home: MeetingScreen(store: s, meetingId: mid)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slides'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add slide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Picture'));
    await tester.pump();
    await tester.tap(find.text('Add picture'));
    await tester.pumpAndSettle();
    expect(find.textContaining('too big'), findsOneWidget);
    expect(find.text('Add picture'), findsOneWidget);
    s.dispose();
  });

  testWidgets('a person who cannot write sees the preview but no add, drag or change', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (_, s) = await setupStoreWith(seeded());
    s.canWrite = false;
    await tester.pumpWidget(MaterialApp(home: MeetingScreen(store: s, meetingId: mid)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slides'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add slide'), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    await tester.tap(find.text('2. Every Saturday'));
    await tester.pumpAndSettle();
    expect(find.text('Slide 2 of 4'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    s.dispose();
  });
}
