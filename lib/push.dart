import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';

/// Where this phone can be reached when the app is closed (D60). The server only ever sends the same plain line, never record text.
abstract class PushService {
  /// Asks permission (Android 13 and later) and gives this phone's push address, or null when push is not available or not allowed.
  Future<String?> token();

  /// Called with the new address when the push service changes it.
  Stream<String> get refreshed;
}

/// No push (tests, the web build, a phone without Google services).
class NoPush implements PushService {
  const NoPush();
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get refreshed => const Stream.empty();
}

/// Firebase Cloud Messaging. Never throws: a phone that cannot do push simply gets none.
class FirebasePush implements PushService {
  bool _ready = false;

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (_) {}
    return _ready;
  }

  @override
  Future<String?> token() async {
    try {
      if (!await _init()) return null;
      final m = FirebaseMessaging.instance;
      final p = await m.requestPermission();
      if (p.authorizationStatus == AuthorizationStatus.denied) return null;
      return await m.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get refreshed async* {
    if (!await _init()) return;
    yield* FirebaseMessaging.instance.onTokenRefresh;
  }
}

/// Keeps the server told where to reach this phone while a person is signed in, and forgets it at sign-out.
/// Push never gets in the way of using the app: every failure is swallowed.
class PushLink {
  final PushService push;
  final Api api;
  PushLink(this.push, this.api);
  String? _token;
  StreamSubscription<String>? _sub;
  bool _stopped = false;

  Future<void> start() async {
    try {
      final t = await push.token();
      if (t == null || _stopped) return;
      _token = t;
      // listen for a new address first, so a failed first try (no connection) does not lose later ones
      _sub = push.refreshed.listen((n) {
        _token = n;
        api.registerDevice(n).catchError((_) => false);
      });
      await api.registerDevice(t);
    } catch (_) {}
  }

  /// Sign-out: tell the server to stop, while the sign-in still works. Call before the token is cleared.
  Future<void> stop() async {
    _stopped = true;
    await _sub?.cancel();
    final t = _token;
    _token = null;
    if (t != null) await api.forgetDevice(t);
  }
}
