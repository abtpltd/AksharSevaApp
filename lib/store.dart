import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api.dart';

String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

int toMinutes(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
  return m == null ? 0 : int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

String clock12(int total) {
  final t = ((total % 1440) + 1440) % 1440;
  final h = t ~/ 60, m = t % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// Items in order of their place number, ties by id (D57).
List<Rec> byPlace(Iterable<Rec> items) {
  final l = items.toList();
  num pos(Rec r) => r.body['pos'] is num ? r.body['pos'] as num : 0;
  l.sort((a, b) {
    final c = pos(a).compareTo(pos(b));
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return l;
}

/// A new item goes at the end: one more than the largest place number in the list.
double nextPos(Iterable<Rec> items) {
  var m = 0.0;
  for (final r in items) {
    final p = r.body['pos'];
    if (p is num && p > m) m = p.toDouble();
  }
  return m + 1;
}

String? _s(Object? o) => o is String ? o : null;

/// A plain line for the Notifications screen: something other people changed since the last read.
class Notice {
  final String text;
  final DateTime at;
  final String? meetingId;
  bool seen = false;
  Notice(this.text, this.at, this.meetingId);
}

/// What the phone shows. There is no copy of its own: it reads from the server and saves straight back (D56, D59).
/// A delete always wins (D58): a record deleted by someone else leaves the screen and the server refuses a save on it (410).
class Store extends ChangeNotifier {
  final Api api;
  Store(this.api);

  String org = '';
  String personName = '';
  bool canWrite = false;
  List<Rec> sabhas = [], meetings = [];
  List<Rec> _items = [], _slides = [], _donors = [], _ticker = [], _cursor = [], _screen = [];
  String? message; // a plain notice for the person
  String? problem; // the last connection problem, cleared by the next good read
  bool loading = false;
  String? openMeeting;
  Timer? _poll;
  bool _busy = false;
  bool _readAgain = false;
  Future<void>? _running;
  bool _primed = false; // the first read only fills the lists; later reads report what changed
  final List<Notice> notices = [];
  int get unread => notices.where((n) => !n.seen).length;

  void markAllRead() {
    for (final n in notices) {
      n.seen = true;
    }
    notifyListeners();
  }

  /// Meetings called when needed (a sabha that is not weekly: Para Sabha, Gyan Goshthi, Prarthna Sabha, events).
  bool isAsNeeded(Rec m) {
    for (final s in sabhas) {
      if (s.id == m.body['sabhaId']) return s.body['kind'] != 'weekly';
    }
    return false;
  }

  String _label(String meetingId, List<Rec> old) {
    for (final m in [...meetings, ...old]) {
      if (m.id == meetingId) return '${sabhaName(m)} · ${m.body['date']}';
    }
    return 'a meeting';
  }

  void _diff(String kind, List<Rec> before, List<Rec> after, List<Rec> oldMeetings) {
    final b = {for (final r in before) r.id: r};
    final a = {for (final r in after) r.id: r};
    String mid(Rec r) => kind == 'meeting' ? r.id : '${r.body['meetingId']}';
    final live = {for (final m in meetings) m.id};
    final added = <String, int>{}, gone = <String, int>{}, changed = <String, int>{};
    for (final r in after) {
      final o = b[r.id];
      if (o == null) {
        added[mid(r)] = (added[mid(r)] ?? 0) + 1;
      } else if (o.version != r.version) {
        changed[mid(r)] = (changed[mid(r)] ?? 0) + 1;
      }
    }
    for (final r in before) {
      if (!a.containsKey(r.id)) gone[mid(r)] = (gone[mid(r)] ?? 0) + 1;
    }
    String noun(int n) {
      final one = kind == 'program-item' ? 'program item' : (kind == 'slide' ? 'slide' : 'donor');
      return n == 1 ? one : '${one}s';
    }

    final now = DateTime.now();
    void put(String text, String id) => notices.insert(0, Notice(text, now, live.contains(id) ? id : null));
    for (final e in added.entries) {
      put(kind == 'meeting' ? 'New meeting: ${_label(e.key, oldMeetings)}' : '${e.value} ${noun(e.value)} added to ${_label(e.key, oldMeetings)}', e.key);
    }
    for (final e in changed.entries) {
      put(kind == 'meeting' ? 'Meeting details changed: ${_label(e.key, oldMeetings)}' : '${e.value} ${noun(e.value)} changed in ${_label(e.key, oldMeetings)}', e.key);
    }
    for (final e in gone.entries) {
      if (kind != 'meeting' && !live.contains(e.key)) continue; // the whole meeting went; one line is enough
      put(kind == 'meeting' ? 'Meeting deleted: ${_label(e.key, oldMeetings)}' : '${e.value} ${noun(e.value)} removed from ${_label(e.key, oldMeetings)}', e.key);
    }
    if (notices.length > 60) notices.removeRange(60, notices.length);
  }

  Future<void> start({bool live = false}) async {
    final me = await api.me();
    org = _s(me['org']) ?? '';
    personName = _s(me['name']) ?? '';
    canWrite = me['status'] == 'confirmed' && (me['role'] == 'editor' || me['role'] == 'admin');
    await refresh();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      // while instant updates are flowing, a read every minute is enough as a safety net
      if (liveOn && ++_beats % 3 != 0) return;
      refresh(quiet: true);
    });
    if (live) _connectLive();
  }

  // ---- instant updates: the server says "something changed", then the phone reads again ----
  bool liveOn = false;
  int _beats = 0, _fails = 0;
  bool _disposed = false;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _retry, _soon;

  void _connectLive() {
    if (_disposed || !api.signedIn) return;
    _sub?.cancel();
    _sub = api.live().listen(
      (_) {
        liveOn = true;
        _fails = 0;
        // several hints can arrive together: one read covers them
        _soon?.cancel();
        _soon = Timer(const Duration(milliseconds: 250), () => refresh(quiet: true));
      },
      onError: (Object e) {
        liveOn = false;
        if (e is ApiError && e.status == 401) {
          problem = 'Your sign-in has run out. Please sign in again.';
          notifyListeners();
          return;
        }
        _again();
      },
      onDone: () {
        liveOn = false;
        _again();
      },
      cancelOnError: true,
    );
  }

  void _again() {
    if (_disposed) return;
    _fails++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _fails > 4 ? 30 : 2 * _fails), () {
      _connectLive();
      refresh(quiet: true); // catch up on anything missed while the stream was down
    });
  }

  @override
  void notifyListeners() { if (!_disposed) super.notifyListeners(); }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _sub?.cancel();
    _retry?.cancel();
    _soon?.cancel();
    super.dispose();
  }

  void clearMessage() {
    message = null;
    notifyListeners();
  }

  String sabhaName(Rec m) {
    final id = m.body['sabhaId'];
    for (final s in sabhas) {
      if (s.id == id) return _s(s.body['name']) ?? 'Sabha';
    }
    return 'Sabha';
  }

  Rec? meeting(String id) {
    for (final m in meetings) {
      if (m.id == id) return m;
    }
    return null;
  }

  List<Rec> itemsOf(String meetingId) => byPlace(_items.where((r) => r.body['meetingId'] == meetingId));
  List<Rec> slidesOf(String meetingId) => byPlace(_slides.where((r) => r.body['meetingId'] == meetingId));
  List<Rec> donorsOf(String meetingId) => byPlace(_donors.where((r) => r.body['meetingId'] == meetingId));
  /// Where the announcer has got to in the donor list (D41): one small record per meeting, or null when nobody is announcing.
  Rec? cursorOf(String meetingId) => _newest(_cursor, meetingId);

  /// The newest record of a kind for a meeting: the highest version, and the larger id when versions tie (the desktop picks the same one).
  Rec? _newest(List<Rec> list, String meetingId) {
    Rec? best;
    for (final r in list) {
      if (r.body['meetingId'] != meetingId) continue;
      if (best == null || r.version > best.version || (r.version == best.version && r.id.compareTo(best.id) > 0)) best = r;
    }
    return best;
  }

  /// How the hall screen behaves for a meeting: scroller on or off and its speed, and the donor list scrolling by itself (D39, D41).
  Map<String, dynamic> screenOf(String meetingId) {
    final best = _newest(_screen, meetingId);
    final b = best?.body ?? const {};
    int n(dynamic v, int lo, int hi, int d) => v is num ? v.round().clamp(lo, hi) : d;
    return {'tickerOn': b['tickerOn'] != false, 'tickerSpeed': n(b['tickerSpeed'], 1, 5, 3), 'autoDonors': b['autoDonors'] == true, 'autoSpeed': n(b['autoSpeed'], 1, 20, 4)};
  }

  /// The slide (its number among this meeting's slides, from 0) the hall screen shows, or null when nobody has moved it yet.
  int? hallSlide(String meetingId) {
    final best = _newest(_screen, meetingId);
    final v = best?.body['slide'];
    return v is int && v >= 0 ? v : null;
  }

  /// Moves the hall screen one slide on or back (the phone remote). False when there is no such slide or the save failed.
  Future<bool> moveHallSlide(String meetingId, int delta) async {
    final count = slidesOf(meetingId).length;
    final now = hallSlide(meetingId) ?? 0;
    final to = now + delta;
    if (to < 0 || to >= count) return false;
    return setScreen(meetingId, {'slide': to});
  }

  /// Changes some of those settings. A clash (someone changed them first) reads theirs and puts this change on top, once.
  Future<bool> setScreen(String meetingId, Map<String, dynamic> change) async {
    final m = meeting(meetingId);
    if (m == null) return false;
    for (var tries = 0; tries < 2; tries++) {
      final cur = _newest(_screen, meetingId);
      final keep = hallSlide(meetingId);
      final body = {...screenOf(meetingId), if (keep != null) 'slide': keep, ...change, 'meetingId': meetingId};
      try {
        if (cur == null) {
          final id = newUuid();
          final saved = await api.put('screen', id, org: m.org, body: {...body, 'id': id});
          _replace('screen', saved ?? Rec('screen', id, m.org, 'all', 1, {...body, 'id': id}));
        } else {
          final saved = await api.put('screen', cur.id, org: cur.org, body: {...body, 'id': cur.id}, version: cur.version);
          _replace('screen', saved ?? Rec('screen', cur.id, cur.org, 'all', cur.version + 1, {...body, 'id': cur.id}));
        }
        notifyListeners();
        return true;
      } on ApiError catch (e) {
        if (e.status == 409 && tries == 0) {
          await refresh(quiet: true);
          continue;
        }
        _failure('screen', cur?.id ?? '', e, 'saved');
        return false;
      }
    }
    return false;
  }

  bool _cursorBusy = false;
  int? _cursorWant;

  /// Moves the announcer's place. Taps that come while a save is on its way are folded into one: the last one wins.
  Future<void> setCursor(String meetingId, int donor) async {
    _cursorWant = donor;
    if (_cursorBusy) return;
    _cursorBusy = true;
    try {
      while (_cursorWant != null) {
        final want = _cursorWant!;
        _cursorWant = null;
        final m = meeting(meetingId);
        if (m == null) return;
        final c = cursorOf(meetingId);
        try {
          Rec? saved;
          if (c == null) {
            final id = newUuid();
            saved = await api.put('cursor', id, org: m.org, body: {'id': id, 'meetingId': meetingId, 'donor': want});
            _replace('cursor', saved ?? Rec('cursor', id, m.org, 'all', 1, {'id': id, 'meetingId': meetingId, 'donor': want}));
          } else {
            saved = await api.put('cursor', c.id, org: c.org, body: {...c.body, 'donor': want}, version: c.version);
            _replace('cursor', saved ?? Rec('cursor', c.id, c.org, 'all', c.version + 1, {...c.body, 'donor': want}));
          }
          notifyListeners();
        } on ApiError catch (e) {
          if (e.status == 409 || e.status == 404 || e.status == 410) {
            await refresh(quiet: true); // someone else moved or ended it: take their place, then try this tap once more
            if (_cursorWant == null && cursorOf(meetingId) != null) _cursorWant = want;
          } else {
            _failure('cursor', c?.id ?? '', e, 'saved');
            return;
          }
        }
      }
    } finally {
      _cursorBusy = false;
    }
  }

  /// The announcer has finished: the hall screen goes back to the ordinary slides.
  Future<void> endCursor(String meetingId) async {
    _cursorWant = null;
    // a first tap may still be on its way to the server: wait for it, or its record would be left behind
    for (var i = 0; i < 50 && _cursorBusy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // two phones that started together leave two places: remove every one of them
    for (final c in _cursor.where((r) => r.body['meetingId'] == meetingId).toList()) {
      await delete(c);
    }
  }

  List<Rec> tickerOf(String meetingId) => byPlace(_ticker.where((r) => r.body['meetingId'] == meetingId));

  /// Reads everything again. A failed read keeps what is on the screen and says so.
  Future<void> refresh({bool quiet = false}) async {
    if (_busy) {
      // a read is already running and may have started before the latest change: ask for one more pass and wait for it
      _readAgain = true;
      return _running;
    }
    _running = _readLoop(quiet);
    return _running;
  }

  Future<void> _readLoop(bool quiet) async {
    do {
      _readAgain = false;
      await _readOnce(quiet);
    } while (_readAgain && !_disposed);
  }

  Future<void> _readOnce(bool quiet) async {
    _busy = true;
    if (!quiet) {
      loading = true;
      notifyListeners();
    }
    try {
      final r = await Future.wait([api.list('sabha'), api.list('meeting'), api.list('program-item'), api.list('slide'), api.list('donor'), api.list('ticker'), api.list('cursor'), api.list('screen')]);
      final oldMeetings = meetings, oldItems = _items, oldSlides = _slides, oldDonors = _donors;
      sabhas = r[0];
      meetings = [...r[1]]..sort((a, b) => '${b.body['date']}'.compareTo('${a.body['date']}'));
      _items = r[2];
      _slides = r[3];
      _donors = r[4];
      _ticker = r[5];
      _cursor = r[6];
      _screen = r[7];
      if (_primed) {
        _diff('meeting', oldMeetings, meetings, oldMeetings);
        _diff('program-item', oldItems, _items, oldMeetings);
        _diff('slide', oldSlides, _slides, oldMeetings);
        _diff('donor', oldDonors, _donors, oldMeetings);
      }
      _primed = true;
      problem = null;
      if (openMeeting != null && meeting(openMeeting!) == null && meetings.isNotEmpty) {
        message = 'This meeting was deleted by someone else.';
      }
    } on ApiError catch (e) {
      problem = e.status == 401 ? 'Your sign-in has run out. Please sign in again.' : '${e.message} Not updated.';
    } finally {
      _busy = false;
      loading = false;
      notifyListeners();
    }
  }

  List<Rec> _listFor(String kind) => kind == 'program-item' ? _items : (kind == 'slide' ? _slides : (kind == 'ticker' ? _ticker : (kind == 'cursor' ? _cursor : (kind == 'screen' ? _screen : _donors))));
  void _setList(String kind, List<Rec> l) {
    if (kind == 'program-item') {
      _items = l;
    } else if (kind == 'slide') {
      _slides = l;
    } else if (kind == 'ticker') {
      _ticker = l;
    } else if (kind == 'cursor') {
      _cursor = l;
    } else if (kind == 'screen') {
      _screen = l;
    } else {
      _donors = l;
    }
  }

  void _drop(String kind, String id) {
    if (_busy) _readAgain = true; // a read that started before this change must not leave the old picture
    _setList(kind, _listFor(kind).where((r) => r.id != id).toList());
  }
  void _replace(String kind, Rec rec) {
    if (_busy) _readAgain = true;
    _setList(kind, [..._listFor(kind).where((r) => r.id != rec.id), rec]);
  }

  /// Adds a record at the end of its meeting's list. Returns true when the server took it.
  Future<bool> add(String kind, String meetingId, Map<String, dynamic> fields) async {
    final m = meeting(meetingId);
    if (m == null) return false;
    final id = newUuid();
    final body = {...fields, 'id': id, 'meetingId': meetingId, 'pos': nextPos(_listFor(kind).where((r) => r.body['meetingId'] == meetingId))};
    // the desktop and the other phones expect a slide's block to carry the same id as its record
    if (kind == 'slide' && body['block'] is Map) body['block'] = {...(body['block'] as Map), 'id': id};
    return _save(kind, id, m.org, body, null);
  }

  /// Changes a record. [fields] replaces the editable parts; the place and meeting stay.
  Future<bool> update(Rec rec, Map<String, dynamic> fields) {
    final body = {...rec.body, ...fields};
    return _save(rec.kind, rec.id, rec.org, body, rec.version);
  }

  Future<bool> _save(String kind, String id, String org, Map<String, dynamic> body, int? version) async {
    try {
      final saved = await api.put(kind, id, org: org, body: body, version: version);
      _replace(kind, saved ?? Rec(kind, id, org, 'all', (version ?? 0) + 1, body));
      message = null;
      notifyListeners();
      return true;
    } on ApiError catch (e) {
      _failure(kind, id, e, 'saved');
      return false;
    }
  }

  Future<bool> delete(Rec rec) async {
    try {
      await api.remove(rec.kind, rec.id);
      _drop(rec.kind, rec.id);
      message = null;
      notifyListeners();
      return true;
    } on ApiError catch (e) {
      if (e.status == 404 || e.status == 410) {
        _drop(rec.kind, rec.id);
        message = 'It was already deleted.';
        notifyListeners();
        return true;
      }
      _failure(rec.kind, rec.id, e, 'deleted');
      return false;
    }
  }

  void _failure(String kind, String id, ApiError e, String verb) {
    if (e.status == 410) {
      _drop(kind, id);
      message = 'This was deleted by someone else, so it was not saved.';
    } else if (e.status == 409) {
      final cur = Rec.parse(e.body?['current']);
      if (cur != null) _replace(kind, cur);
      message = 'Someone else changed this at the same moment, so your change was not saved. Their version is shown.';
    } else if (e.status == 403) {
      message = 'You cannot change this. Ask your coordinator to confirm you.';
    } else if (e.status == 401) {
      problem = 'Your sign-in has run out. Please sign in again.';
    } else {
      message = '${e.message} Not $verb.';
    }
    notifyListeners();
  }
}
