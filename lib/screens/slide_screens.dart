import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api.dart';
import '../slide_view.dart';
import '../store.dart';

/// Biggest picture the phone will put on a slide, as a data URL (the back office refuses pictures over 8 MB).
const maxPictureChars = 6 * 1024 * 1024;

/// A picked picture: its bytes and the kind the data URL names.
class PickedPicture {
  final Uint8List bytes;
  final String mime;
  PickedPicture(this.bytes, this.mime);
}

typedef PicturePicker = Future<PickedPicture?> Function(BuildContext context);

/// Where pictures come from. Tests put a pretend picker here.
PicturePicker picturePicker = pickFromPhone;

String _mimeOf(Uint8List b, String name) {
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpeg';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
  if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45) return 'webp';
  final n = name.toLowerCase();
  return n.endsWith('.png') ? 'png' : n.endsWith('.gif') ? 'gif' : n.endsWith('.webp') ? 'webp' : 'jpeg';
}

/// Asks where the picture comes from (gallery or camera) and returns it, made smaller so it fits on a slide and in a save.
Future<PickedPicture?> pickFromPhone(BuildContext context) async {
  final from = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(c, ImageSource.camera)),
    ])),
  );
  if (from == null) return null;
  final f = await ImagePicker().pickImage(source: from, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
  if (f == null) return null;
  final b = await f.readAsBytes();
  return PickedPicture(b, _mimeOf(b, f.name));
}

String pictureUrl(PickedPicture p) => 'data:image/${p.mime};base64,${base64Encode(p.bytes)}';

/// Add or change a text or picture slide, with the slide drawn below the fields as it is typed.
class SlideForm extends StatefulWidget {
  final Store store;
  final String meetingId;
  final Rec? rec;
  const SlideForm({super.key, required this.store, required this.meetingId, this.rec});

  @override
  State<SlideForm> createState() => _SlideFormState();
}

class _SlideFormState extends State<SlideForm> {
  late final Map<String, dynamic> _block = Map<String, dynamic>.from(widget.rec?.body['block'] is Map ? widget.rec!.body['block'] as Map : {});
  late final TextEditingController _label = TextEditingController(text: '${_block['label'] ?? ''}');
  late final TextEditingController _heading = TextEditingController(text: '${_block['heading'] ?? ''}');
  late final TextEditingController _lines = TextEditingController(text: ((_block['lines'] as List?) ?? []).join('\n'));
  late bool _poster = _block['kind'] == 'poster';
  late String _image = '${_block['image'] ?? ''}';
  String? _error;
  bool _saving = false;

  @override
  void dispose() { _label.dispose(); _heading.dispose(); _lines.dispose(); super.dispose(); }

  List<String> get _lineList => _lines.text.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  Map<String, dynamic> _current() => {
        ..._block,
        'id': _block['id'] ?? widget.rec?.id ?? 'preview',
        'kind': _poster ? 'poster' : 'text',
        'label': _label.text.trim(), 'heading': _heading.text.trim(), 'lines': _lineList,
        if (_poster) 'image': _image else ..._noImage,
      };
  static const _noImage = <String, dynamic>{};

  Future<void> _choose() async {
    final p = await picturePicker(context);
    if (p == null) return;
    final url = pictureUrl(p);
    if (url.length > maxPictureChars) { setState(() => _error = 'That picture is too big. Choose a smaller one.'); return; }
    setState(() { _image = url; _error = null; });
  }

  Future<void> _save() async {
    final b = _current();
    if (_heading.text.trim().isEmpty && _lineList.isEmpty && (!_poster || _image.isEmpty)) { setState(() => _error = 'Write a heading or some lines first.'); return; }
    if (_poster && _image.isEmpty) { setState(() => _error = 'Add a picture, or switch to a text slide.'); return; }
    setState(() { _saving = true; _error = null; });
    final r = widget.rec;
    final ok = r == null ? await widget.store.add('slide', widget.meetingId, {'block': b}) : await widget.store.update(r, {'block': {...b, 'id': r.id}});
    if (!mounted) return;
    if (ok) { Navigator.pop(context); } else { setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final donors = [for (final d in widget.store.donorsOf(widget.meetingId)) Map<String, dynamic>.from(d.body)];
    return Scaffold(
      appBar: AppBar(title: Text(widget.rec == null ? 'Add slide' : 'Change slide')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.store.message != null) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF3D9B8), borderRadius: BorderRadius.circular(6)), child: Text(widget.store.message!)),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Text'), icon: Icon(Icons.notes)), ButtonSegment(value: true, label: Text('Picture'), icon: Icon(Icons.image_outlined))],
          selected: {_poster}, onSelectionChanged: (s) => setState(() => _poster = s.first),
        ),
        const SizedBox(height: 12),
        TextField(controller: _label, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Label (small title)')),
        const SizedBox(height: 12),
        TextField(controller: _heading, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Heading')),
        const SizedBox(height: 12),
        TextField(controller: _lines, onChanged: (_) => setState(() {}), minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'Lines (one per line)')),
        if (_poster) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: _choose, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(_image.isEmpty ? 'Add picture' : 'Change picture')),
            if (_image.isNotEmpty) TextButton(onPressed: () => setState(() => _image = ''), child: const Text('Remove picture')),
          ]),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFB3261E)))),
        const SizedBox(height: 16),
        const Text('Preview', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: SlideView(key: const ValueKey('form-preview'), block: _current(), donors: donors)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save')),
      ]),
    );
  }
}

/// Looks at the meeting's slides one by one (swipe), starting at [start]; change or delete the one on show.
class SlideViewer extends StatefulWidget {
  final Store store;
  final String meetingId;
  final int start;
  const SlideViewer({super.key, required this.store, required this.meetingId, required this.start});

  @override
  State<SlideViewer> createState() => _SlideViewerState();
}

class _SlideViewerState extends State<SlideViewer> {
  late final PageController _pc = PageController(initialPage: widget.start);
  late int _at = widget.start;

  @override
  void dispose() { _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final slides = widget.store.slidesOf(widget.meetingId);
        if (slides.isEmpty) return Scaffold(appBar: AppBar(title: const Text('Slides')), body: const Center(child: Text('No slides left.')));
        final at = _at.clamp(0, slides.length - 1);
        final rec = slides[at];
        final b = rec.body['block'] is Map ? Map<String, dynamic>.from(rec.body['block'] as Map) : <String, dynamic>{};
        final donors = [for (final d in widget.store.donorsOf(widget.meetingId)) Map<String, dynamic>.from(d.body)];
        final write = widget.store.canWrite;
        return Scaffold(
          appBar: AppBar(title: Text('Slide ${at + 1} of ${slides.length}')),
          body: Column(children: [
            Expanded(child: PageView.builder(
              controller: _pc, itemCount: slides.length, onPageChanged: (i) => setState(() => _at = i),
              itemBuilder: (c, i) {
                final bb = slides[i].body['block'] is Map ? Map<String, dynamic>.from(slides[i].body['block'] as Map) : <String, dynamic>{};
                return Center(child: Padding(padding: const EdgeInsets.all(12), child: SlideView(block: bb, donors: donors)));
              },
            )),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text(slideTitle(b), style: const TextStyle(fontWeight: FontWeight.w500))),
            if (write && !phoneEditable(b)) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 4), child: Text('This kind of slide is changed on the back office.', style: TextStyle(fontSize: 12))),
            SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 4, children: [
              IconButton(tooltip: 'Previous slide', onPressed: at > 0 ? () => _pc.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut) : null, icon: const Icon(Icons.chevron_left)),
              IconButton(tooltip: 'Next slide', onPressed: at < slides.length - 1 ? () => _pc.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut) : null, icon: const Icon(Icons.chevron_right)),
              if (write && phoneEditable(b)) FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => SlideForm(store: widget.store, meetingId: widget.meetingId, rec: rec))), icon: const Icon(Icons.edit_outlined), label: const Text('Change')),
              if (write) TextButton.icon(onPressed: () => _delete(context, rec), icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
            ]))),
          ]),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, Rec rec) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Delete this slide?'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))],
    ));
    if (ok == true) await widget.store.delete(rec);
  }
}
