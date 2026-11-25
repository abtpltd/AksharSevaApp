import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aksharsevak/api.dart';
import 'package:aksharsevak/store.dart';

const org = 'world/kenya/nairobi';
const mid = '11111111-1111-4111-8111-111111111111';
const sid = '22222222-2222-4222-8222-222222222222';
String id(int n) => '33333333-3333-4333-8333-${n.toString().padLeft(12, '0')}';

Map<String, dynamic> rec(String kind, String i, Map<String, dynamic> body, [int v = 1]) => {'kind': kind, 'id': i, 'org': org, 'wing': 'all', 'version': v, 'updatedAt': 'x', 'updatedBy': 'u', 'body': body};

/// A pretend server that follows the real rules: version check (409), delete is final (410), new records need no version.
class Fake {
  final Map<String, Map<String, dynamic>> docs = {};
  final Set<String> deleted = {};
  final List<String> log = [];
  bool down = false;
  int? failWith;
  Fake() {
    put(rec('sabha', sid, {'id': sid, 'name': 'Ravi Sabha'}));
    put(rec('meeting', mid, {'id': mid, 'sabhaId': sid, 'date': '2026-11-29', 'start': '17:00', 'venue': 'Hall', 'mc': ''}));
  }
  void put(Map<String, dynamic> r) => docs['${r['kind']}:${r['id']}'] = r;
  Future<http.Response> handle(http.Request r) async {
    if (down) throw Exception('offline');
    final p = r.url.path;
    log.add('${r.method} $p');
    http.Response j(int s, Object o) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});
    if (failWith != null) return j(failWith!, {'error': 'nope'});
    if (p == '/api/me') return j(200, {'id': 'ed', 'name': 'Ed', 'org': org, 'role': 'editor', 'status': 'confirmed'});
    final m = RegExp(r'^/api/docs/([a-z-]+)(?:/(.+))?$').firstMatch(p);
    if (m == null) return j(404, {'error': 'not found'});
    final kind = m[1]!, i = m[2];
    if (i == null) return j(200, docs.values.where((d) => d['kind'] == kind).toList());
    final key = '$kind:$i';
    if (r.method == 'DELETE') {
      if (!docs.containsKey(key)) return j(404, {'error': 'not found'});
      docs.remove(key);
      deleted.add(key);
      return j(200, {'ok': true});
    }
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    final cur = docs[key];
    if (deleted.contains(key)) return j(410, {'error': 'This was deleted by someone else'});
    if (cur != null && b['version'] != cur['version']) return j(409, {'error': 'Someone else changed this first', 'current': cur});
    final saved = rec(kind, i, b['body'] as Map<String, dynamic>, cur == null ? 1 : (cur['version'] as int) + 1);
    docs[key] = saved;
    return j(cur == null ? 201 : 200, saved);
  }
}

Future<(Fake, Store)> setup() async {
  final f = Fake();
  final api = Api('http://localhost:3000', client: MockClient(f.handle));
  final s = Store(api);
  await s.start();
  return (f, s);
}

void main() {
  group('address', () {
    test('https only, or http on this phone', () {
      expect(normalizeBase('https://akshar.example.com/'), 'https://akshar.example.com');
      expect(normalizeBase('http://localhost:3000'), 'http://localhost:3000');
      for (final bad in ['http://akshar.example.com', 'https://a:b@x.com', 'https://x.com/api', 'x.com', '']) {
        expect(() => normalizeBase(bad), throwsA(isA<ApiError>()), reason: bad);
      }
    });
    test('a bad kind or id is refused before any call', () async {
      final api = Api('http://localhost:3000', client: MockClient((r) async => http.Response('{}', 200)));
      expect(() => api.list('poster'), throwsA(isA<ApiError>()));
      expect(() => api.put('slide', 'not-a-uuid', org: org, body: {}), throwsA(isA<ApiError>()));
    });
    test('a lost connection is a plain message with status 0; a 401 forgets the token', () async {
      var n = 0;
      final api = Api('http://localhost:3000', client: MockClient((r) async {
        n++;
        if (n == 1) return http.Response('{"token":"t"}', 200);
        if (n == 2) return http.Response('{"error":"expired"}', 401);
        throw Exception('x');
      }));
      await api.login('a', 'b');
      expect(api.signedIn, true);
      await expectLater(api.me(), throwsA(predicate((e) => e is ApiError && e.status == 401)));
      expect(api.signedIn, false);
      await expectLater(api.me(), throwsA(predicate((e) => e is ApiError && e.status == 0)));
    });
  });

  group('phone entry', () {
    test('shows what is already added, in order of place then id', () async {
      final f = Fake();
      f.put(rec('program-item', id(2), {'id': id(2), 'meetingId': mid, 'pos': 2, 'item': 'B', 'medium': 'Live', 'presenter': '', 'minutes': 5, 'remark': ''}));
      f.put(rec('program-item', id(1), {'id': id(1), 'meetingId': mid, 'pos': 1, 'item': 'A', 'medium': 'Live', 'presenter': '', 'minutes': 5, 'remark': ''}));
      f.put(rec('program-item', id(3), {'id': id(3), 'meetingId': 'other', 'pos': 0, 'item': 'X', 'medium': 'Live', 'presenter': '', 'minutes': 5, 'remark': ''}));
      final s = Store(Api('http://localhost:3000', client: MockClient(f.handle)));
      await s.start();
      expect(s.itemsOf(mid).map((r) => r.body['item']), ['A', 'B']);
      expect(s.sabhaName(s.meeting(mid)!), 'Ravi Sabha');
      expect(s.canWrite, true);
    });

    test('a new item goes at the end with a UUID, the meeting and the next place number', () async {
      final (f, s) = await setup();
      f.put(rec('donor', id(1), {'id': id(1), 'meetingId': mid, 'pos': 4, 'name': 'A', 'occasion': ''}));
      await s.refresh();
      expect(await s.add('donor', mid, {'name': 'B', 'occasion': 'Diwali'}), true);
      final d = s.donorsOf(mid);
      expect(d.map((r) => r.body['name']), ['A', 'B']);
      expect(d.last.body['pos'], 5);
      expect(isUuid(d.last.id), true);
      expect(f.docs.values.where((x) => x['kind'] == 'donor').length, 2);
    });

    test('a new slide carries its own record id inside the block, as the desktop requires', () async {
      final (f, s) = await setup();
      await s.add('slide', mid, {'block': {'id': 'something-else', 'kind': 'text', 'label': 'L', 'heading': 'H', 'lines': ['a']}});
      final r = s.slidesOf(mid).single;
      expect((r.body['block'] as Map)['id'], r.id);
      expect(r.body['pos'], 1);
    });

    test('two phones adding at once both keep their item', () async {
      final (f, s) = await setup();
      f.put(rec('donor', id(9), {'id': id(9), 'meetingId': mid, 'pos': 1, 'name': 'Other phone', 'occasion': ''})); // not yet seen here
      expect(await s.add('donor', mid, {'name': 'Mine', 'occasion': ''}), true);
      await s.refresh();
      expect(s.donorsOf(mid).map((r) => r.body['name']).toSet(), {'Other phone', 'Mine'});
    });

    test('a change is sent with its version and keeps the place and meeting', () async {
      final (f, s) = await setup();
      await s.add('program-item', mid, {'item': 'Kirtan', 'medium': 'Live', 'presenter': '', 'minutes': 10, 'remark': ''});
      final r = s.itemsOf(mid).single;
      expect(await s.update(r, {'minutes': 15}), true);
      final now = s.itemsOf(mid).single;
      expect(now.body['minutes'], 15);
      expect(now.body['meetingId'], mid);
      expect(now.version, 2);
    });

    test('someone else changed it first: their version is shown and nothing is overwritten', () async {
      final (f, s) = await setup();
      await s.add('donor', mid, {'name': 'A', 'occasion': ''});
      final mine = s.donorsOf(mid).single;
      f.put(rec('donor', mine.id, {...mine.body, 'name': 'Theirs'}, 2));
      expect(await s.update(mine, {'name': 'Mine'}), false);
      expect(s.donorsOf(mid).single.body['name'], 'Theirs');
      expect(s.message, contains('not saved'));
    });

    test('a delete always wins: a record deleted elsewhere cannot be saved and leaves the screen', () async {
      final (f, s) = await setup();
      await s.add('donor', mid, {'name': 'A', 'occasion': ''});
      final mine = s.donorsOf(mid).single;
      f.docs.remove('donor:${mine.id}');
      f.deleted.add('donor:${mine.id}');
      expect(await s.update(mine, {'name': 'Late edit'}), false);
      expect(s.donorsOf(mid), isEmpty);
      expect(s.message, contains('deleted by someone else'));
      await s.refresh();
      expect(s.donorsOf(mid), isEmpty); // nothing brought it back
    });

    test('deleting a record already gone is fine', () async {
      final (f, s) = await setup();
      await s.add('donor', mid, {'name': 'A', 'occasion': ''});
      final mine = s.donorsOf(mid).single;
      f.docs.remove('donor:${mine.id}');
      f.deleted.add('donor:${mine.id}');
      expect(await s.delete(mine), true);
      expect(s.donorsOf(mid), isEmpty);
    });

    test('no connection: the screen stays, says so, and the next read recovers', () async {
      final (f, s) = await setup();
      await s.add('donor', mid, {'name': 'A', 'occasion': ''});
      f.down = true;
      await s.refresh();
      expect(s.problem, contains('Not updated'));
      expect(s.donorsOf(mid).length, 1);
      expect(await s.add('donor', mid, {'name': 'B', 'occasion': ''}), false);
      expect(s.message, contains('Not saved'));
      expect(s.donorsOf(mid).length, 1); // nothing is kept back silently
      f.down = false;
      await s.refresh();
      expect(s.problem, isNull);
    });

    test('a refusal (403) says who can fix it and changes nothing', () async {
      final (f, s) = await setup();
      f.failWith = 403;
      expect(await s.add('donor', mid, {'name': 'A', 'occasion': ''}), false);
      expect(s.message, contains('coordinator'));
      expect(s.donorsOf(mid), isEmpty);
    });

    test('program times chain from the meeting start', () {
      expect(clock12(toMinutes('17:00')), '5:00 PM');
      expect(clock12(toMinutes('17:00') + 25), '5:25 PM');
      expect(clock12(0), '12:00 AM');
    });
  });
}
