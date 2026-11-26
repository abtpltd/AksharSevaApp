import 'package:flutter/material.dart';
import '../store.dart';
import '../slide_view.dart';
import '../donor_name.dart';
import 'slide_screens.dart';

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
              actions: [
                if (store.canWrite) IconButton(tooltip: 'Change date, time or venue', onPressed: () => _editMeeting(context, store, m), icon: const Icon(Icons.edit_calendar)),
                IconButton(tooltip: 'Read again', onPressed: store.refresh, icon: const Icon(Icons.refresh)),
              ],
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

/// Changes when and where a meeting is held. The sabha's usual time stays as it is: only this meeting moves.
Future<void> _editMeeting(BuildContext context, Store store, dynamic m) {
  var date = DateTime.tryParse('${m.body['date']}') ?? DateTime.now();
  final parts = '${m.body['start'] ?? '00:00'}'.split(':');
  var time = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
  final venue = TextEditingController(text: '${m.body['venue'] ?? ''}');
  String two(int n) => n.toString().padLeft(2, '0');
  return _form(
    context,
    title: 'Date, time and venue',
    fields: [
      StatefulBuilder(builder: (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('${date.year}-${two(date.month)}-${two(date.day)}'),
              onPressed: () async {
                final d = await showDatePicker(context: c, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) set(() => date = d);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text('${two(time.hour)}:${two(time.minute)}'),
              onPressed: () async {
                final t = await showTimePicker(context: c, initialTime: time);
                if (t != null) set(() => time = t);
              },
            ),
          ])),
      TextField(controller: venue, decoration: const InputDecoration(labelText: 'Venue')),
    ],
    onSave: () => store.update(m, {'date': '${date.year}-${two(date.month)}-${two(date.day)}', 'start': '${two(time.hour)}:${two(time.minute)}', 'venue': venue.text.trim()}),
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

  @override
  Widget build(BuildContext context) {
    final slides = store.slidesOf(mid);
    final write = store.canWrite;
    final donors = [for (final d in store.donorsOf(mid)) Map<String, dynamic>.from(d.body)];
    return Scaffold(
      floatingActionButton: write
          ? FloatingActionButton(
              tooltip: 'Add slide',
              onPressed: () => _addWithFreshList(context, store, () => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => SlideForm(store: store, meetingId: mid)))),
              child: const Icon(Icons.add),
            )
          : null,
      body: slides.isEmpty
          ? const Center(child: Text('No slides yet.'))
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              buildDefaultDragHandles: false,
              itemCount: slides.length,
              onReorder: (from, to) { if (write) store.moveSlide(mid, from, to); },
              itemBuilder: (c, i) {
                final r = slides[i];
                final b = (r.body['block'] is Map) ? Map<String, dynamic>.from(r.body['block']) : <String, dynamic>{};
                final lines = ((b['lines'] as List?) ?? []).take(2).join(', ');
                return ListTile(
                  key: ValueKey(r.id),
                  leading: SizedBox(width: 72, child: ClipRRect(borderRadius: BorderRadius.circular(3), child: IgnorePointer(child: SlideView(block: b, donors: donors)))),
                  title: Text('${i + 1}. ${slideTitle(b)}'),
                  subtitle: lines.isEmpty ? null : Text(lines, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: write ? ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle))) : null,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SlideViewer(store: store, meetingId: mid, start: i))),
                );
              },
            ),
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
    final contacts = [for (final c in store.contacts) c.body];
    Map? picked = rec == null ? null : contacts.where((c) => c['id'] == rec.body['contactId']).firstOrNull;
    var family = rec?.body['family'] == true;
    var style = rec?.body['style'] as String?;
    var keep = false;
    var kind = 'satsangi';
    final company = TextEditingController();
    // the text on the slide for what is typed now
    String shown() {
      final typed = name.text.trim();
      if (picked != null) return donorText(picked!, family: family, style: style);
      if (keep) return donorText({'name': typed, 'kind': kind, 'company': company.text}, family: family);
      return family ? '$typed & Family' : typed;
    }

    return _form(
      context,
      title: rec == null ? 'Add donor' : 'Change donor',
      fields: [
        StatefulBuilder(builder: (c, set) {
          final hits = picked == null && rec == null ? matchContacts(contacts, name.text) : const <Map>[];
          final c0 = picked;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), onChanged: (_) => set(() { if (picked != null) picked = null; })),
            for (final h in hits)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(donorText(h)),
                subtitle: Text('${h['kind']}'),
                onTap: () => set(() {
                  picked = h;
                  name.text = '${h['name']}';
                  family = h['family'] == true;
                  style = null;
                  keep = false;
                }),
              ),
            if (c0 != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('From the directory (${c0['kind']})', style: const TextStyle(fontSize: 12))),
            if (c0 == null || c0['kind'] == 'satsangi')
              CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, controlAffinity: ListTileControlAffinity.leading, title: const Text('& Family'), value: family, onChanged: (v) => set(() => family = v == true)),
            if (c0 != null && c0['kind'] == 'satsangi' && '${c0['company'] ?? ''}'.isNotEmpty)
              DropdownButtonFormField<String>(
                value: style ?? 'name-company',
                decoration: const InputDecoration(labelText: 'How the name shows'),
                items: const [DropdownMenuItem(value: 'name-company', child: Text('Name (Company)')), DropdownMenuItem(value: 'name', child: Text('Name only')), DropdownMenuItem(value: 'company', child: Text('Company only'))],
                onChanged: (v) => set(() => style = v),
              ),
            if (c0 == null && rec == null && name.text.trim().isNotEmpty && store.org.isNotEmpty) ...[
              CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, controlAffinity: ListTileControlAffinity.leading, title: const Text('Save to the donor directory'), value: keep, onChanged: (v) => set(() => keep = v == true)),
              if (keep)
                Row(children: [
                  DropdownButton<String>(value: kind, items: const [DropdownMenuItem(value: 'satsangi', child: Text('Satsangi')), DropdownMenuItem(value: 'company', child: Text('Company')), DropdownMenuItem(value: 'other', child: Text('Other'))], onChanged: (v) => set(() => kind = v ?? 'satsangi')),
                  if (kind == 'satsangi') ...[const SizedBox(width: 12), Expanded(child: TextField(controller: company, onChanged: (_) => set(() {}), decoration: const InputDecoration(labelText: 'Company (optional)')))],
                ]),
            ],
            if (name.text.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('On the slide: ${shown()}', style: const TextStyle(fontWeight: FontWeight.w600))),
          ]);
        }),
        TextField(controller: occasion, decoration: const InputDecoration(labelText: 'Occasion')),
      ],
      onSave: () async {
        if (name.text.trim().isEmpty) return false;
        if (picked == null && keep && rec == null) {
          if (!await store.addContact(name.text, kind, company.text, family)) return false;
          picked = store.contacts.where((c) => '${c.body['name']}' == name.text.replaceAll(RegExp(r'\s+'), ' ').trim() && '${c.body['kind']}' == kind).map((c) => c.body).firstOrNull;
        }
        final f = <String, dynamic>{'name': shown(), 'occasion': occasion.text.trim()};
        if (picked != null) {
          f['contactId'] = picked!['id'];
          if (picked!['kind'] == 'satsangi') f['family'] = family;
          if (style != null) f['style'] = style;
        } else if (rec?.body['contactId'] != null) {
          f['contactId'] = null;
        }
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
