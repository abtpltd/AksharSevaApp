import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the sign-in token is kept when the person chooses "Keep me signed in".
/// The password and the phone code are never stored; only the token the server gave.
abstract class Vault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// The phone's secure store (Android Keystore, iOS Keychain).
class SecureVault implements Vault {
  static const _key = 'aksharsevak.token';
  final _s = const FlutterSecureStorage();
  @override
  Future<String?> read() async {
    try {
      return await _s.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _s.write(key: _key, value: token);
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      await _s.delete(key: _key);
    } catch (_) {}
  }
}

/// For tests.
class MemoryVault implements Vault {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String t) async => token = t;
  @override
  Future<void> clear() async => token = null;
}
