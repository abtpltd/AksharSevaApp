import 'dart:async';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:aksharsevak/push.dart';
import 'support.dart';

class FakePush implements PushService {
  final String? t;
  final StreamController<String> c = StreamController<String>.broadcast();
  FakePush(this.t);
  @override
  Future<String?> token() async => t;
  @override
  Stream<String> get refreshed => c.stream;
}

void main() {
  test('signed in: the server is told this phone\'s address, and told the new one if it changes', () async {
    final f = Fake();
    final (_, s) = await setupStoreWith(f);
    final p = FakePush('tok1');
    final link = PushLink(p, s.api);
    await link.start();
    expect(f.log.where((l) => l == 'POST /api/push/register'), hasLength(1));
    p.c.add('tok2');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(f.log.where((l) => l == 'POST /api/push/register'), hasLength(2));
    await link.stop();
    expect(f.log.last, 'DELETE /api/push/register'); // sign-out: the phone is forgotten
    p.c.add('tok3');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(f.log.where((l) => l == 'POST /api/push/register'), hasLength(2)); // nothing after sign-out
  });

  test('no permission or no push: nothing is sent and nothing breaks', () async {
    final f = Fake();
    final (_, s) = await setupStoreWith(f);
    final link = PushLink(const NoPush(), s.api);
    await link.start();
    await link.stop();
    expect(f.log.where((l) => l.contains('push')), isEmpty);
  });

  test('a server without push (503) or a failing server does not break the link', () async {
    final f = Fake();
    final (_, s) = await setupStoreWith(f);
    f.failWith = 503;
    final link = PushLink(FakePush('tok'), s.api);
    await link.start();
    f.failWith = 500;
    await link.stop();
  });
}
