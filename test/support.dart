import 'dart:convert';
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
    if (p == '/api/push/register') return j(200, {'ok': true});
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


Future<(Fake, Store)> setupStore() async {
  final f = Fake();
  final s = Store(Api('http://localhost:3000', client: MockClient(f.handle)));
  await s.start();
  return (f, s);
}

/// Like [setupStore] but with a server the test already holds, so it can look at what the phone sent.
Future<(Fake, Store)> setupStoreWith(Fake f) async {
  final s = Store(Api('http://localhost:3000', client: MockClient(f.handle)));
  await s.start();
  return (f, s);
}
