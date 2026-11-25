import 'package:flutter/material.dart';
import '../store.dart';

const mediums = ['Live', 'Video', 'PPT', 'Emcee', 'Other'];

class MeetingScreen extends StatelessWidget {
  final Store store;
  final String meetingId;
  const MeetingScreen({super.key, required this.store, required this.meetingId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final m = store.meeting(meetingId);
        if (m == null) {
          return Scaffold(appBar: AppBar(title: const Text('Meeting')), body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Meeting not found. It may have been deleted by someone else.'))));
        }
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${m.body['date']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)), Text('${store.sabhaName(m)} · ${m.body['start'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Color(0xFFE8C9A0)))]),
              actions: [IconButton(tooltip: 'Read again', onPressed: store.refresh, icon: const Icon(Icons.refresh))],
              bottom: const TabBar(tabs: [Tab(text: 'Program'), Tab(text: 'Slides'), Tab(text: 'Donors'), Tab(text: 'Scroller')]),
            ),
            body: Column(children: [
              if (store.problem != null) MaterialBanner(content: Text(store.problem!), actions: [TextButton(onPressed: store.refresh, child: const Text('Try again'))]),
              if (store.message != null) MaterialBanner(content: Text(store.message!), actions: [TextButton(onPressed: store.clearMessage, child: const Text('OK'))]),
              Expanded(child: TabBarView(children: [_Program(store, m.id), _Slides(store, m.id), _Donors(store, m.id), _Scroller(store, m.id)])),
            ]),
          ),
        );
      },
    );
  }
}

/// Reads the lists again first so the person sees what others have already added, then opens the form (D56).
Future<void> _addWithFreshList(BuildContext context, Store store, Future<void> Function() open) async {
  await store.refresh(quiet: true);
  if (context.mounted) await open();
}

Future<bool> _confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete $what?'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))],
    ),
  );
  return ok ?? false;
}

Future<void> _form(BuildContext context, {required String title, required List<Widget> fields, required Future<bool> Function() onSave, Future<bool> Function()? onDelete, String? note}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (c) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (note != null) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF3D9B8), borderRadius: BorderRadius.circular(6)), child: Text(note)),
          for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: f),
          FilledButton(
            onPressed: () async {
              if (await onSave() && c.mounted) Navigator.pop(c);
            },
            child: const Text('Save'),
          ),
          if (onDelete != null)
            TextButton(
              onPressed: () async {
                if (await _confirmDelete(c, 'this')) {
                  if (await onDelete() && c.mounted) Navigator.pop(c);
                }
              },
              child: const Text('Delete'),
            ),
        ]),
      ),
    ),
  );
}

class _Program extends StatelessWidget {
  final Store store;
  final String mid;
  const _Program(this.store, this.mid);

  Future<void> _edit(BuildContext context, [dynamic rec]) {
    final item = TextEditingController(text: rec?.body['item'] ?? '');
    final presenter = TextEditingController(text: rec?.body['presenter'] ?? '');
    final minutes = TextEditingController(text: '${rec?.body['minutes'] ?? 5}');
    final remark = TextEditingController(text: rec?.body['remark'] ?? '');
    var medium = mediums.contains(rec?.body['medium']) ? rec.body['medium'] as String : 'Live';
    return _form(
      context,
      title: rec == null ? 'Add program item' : 'Change program item',
      note: rec == null && store.itemsOf(mid).isNotEmpty ? '${store.itemsOf(mid).length} items already added by others' : null,
      fields: [
        TextField(controller: item, decoration: const InputDecoration(labelText: 'Item')),
        StatefulBuilder(builder: (c, set) => DropdownButtonFormField<String>(initialValue: medium, decoration: const InputDecoration(labelText: 'How'), items: [for (final x in mediums) DropdownMenuItem(value: x, child: Text(x))], onChanged: (v) => set(() => medium = v ?? medium))),
        TextField(controller: presenter, decoration: const InputDecoration(labelText: 'Presenter')),
        TextField(controller: minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes')),
        TextField(controller: remark, decoration: const InputDecoration(labelText: 'Remark')),
      ],
      onSave: () {
        final f = {'item': item.text.trim(), 'medium': medium, 'presenter': presenter.text.trim(), 'minutes': int.tryParse(minutes.text.trim()) ?? 5, 'remark': remark.text.trim()};
        if ((f['item'] as String).isEmpty) return Future.value(false);
        return rec == null ? store.add('program-item', mid, f) : store.update(rec, f);
      },
      onDelete: rec == null ? null : () => store.delete(rec),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = store.itemsOf(mid);
    final m = store.meeting(mid)!;
    var t = toMinutes('${m.body['start'] ?? '00:00'}');
    return Scaffold(
      floatingActionButton: store.canWrite ? FloatingActionButton.extended(onPressed: () => _addWithFreshList(context, store, () => _edit(context)), icon: const Icon(Icons.add), label: const Text('Add item')) : null,
      body: items.isEmpty
          ? const Center(child: Text('Nothing added yet.'))
          : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
              for (final r in items)
                Builder(builder: (c) {
                  final mins = r.body['minutes'] is num ? (r.body['minutes'] as num).round() : 0;
                  final from = t;
                  t += mins;
                  return ListTile(
                    leading: Text('${clock12(from)}\n${r.body['medium'] ?? ''}', style: Theme.of(c).textTheme.bodySmall),
                    title: Text('${r.body['item'] ?? ''}'),
                    subtitle: Text([r.body['presenter'], '$mins min', r.body['remark']].where((x) => x != null && '$x'.isNotEmpty).join('  ·  ')),
                    onTap: store.canWrite ? () => _edit(c, r) : null,
                  );
                }),
            ]),
    );
  }
}

class _Slides extends StatelessWidget {
  final Store store;
  final String mid;
  const _Slides(this.store, this.mid);

  Future<void> _edit(BuildContext context, [dynamic rec]) {
    final block = Map<String, dynamic>.from(rec?.body['block'] ?? {});
    final label = TextEditingController(text: '${block['label'] ?? ''}');
    final heading = TextEditingController(text: '${block['heading'] ?? ''}');
    final lines = TextEditingController(text: ((block['lines'] as List?) ?? []).join('\n'));
    return _form(
      context,
      title: rec == null ? 'Add slide' : 'Change slide',
      fields: [
        TextField(controller: label, decoration: const InputDecoration(labelText: 'Label (small title)')),
        TextField(controller: heading, decoration: const InputDecoration(labelText: 'Heading')),
        TextField(controller: lines, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'Lines (one per line)')),
      ],
      onSave: () {
        final ls = lines.text.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
        if (heading.text.trim().isEmpty && ls.isEmpty) return Future.value(false);
        final b = {...block, 'id': block['id'] ?? rec?.id ?? newUuid(), 'kind': 'text', 'label': label.text.trim(), 'heading': heading.text.trim(), 'lines': ls};
        if (rec == null) {
          return store.add('slide', mid, {'block': b});
        }
        return store.update(rec, {'block': {...b, 'id': rec.id}});
      },
      onDelete: rec == null ? null : () => store.delete(rec),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = store.slidesOf(mid);
    return Scaffold(
      floatingActionButton: store.canWrite ? FloatingActionButton.extended(onPressed: () => _addWithFreshList(context, store, () => _edit(context)), icon: const Icon(Icons.add), label: const Text('Add slide')) : null,
      body: slides.isEmpty
          ? const Center(child: Text('No slides yet.'))
          : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
              for (var i = 0; i < slides.length; i++)
                Builder(builder: (c) {
                  final r = slides[i];
                  final b = (r.body['block'] is Map) ? Map<String, dynamic>.from(r.body['block']) : <String, dynamic>{};
                  final isText = b['kind'] == 'text';
                  final title = '${b['heading'] ?? ''}'.isNotEmpty ? '${b['heading']}' : (('${b['label'] ?? ''}'.isNotEmpty) ? '${b['label']}' : '${b['kind'] ?? 'slide'}');
                  return ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(title),
                    subtitle: Text(isText ? ((b['lines'] as List?) ?? []).take(2).join(', ') : 'Edit this kind of slide on the back office'),
                    onTap: !store.canWrite ? null : (isText ? () => _edit(c, r) : () async { if (await _confirmDelete(c, 'this slide')) await store.delete(r); }),
                  );
                }),
            ]),
    );
  }
}

class _Donors extends StatelessWidget {
  final Store store;
  final String mid;
  const _Donors(this.store, this.mid);

  Future<void> _edit(BuildContext context, [dynamic rec]) {
    final name = TextEditingController(text: rec?.body['name'] ?? '');
    final occasion = TextEditingController(text: rec?.body['occasion'] ?? '');
    return _form(
      context,
      title: rec == null ? 'Add donor' : 'Change donor',
      fields: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        TextField(controller: occasion, decoration: const InputDecoration(labelText: 'Occasion')),
      ],
      onSave: () {
        final f = {'name': name.text.trim(), 'occasion': occasion.text.trim()};
        if (f['name']!.isEmpty) return Future.value(false);
        return rec == null ? store.add('donor', mid, f) : store.update(rec, f);
      },
      onDelete: rec == null ? null : () => store.delete(rec),
    );
  }

  @override
  Widget build(BuildContext context) {
    final donors = store.donorsOf(mid);
    return Scaffold(
      floatingActionButton: store.canWrite ? FloatingActionButton.extended(onPressed: () => _addWithFreshList(context, store, () => _edit(context)), icon: const Icon(Icons.add), label: const Text('Add donor')) : null,
      body: donors.isEmpty
          ? const Center(child: Text('No donors yet.'))
          : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
              if (store.canWrite)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => AnnouncerScreen(store, mid))),
                    icon: const Icon(Icons.record_voice_over),
                    label: const Text('Announce the names'),
                  ),
                ),
              for (final r in donors) ListTile(title: Text('${r.body['name'] ?? ''}'), subtitle: Text('${r.body['occasion'] ?? ''}'), onTap: store.canWrite ? () => _edit(context, r) : null),
            ]),
    );
  }
}

/// Messages that run along the bottom of the hall screen (D39, D40). Anyone who can add may add one; the desktop shows it at once.
class _Scroller extends StatelessWidget {
  final Store store;
  final String mid;
  const _Scroller(this.store, this.mid);

  Future<void> _edit(BuildContext context, [dynamic rec]) {
    final text = TextEditingController(text: rec?.body['text'] ?? '');
    return _form(
      context,
      title: rec == null ? 'Add scroller message' : 'Change scroller message',
      fields: [TextField(controller: text, maxLength: 200, maxLines: 3, decoration: const InputDecoration(labelText: 'Message'))],
      note: 'It runs along the bottom of the hall screen.',
      onSave: () {
        final t = text.text.trim();
        if (t.isEmpty) return Future.value(false);
        return rec == null ? store.add('ticker', mid, {'text': t}) : store.update(rec, {'text': t});
      },
      onDelete: rec == null ? null : () => store.delete(rec),
    );
  }

  List<Widget> _controls() {
    final sc = store.screenOf(mid);
    final total = store.slidesOf(mid).length;
    final at = store.hallSlide(mid) ?? 0;
    return [
      ListTile(
        title: Text(total == 0 ? 'Hall screen: no slides yet' : 'Hall screen: slide ${at + 1} of $total'),
        subtitle: const Text('Moves the slide for everyone, as the desktop does'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: at > 0 ? () => store.moveHallSlide(mid, -1) : null, child: const Text('Back'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: at < total - 1 ? () => store.moveHallSlide(mid, 1) : null, child: const Text('Next'))),
        ]),
      ),
      const Divider(),
      SwitchListTile(title: const Text('Scroller on the hall screen'), value: sc['tickerOn'] as bool, onChanged: (v) => store.setScreen(mid, {'tickerOn': v})),
      ListTile(
        title: const Text('Scroller speed'),
        subtitle: Slider(min: 1, max: 5, divisions: 4, label: '${sc['tickerSpeed']}', value: (sc['tickerSpeed'] as int).toDouble(), onChanged: (v) => store.setScreen(mid, {'tickerSpeed': v.round()})),
      ),
      SwitchListTile(
        title: const Text('Donor list moves by itself'),
        subtitle: Text('A name every ${sc['autoSpeed']} seconds, if the announcer\'s phone cannot be used'),
        value: sc['autoDonors'] as bool,
        onChanged: (v) => store.setScreen(mid, {'autoDonors': v}),
      ),
      const Divider(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final msgs = store.tickerOf(mid);
    return Scaffold(
      floatingActionButton: store.canWrite ? FloatingActionButton.extended(onPressed: () => _addWithFreshList(context, store, () => _edit(context)), icon: const Icon(Icons.add), label: const Text('Add message')) : null,
      body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
              if (store.canWrite) ..._controls(),
              if (msgs.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No scroller messages yet.'))),
              for (final r in msgs) ListTile(title: Text('${r.body['text'] ?? ''}'), onTap: store.canWrite ? () => _edit(context, r) : null),
            ]),
    );
  }
}

/// The announcer reads the donor names aloud and taps for the next one; the hall screen follows (D41).
class AnnouncerScreen extends StatefulWidget {
  final Store store;
  final String mid;
  const AnnouncerScreen(this.store, this.mid, {super.key});
  @override
  State<AnnouncerScreen> createState() => _AnnouncerState();
}

class _AnnouncerState extends State<AnnouncerScreen> {
  Store get s => widget.store;
  int _at = 0;

  @override
  void initState() {
    super.initState();
    final c = s.cursorOf(widget.mid);
    _at = (c?.body['donor'] is int) ? c!.body['donor'] as int : 0;
    s.setCursor(widget.mid, _at); // the hall screen switches to the scrolling list at once
  }

  void _go(int n, int count) {
    final to = n.clamp(0, count - 1);
    setState(() => _at = to);
    s.setCursor(widget.mid, to);
  }

  @override
  Widget build(BuildContext context) {
    final donors = s.donorsOf(widget.mid).where((r) => '${r.body['name'] ?? ''}'.trim().isNotEmpty).toList();
    final n = donors.length;
    final at = n == 0 ? 0 : _at.clamp(0, n - 1);
    String name(int i) => i >= 0 && i < n ? '${donors[i].body['name']}' : '';
    return Scaffold(
      appBar: AppBar(
        title: Text('Announcing ${n == 0 ? 0 : at + 1} of $n'),
        actions: [
          TextButton(
            onPressed: () async {
              await s.endCursor(widget.mid);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Finish', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: n == 0
          ? const Center(child: Text('No donors to announce.'))
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const SizedBox(height: 12),
                Text(name(at), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                if ('${donors[at].body['occasion'] ?? ''}'.isNotEmpty) Text('${donors[at].body['occasion']}', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Text(at + 1 < n ? 'Next: ${name(at + 1)}' : 'This is the last name', textAlign: TextAlign.center),
                const Spacer(),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: at > 0 ? () => _go(at - 1, n) : null, child: const Padding(padding: EdgeInsets.symmetric(vertical: 22), child: Text('Back')))),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: FilledButton(onPressed: at + 1 < n ? () => _go(at + 1, n) : null, child: const Padding(padding: EdgeInsets.symmetric(vertical: 22), child: Text('Next name', style: TextStyle(fontSize: 20))))),
                ]),
              ]),
            ),
    );
  }
}
