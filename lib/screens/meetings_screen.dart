import 'package:flutter/material.dart';
import '../api.dart';
import '../store.dart';
import '../theme.dart';
import 'meeting_screen.dart';

enum _View { home, sabha, asNeeded, notifications, duties }

/// The main screen: a dark title bar, a side menu, and one body at a time (all meetings, one sabha, meetings as needed,
/// notifications, my duties). Department, event and duty screens will be added to the menu as the server gets that data.
class MeetingsScreen extends StatefulWidget {
  final Store store;
  final VoidCallback onSignOut;
  const MeetingsScreen({super.key, required this.store, required this.onSignOut});
  @override
  State<MeetingsScreen> createState() => _MeetingsState();
}

class _MeetingsState extends State<MeetingsScreen> {
  _View view = _View.home;
  Rec? sabha;
  Store get store => widget.store;

  void _go(_View v, [Rec? s]) {
    Navigator.of(context).pop(); // close the menu
    setState(() {
      view = v;
      sabha = s;
    });
    if (v == _View.notifications) store.markAllRead();
  }

  String get _title => switch (view) {
        _View.home => 'Meetings',
        _View.sabha => '${sabha?.body['name'] ?? 'Sabha'}',
        _View.asNeeded => 'Meetings as needed',
        _View.notifications => 'Notifications',
        _View.duties => 'My duties',
      };

  void _open(Rec m) {
    store.openMeeting = m.id;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeetingScreen(store: store, meetingId: m.id))).then((_) => store.openMeeting = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final unread = store.unread;
        return Scaffold(
          appBar: AppBar(title: Text(_title), actions: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () {
                setState(() => view = _View.notifications);
                store.markAllRead();
              },
              icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_none)),
            ),
            IconButton(tooltip: 'Read again', onPressed: store.refresh, icon: const Icon(Icons.refresh)),
          ]),
          drawer: _menu(context, unread),
          body: Column(children: [
            if (store.problem != null) MaterialBanner(content: Text(store.problem!), actions: [TextButton(onPressed: store.refresh, child: const Text('Try again'))]),
            if (!store.canWrite && store.personName.isNotEmpty) const MaterialBanner(content: Text('You can read, but not add yet. Your coordinator needs to confirm you.'), actions: [SizedBox()]),
            Expanded(child: _body(context)),
          ]),
        );
      },
    );
  }

  Widget _menu(BuildContext context, int unread) {
    Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 2), child: Text(t, style: const TextStyle(color: baps_red, fontWeight: FontWeight.w500, fontSize: 12)));
    Widget item(IconData i, String t, bool on, VoidCallback f, {Widget? trailing}) =>
        ListTile(dense: true, leading: Icon(i), title: Text(t), selected: on, selectedTileColor: const Color(0xFFF3D9B8), selectedColor: ink, trailing: trailing, onTap: f);
    final weekly = store.sabhas.where((s) => s.body['kind'] == 'weekly').toList();
    return Drawer(
      child: Column(children: [
        Container(
          width: double.infinity,
          color: maroon,
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(store.personName.isEmpty ? 'AksharSevak' : store.personName, style: const TextStyle(color: cream, fontSize: 16, fontWeight: FontWeight.w500)),
            Text('${store.org}  ·  ${store.canWrite ? 'Can add' : 'Read only'}', style: const TextStyle(color: paleSand, fontSize: 12)),
          ]),
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            item(Icons.home_outlined, 'Home', view == _View.home, () => _go(_View.home)),
            item(Icons.checklist, 'My duties', view == _View.duties, () => _go(_View.duties)),
            item(Icons.notifications_none, 'Notifications', view == _View.notifications, () => _go(_View.notifications),
                trailing: unread > 0 ? CircleAvatar(radius: 10, backgroundColor: redOrange, child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11))) : null),
            if (weekly.isNotEmpty) head('Sabhas'),
            for (final s in weekly) item(Icons.event_outlined, '${s.body['name']}', view == _View.sabha && sabha?.id == s.id, () => _go(_View.sabha, s)),
            head('Meetings'),
            item(Icons.bolt_outlined, 'Meetings as needed', view == _View.asNeeded, () => _go(_View.asNeeded)),
            const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 8), child: Text('Events and your departments will appear here as they are set up.', style: TextStyle(fontSize: 12, color: Color(0xFF6B6458)))),
          ]),
        ),
        const Divider(height: 1, color: line),
        item(Icons.logout, 'Sign out', false, () {
          Navigator.of(context).pop();
          widget.onSignOut();
        }),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    switch (view) {
      case _View.notifications:
        return _notices();
      case _View.duties:
        final duties = store.myDuties();
        if (duties.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('No duties yet. When you are named as the presenter of a program item in a coming meeting, it appears here.', textAlign: TextAlign.center)));
        return ListView(children: [
          for (final d in duties)
            ListTile(
              leading: const Icon(Icons.checklist),
              title: Text('${d.item.body['item'] ?? ''}'),
              subtitle: Text('${d.meeting.body['date']} · ${clock12(d.startMinutes)} · ${store.sabhaName(d.meeting)} · ${d.item.body['minutes'] ?? 0} min'),
              onTap: () => _open(d.meeting),
            ),
        ]);
      case _View.home:
      case _View.sabha:
      case _View.asNeeded:
        final list = store.meetings.where((m) => view == _View.home || (view == _View.sabha ? m.body['sabhaId'] == sabha?.id : store.isAsNeeded(m))).toList();
        if (store.loading && store.meetings.isEmpty) return const Center(child: CircularProgressIndicator());
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                view == _View.asNeeded ? 'No meetings called as needed yet. A Para Sabha, Gyan Goshthi or Prarthna Sabha appears here when it is made on the back office.' : 'No meetings yet. They are made on the back office.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final today = DateTime.now().toIso8601String().substring(0, 10);
        return RefreshIndicator(
          onRefresh: store.refresh,
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
            for (final m in list)
              Card(
                child: ListTile(
                  title: Text('${store.sabhaName(m)}  ·  ${m.body['date']}', style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text('${m.body['start'] ?? ''}  ${m.body['venue'] ?? ''}'),
                  trailing: '${m.body['date']}'.compareTo(today) >= 0 ? const Chip(label: Text('Coming')) : null,
                  onTap: () => _open(m),
                ),
              ),
          ]),
        );
    }
  }

  Widget _notices() {
    if (store.notices.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Nothing new. Changes other people make to meetings, program items, slides and donors will show here while the app is open.', textAlign: TextAlign.center)));
    }
    String ago(DateTime t) {
      final d = DateTime.now().difference(t);
      return d.inMinutes < 1 ? 'Just now' : d.inMinutes < 60 ? '${d.inMinutes} min ago' : d.inHours < 24 ? '${d.inHours} h ago' : '${d.inDays} d ago';
    }

    return ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
      for (final n in store.notices)
        Card(
          child: ListTile(
            title: Text(n.text),
            subtitle: Text(ago(n.at)),
            trailing: n.meetingId == null ? null : const Icon(Icons.chevron_right),
            onTap: n.meetingId == null
                ? null
                : () {
                    final m = store.meeting(n.meetingId!);
                    if (m != null) _open(m);
                  },
          ),
        ),
    ]);
  }
}
