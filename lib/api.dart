import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// A plain message from the server or the network. status 0 means the server could not be reached.
class ApiError implements Exception {
  final int status;
  final String message;
  final Map<String, dynamic>? body;
  ApiError(this.status, this.message, [this.body]);
  @override
  String toString() => message;
}

const _kinds = {'sabha', 'meeting', 'program-item', 'slide', 'donor', 'ticker', 'cursor', 'screen'};
final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
bool isUuid(String s) => _uuid.hasMatch(s);

/// Only https, or plain http on this phone itself (testing). No name, password, path or query inside the address (D42).
String normalizeBase(String raw) {
  final Uri u;
  try {
    u = Uri.parse(raw.trim());
  } catch (_) {
    throw ApiError(400, 'Please enter the full server address, starting with https://');
  }
  if (!u.hasScheme || u.host.isEmpty) throw ApiError(400, 'Please enter the full server address, starting with https://');
  final local = u.host == 'localhost' || u.host == '127.0.0.1';
  if (u.scheme != 'https' && !(u.scheme == 'http' && local)) {
    throw ApiError(400, 'The server address must start with https://');
  }
  if (u.userInfo.isNotEmpty) throw ApiError(400, 'Do not put a name or password inside the address');
  if ((u.path.isNotEmpty && u.path != '/') || u.hasQuery || u.hasFragment) {
    throw ApiError(400, 'Enter only the server address, without a path');
  }
  return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
}

/// One record as the server sends it.
class Rec {
  final String kind, id, org, wing;
  final int version;
  final Map<String, dynamic> body;
  Rec(this.kind, this.id, this.org, this.wing, this.version, this.body);
  static Rec? parse(Object? j) {
    if (j is! Map) return null;
    final body = j['body'];
    if (j['kind'] is! String || j['id'] is! String || j['org'] is! String || j['version'] is! int || body is! Map) return null;
    return Rec(j['kind'] as String, j['id'] as String, j['org'] as String, (j['wing'] as String?) ?? 'all', j['version'] as int,
        Map<String, dynamic>.from(body));
  }
}

/// The token lives only inside this object; the app keeps it in the phone's secure store only when the person chose to stay signed in. Nothing here stores a password.
class Api {
  final String base;
  final http.Client _http;
  final Duration timeout;
  String? _token;
  Api(String raw, {http.Client? client, this.timeout = const Duration(seconds: 30)})
      : base = normalizeBase(raw),
        _http = client ?? http.Client();

  bool get signedIn => _token != null;
  String? get token => _token;
  void useToken(String t) => _token = t;
  void signOut() => _token = null;

  Future<Map<String, dynamic>> _call(String method, String path, {Object? body, bool auth = true}) async {
    final req = http.Request(method, Uri.parse(base + path));
    req.headers['content-type'] = 'application/json';
    if (auth && _token != null) req.headers['authorization'] = 'Bearer $_token';
    if (body != null) req.body = jsonEncode(body);
    http.Response r;
    try {
      r = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw ApiError(0, 'The server did not answer in time. Check your connection.');
    } catch (_) {
      throw ApiError(0, 'Could not reach the server. Check the address and your connection.');
    }
    Object? j;
    try {
      j = jsonDecode(r.body);
    } catch (_) {}
    if (r.statusCode < 200 || r.statusCode >= 300) {
      if (r.statusCode == 401 && auth) _token = null;
      final m = j is Map && j['error'] is String ? j['error'] as String : 'The server answered ${r.statusCode}';
      throw ApiError(r.statusCode, m, j is Map ? Map<String, dynamic>.from(j) : null);
    }
    return j is Map ? Map<String, dynamic>.from(j) : {'list': j};
  }

  Future<void> login(String id, String password) async {
    _token = null;
    final r = await _call('POST', '/api/login', body: {'id': id, 'password': password}, auth: false);
    _token = r['token'] as String?;
  }

  /// Asks the server to send a one-time code. It answers the same whether or not the phone is known.
  Future<void> startPhone(String phone, {String? inviteCode}) =>
      _call('POST', '/api/register/start', body: {'phone': phone, if (inviteCode != null && inviteCode.isNotEmpty) 'code': inviteCode}, auth: false);

  Future<void> verifyPhone(String phone, String otp, {String? inviteCode, String? name}) async {
    _token = null;
    final r = await _call('POST', '/api/register/verify',
        body: {
          'phone': phone,
          'otp': otp,
          if (inviteCode != null && inviteCode.isNotEmpty) 'code': inviteCode,
          if (name != null && name.isNotEmpty) 'name': name,
        },
        auth: false);
    _token = r['token'] as String?;
  }

  Future<Map<String, dynamic>> me() => _call('GET', '/api/me');

  String _path(String kind, [String? id]) {
    if (!_kinds.contains(kind)) throw ApiError(400, 'Unknown kind of record');
    if (id != null && !isUuid(id)) throw ApiError(400, 'A record id must be a UUID');
    return '/api/docs/$kind${id == null ? '' : '/$id'}';
  }

  Future<List<Rec>> list(String kind) async {
    final r = await _call('GET', _path(kind));
    final raw = r['list'];
    if (raw is! List) return [];
    return [for (final x in raw) if (Rec.parse(x) != null) Rec.parse(x)!];
  }

  Future<Rec?> put(String kind, String id, {required String org, required Map<String, dynamic> body, int? version}) async {
    final r = await _call('PUT', _path(kind, id), body: {'org': org, 'wing': 'all', if (version != null) 'version': version, 'body': body});
    return Rec.parse(r);
  }

  Future<void> remove(String kind, String id) => _call('DELETE', _path(kind, id));

  /// Tells the server where to reach this phone when the app is closed (a push service address, never any record text).
  /// A server without a push service answers 503; that is not an error for the person, so it is reported as false.
  Future<bool> registerDevice(String deviceToken) async {
    try {
      await _call('POST', '/api/push/register', body: {'token': deviceToken});
      return true;
    } on ApiError catch (e) {
      if (e.status == 503) return false;
      rethrow;
    }
  }

  /// Stops messages to this phone (signing out). Never fails the sign-out.
  Future<void> forgetDevice(String deviceToken) async {
    try {
      await _call('DELETE', '/api/push/register', body: {'token': deviceToken});
    } on ApiError catch (_) {}
  }

  /// A stream of small hints that some record changed (the server never sends the text, only kind, id, version). The token goes in the header.
  /// It ends when the connection drops; the caller connects again.
  Stream<Map<String, dynamic>> live() async* {
    final t = _token;
    if (t == null) throw ApiError(401, 'Please sign in');
    final req = http.Request('GET', Uri.parse('$base/api/live'))
      ..headers['authorization'] = 'Bearer $t'
      ..headers['accept'] = 'text/event-stream';
    final http.StreamedResponse resp;
    try {
      resp = await _http.send(req).timeout(timeout);
    } catch (_) {
      throw ApiError(0, 'Could not reach the server.');
    }
    if (resp.statusCode == 401) {
      _token = null;
      throw ApiError(401, 'Please sign in');
    }
    if (resp.statusCode != 200) throw ApiError(resp.statusCode, 'The server answered ${resp.statusCode}');
    var event = '';
    await for (final line in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('event: ')) {
        event = line.substring(7);
      } else if (line.startsWith('data: ')) {
        if (event == 'change') {
          try {
            final j = jsonDecode(line.substring(6));
            if (j is Map) yield Map<String, dynamic>.from(j);
          } catch (_) {}
        }
      } else if (line.isEmpty) {
        event = '';
      }
    }
  }
}
