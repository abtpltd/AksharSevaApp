import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aksharsevak/api.dart';
import 'package:aksharsevak/store.dart';
import 'support.dart';

/// Instant updates: a hint from the server makes the phone read again at once; the phone keeps working when the stream drops.
void main() {
  Future<(Fake, Store, StreamController<List<int>> Function())> setupLive() async {
    final f = Fake();
    late StreamController<List<int>> ctl;
    var opens = 0;
    final client = MockClient.streaming((req, body) async {
      if (req.url.path == '/api/live') {
        opens++;
        ctl = StreamController<List<int>>();
        ctl.add(utf8.encode('event: hello\ndata: {}\n\n'));
        return http.StreamedResponse(ctl.stream, 200);
      }
      final bytes = await body.toBytes();
      final r = await f.handle(http.Request(req.method, req.url)..bodyBytes = bytes);
      return http.StreamedResponse(Stream.value(r.bodyBytes), r.statusCode, headers: r.headers);
    });
    final api = Api('http://localhost:3000', client: client)..useToken('t');
    final s = Store(api);
    await s.start(live: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(opens, 1);
    return (f, s, () => ctl);
  }

  String change(String kind, String id) => 'event: change\ndata: ${jsonEncode({'kind': kind, 'id': id, 'org': org, 'wing': 'all', 'version': 1, 'deleted': false})}\n\n';

  test('a hint makes the phone read again at once, and others\' changes become notices', () async {
    final (f, s, ctl) = await setupLive();
    addTearDown(s.dispose);
    expect(s.donorsOf(mid), isEmpty);
    f.put(rec('donor', id(1), {'id': id(1), 'meetingId': mid, 'pos': 1, 'name': 'Ramesh', 'occasion': ''}));
    final reads = f.log.where((l) => l == 'GET /api/docs/donor').length;
    ctl().add(utf8.encode(change('donor', id(1))));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(f.log.where((l) => l == 'GET /api/docs/donor').length, reads + 1);
    expect(s.donorsOf(mid).map((r) => r.body['name']), ['Ramesh']);
    expect(s.liveOn, true);
    expect(s.notices.first.text, '1 donor added to Ravi Sabha · 2026-11-29');
  });

  test('several hints close together cause one read', () async {
    final (f, s, ctl) = await setupLive();
    addTearDown(s.dispose);
    final reads = f.log.where((l) => l == 'GET /api/docs/donor').length;
    for (var i = 0; i < 5; i++) {
      ctl().add(utf8.encode(change('donor', id(i))));
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(f.log.where((l) => l == 'GET /api/docs/donor').length, reads + 1);
  });

  test('a stream that cannot start or has run out of sign-in is handled without breaking the screen', () async {
    final f = Fake();
    final client = MockClient.streaming((req, body) async {
      if (req.url.path == '/api/live') return http.StreamedResponse(Stream.value(utf8.encode('{"error":"Please sign in"}')), 401);
      final r = await f.handle(http.Request(req.method, req.url));
      return http.StreamedResponse(Stream.value(r.bodyBytes), r.statusCode, headers: r.headers);
    });
    final s = Store(Api('http://localhost:3000', client: client)..useToken('t'));
    addTearDown(s.dispose);
    await s.start(live: true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.liveOn, false);
    expect(s.problem, contains('sign-in has run out'));
    expect(s.meetings, isNotEmpty); // what was read stays on screen
  });
}
