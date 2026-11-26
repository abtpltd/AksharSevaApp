import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aksharsevak/screens/meetings_screen.dart';
import 'package:aksharsevak/updates.dart';
import 'support.dart';

String release(String tag, {String? url, bool draft = false, bool pre = false, bool apk = true}) => jsonEncode({
      'tag_name': tag, 'draft': draft, 'prerelease': pre,
      'assets': apk ? [{'name': 'AksharSevak.apk', 'browser_download_url': url ?? 'https://github.com/abtpltd/AksharSevaApp/releases/download/$tag/AksharSevak.apk'}] : [],
    });
http.Client answer(String body, [int code = 200]) => MockClient((_) async => http.Response(body, code));

void main() {
  test('release tags name builds', () {
    expect(buildFromTag('v12'), 12);
    for (final t in ['12', 'v', 'v1.2', 'latest', 'vv3', 'v12345678901', null, 7]) expect(buildFromTag(t), isNull);
  });

  test('a newer build is offered, the same or an older one is not', () async {
    expect(await checkForUpdate(currentBuild: 5, client: answer(release('v6'))), isA<UpdateAvailable>());
    final r = await checkForUpdate(currentBuild: 5, client: answer(release('v9'))) as UpdateAvailable;
    expect((r.info.build, r.current), (9, 5));
    expect(await checkForUpdate(currentBuild: 6, client: answer(release('v6'))), isA<UpToDate>());
    expect(await checkForUpdate(currentBuild: 8, client: answer(release('v6'))), isA<UpToDate>());
  });

  test('anything odd from GitHub is "could not check", never an update', () async {
    for (final body in [release('v9', draft: true), release('v9', pre: true), release('v9', apk: false), release('latest'), release('v9', url: 'https://evil.example/AksharSevak.apk'), release('v9', url: 'http://github.com/abtpltd/AksharSevaApp/releases/download/v9/AksharSevak.apk'), 'not json', '[]', 'null']) {
      expect(await checkForUpdate(currentBuild: 1, client: answer(body)), isA<UpdateUnknown>(), reason: body);
    }
    expect(await checkForUpdate(currentBuild: 1, client: answer('{}', 403)), isA<UpdateUnknown>());
    expect(await checkForUpdate(currentBuild: 1, client: MockClient((_) async => throw Exception('offline'))), isA<UpdateUnknown>());
    expect(await checkForUpdate(currentBuild: 1, timeout: const Duration(milliseconds: 20), client: MockClient((_) async { await Future<void>.delayed(const Duration(seconds: 1)); return http.Response(release('v9'), 200); })), isA<UpdateUnknown>());
  });

  test('an app installed from Google Play never asks GitHub', () async {
    var asked = false;
    final r = await checkForUpdate(currentBuild: 1, installer: 'com.android.vending', client: MockClient((_) async { asked = true; return http.Response(release('v9'), 200); }));
    expect(r, isA<UpdateByStore>());
    expect(asked, false);
  });

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    addTearDown(() { updateCheck = checkThisApp; updateDownload = openDownload; checkOnStart = false; });
  }

  testWidgets('on start an available update is offered, and Update opens the download', (tester) async {
    await open(tester);
    checkOnStart = true;
    updateCheck = () async => const UpdateAvailable(UpdateInfo(7, 'https://github.com/abtpltd/AksharSevaApp/releases/download/v7/AksharSevak.apk'), 5);
    UpdateInfo? opened;
    updateDownload = (i) async { opened = i; return true; };
    final (_, s) = await setupStoreWith(Fake());
    await tester.pumpWidget(MaterialApp(home: MeetingsScreen(store: s, onSignOut: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('build 7'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(opened?.build, 7);
    s.dispose();
  });

  testWidgets('"Later" does nothing; a quiet start says nothing when up to date or offline', (tester) async {
    await open(tester);
    checkOnStart = true;
    var result = const UpdateAvailable(UpdateInfo(7, 'https://github.com/abtpltd/AksharSevaApp/releases/download/v7/AksharSevak.apk'), 5);
    var downloads = 0;
    updateDownload = (_) async { downloads++; return true; };
    updateCheck = () async => result;
    final (_, s) = await setupStoreWith(Fake());
    await tester.pumpWidget(MaterialApp(home: MeetingsScreen(store: s, onSignOut: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(downloads, 0);
    s.dispose();
    for (final r in <UpdateResult>[const UpToDate(5), const UpdateUnknown()]) {
      updateCheck = () async => r;
      final (_, s2) = await setupStoreWith(Fake());
      await tester.pumpWidget(MaterialApp(home: MeetingsScreen(store: s2, onSignOut: () {})));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      s2.dispose();
    }
  });

  for (final c in [(const UpToDate(5) as UpdateResult, 'newest version (build 5)'), (const UpdateUnknown() as UpdateResult, 'Could not check'), (const UpdateByStore() as UpdateResult, 'Google Play')]) {
    testWidgets('the menu entry answers: ${c.$2}', (tester) async {
      await open(tester);
      final (_, s) = await setupStoreWith(Fake());
      updateCheck = () async => c.$1;
      await tester.pumpWidget(MaterialApp(home: MeetingsScreen(store: s, onSignOut: () {})));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(0, 400), const Offset(500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.textContaining(c.$2), findsOneWidget);
      s.dispose();
    });
  }
}
