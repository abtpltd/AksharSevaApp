import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aksharsevak/api.dart';
import 'package:aksharsevak/store.dart';

// Runs against a real server only when AKSHAR_TEST_SERVER is set (for example http://localhost:8787 with user ed2).
void main() {
  final addr = Platform.environment['AKSHAR_TEST_SERVER'];
  test('phone against the real server', skip: addr == null ? 'set AKSHAR_TEST_SERVER to run' : false, () async {
    final api = Api(addr!);
    await api.login('ed2', 'password-ed2');
    final s = Store(api);
    await s.start();
    expect(s.canWrite, true);
    expect(s.meetings, isNotEmpty, reason: 'make a meeting on the desktop first');
    final mid = s.meetings.first.id;
    final before = (s.itemsOf(mid).length, s.slidesOf(mid).length, s.donorsOf(mid).length);
    print('seen from the desktop: ${before.$1} items, ${before.$2} slides, ${before.$3} donors; sabha ${s.sabhaName(s.meetings.first)}');
    expect(await s.add('program-item', mid, {'item': 'Added from phone', 'medium': 'Live', 'presenter': 'Sevak', 'minutes': 7, 'remark': ''}), true, reason: s.message);
    expect(await s.add('slide', mid, {'block': {'kind': 'text', 'label': 'Notice', 'heading': 'From the phone', 'lines': ['Line one', 'Line two']}}), true, reason: s.message);
    expect(await s.add('donor', mid, {'name': 'Phone Donor', 'occasion': 'Diwali'}), true, reason: s.message);
    expect(await s.add('donor', mid, {'name': 'Gone Donor', 'occasion': ''}), true, reason: s.message);
    final item = s.itemsOf(mid).firstWhere((r) => r.body['item'] == 'Added from phone');
    expect(await s.update(item, {'minutes': 9}), true, reason: s.message);
    expect(await s.delete(s.donorsOf(mid).firstWhere((r) => r.body['name'] == 'Gone Donor')), true);
    final s2 = Store(api);
    await s2.start();
    expect(s2.itemsOf(mid).length, before.$1 + 1);
    expect(s2.itemsOf(mid).last.body['item'], 'Added from phone');
    expect(s2.itemsOf(mid).last.body['minutes'], 9);
    expect(s2.slidesOf(mid).length, before.$2 + 1);
    expect(s2.donorsOf(mid).map((r) => r.body['name']), ['Phone Donor']);
    s.dispose();
    s2.dispose();
  });
}
