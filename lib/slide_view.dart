import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// The look of the slides when the phone has not read the center's slide standard: the Ravi Sabha deck's colours (tan frame, red heading,
/// brown text). The back office shows the exact standard; this is a close preview for checking text and order.
const _bg = Color(0xFFC4AE8F), _frame = Color(0xFF9A7B2C), _heading = Color(0xFFC00000), _body = Color(0xFF6B3410), _name = Color(0xFF1F2F6B);

Color? colorFrom(Object? hex) {
  if (hex is! String) return null;
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  return m == null ? null : Color(0xFF000000 | int.parse(m[1]!, radix: 16));
}

final _dataUrl = RegExp(r'^data:image/(png|jpeg|gif|webp);base64,([A-Za-z0-9+/=\s]+)$');

/// The bytes of a picture slide's data URL, or null when it is not a picture the desktop would accept.
Uint8List? pictureBytes(Object? src) {
  if (src is! String) return null;
  final m = _dataUrl.firstMatch(src);
  if (m == null) return null;
  try { return base64Decode(m[2]!.replaceAll(RegExp(r'\s'), '')); } on FormatException { return null; }
}

/// Short name of a slide for lists.
String slideTitle(Map b) {
  final h = '${b['heading'] ?? ''}', l = '${b['label'] ?? ''}';
  if (h.isNotEmpty) return h;
  if (l.isNotEmpty) return l;
  switch (b['kind']) {
    case 'opening': return 'Opening slide';
    case 'closing': return 'Closing slide';
    case 'canvas': return 'Free layout slide';
    case 'table': return 'Table';
    case 'prasad': return 'Prasad sponsors';
    default: return '${b['kind'] ?? 'Slide'}';
  }
}

/// Text and poster slides can be written on the phone; the other kinds are made on the back office.
bool phoneEditable(Map b) => b['kind'] == 'text' || b['kind'] == 'poster';

/// A 16:9 picture of one slide. [block] is the slide's block as saved; [donors] are the meeting's donors, shown on the prasad slide.
class SlideView extends StatelessWidget {
  final Map block;
  final List<Map> donors;
  const SlideView({super.key, required this.block, this.donors = const []});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, u = w / 960; // 960 points across, as on the desktop
        final kind = block['kind'];
        final canvas = kind == 'canvas';
        final own = canvas ? colorFrom(block['bg']) : null;
        final chrome = canvas ? '${block['chrome'] ?? 'frame'}' : 'full';
        return Container(
          color: own ?? _bg,
          child: Stack(fit: StackFit.expand, children: [
            if (chrome != 'none') Padding(padding: EdgeInsets.all(14 * u), child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: _frame, width: 2.5 * u)))),
            if (chrome != 'none') Padding(padding: EdgeInsets.all(22 * u), child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: _frame, width: 1 * u)))),
            if (canvas) ..._canvas(w, u) else Padding(padding: EdgeInsets.fromLTRB(48 * u, 36 * u, 48 * u, 36 * u), child: _content(u)),
          ]),
        );
      }),
    );
  }

  List<String> get _lines => ((block['lines'] as List?) ?? const []).map((e) => '$e').toList();

  Widget _label(double u) => '${block['label'] ?? ''}'.isEmpty ? const SizedBox.shrink() : Padding(padding: EdgeInsets.only(bottom: 4 * u), child: Text('${block['label']}', style: TextStyle(color: _body, fontSize: 16 * u, fontWeight: FontWeight.w500)));

  Widget _content(double u) {
    switch (block['kind']) {
      case 'opening':
        return Center(child: Text('ANNOUNCEMENTS', textAlign: TextAlign.center, style: TextStyle(color: _name, fontSize: 56 * u, letterSpacing: 2 * u)));
      case 'closing':
        return Center(child: Text('JAI SWAMINARAYAN', textAlign: TextAlign.center, style: TextStyle(color: _name, fontSize: 56 * u, letterSpacing: 2 * u)));
      case 'table':
        final rows = ((block['rows'] as List?) ?? const []).whereType<List>().toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(u),
          for (final r in rows.take(10)) Padding(padding: EdgeInsets.symmetric(vertical: 4 * u), child: Row(children: [Expanded(child: Text('${r.isNotEmpty ? r[0] : ''}', style: TextStyle(color: _body, fontSize: 24 * u))), Expanded(child: Text('${r.length > 1 ? r[1] : ''}', style: TextStyle(color: _body, fontSize: 24 * u)))])),
        ]);
      case 'prasad':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${block['label'] ?? ''}'.isEmpty ? 'Prasad sponsors' : '${block['label']}', style: TextStyle(color: _heading, fontSize: 34 * u)),
          SizedBox(height: 10 * u),
          if (donors.isEmpty) Text('Donor names appear here.', style: TextStyle(color: _body, fontSize: 22 * u)),
          for (final d in donors.take(6)) Padding(padding: EdgeInsets.only(bottom: 6 * u), child: Text('${d['name'] ?? ''}${'${d['occasion'] ?? ''}'.isEmpty ? '' : '  ·  ${d['occasion']}'}', style: TextStyle(color: _name, fontSize: 24 * u))),
        ]);
      case 'poster':
        final pic = pictureBytes(block['image']);
        return Row(children: [
          Expanded(child: pic == null ? Center(child: Icon(Icons.image_outlined, size: 64 * u, color: _frame)) : Image.memory(pic, fit: BoxFit.contain)),
          SizedBox(width: 20 * u),
          Expanded(child: _textBlock(u)),
        ]);
      default:
        return _textBlock(u);
    }
  }

  Widget _textBlock(double u) {
    final ls = _lines;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      _label(u),
      if ('${block['heading'] ?? ''}'.isNotEmpty) Text('${block['heading']}', style: TextStyle(color: _heading, fontSize: 38 * u, fontWeight: FontWeight.w500)),
      SizedBox(height: 10 * u),
      for (final l in ls.take(8)) Padding(padding: EdgeInsets.only(bottom: 6 * u), child: Text(l, style: TextStyle(color: _body, fontSize: 26 * u))),
    ]);
  }

  List<Widget> _canvas(double w, double u) {
    final k = w / 13.333; // pixels per inch
    final out = <Widget>[];
    for (final e in ((block['elements'] as List?) ?? const [])) {
      if (e is! Map) continue;
      double n(String key) => e[key] is num ? (e[key] as num).toDouble() : 0;
      Widget? child;
      if (e['type'] == 'text') {
        final align = e['align'] == 'center' ? TextAlign.center : e['align'] == 'right' ? TextAlign.right : TextAlign.left;
        final v = e['valign'] == 'middle' ? Alignment.center : e['valign'] == 'bottom' ? Alignment.bottomCenter : Alignment.topCenter;
        child = Container(
          alignment: v,
          padding: EdgeInsets.all(4 * u),
          decoration: BoxDecoration(color: colorFrom(e['fill']), border: colorFrom(e['border']) == null ? null : Border.all(color: colorFrom(e['border'])!, width: (n('borderW') <= 0 ? 1 : n('borderW')) * u)),
          child: SizedBox(width: double.infinity, child: Text('${e['text'] ?? ''}', textAlign: align, style: TextStyle(
            color: colorFrom(e['color']) ?? _body, fontSize: (n('size') <= 0 ? 24 : n('size')) * u,
            fontWeight: e['bold'] == true ? FontWeight.w700 : FontWeight.w400, fontStyle: e['italic'] == true ? FontStyle.italic : FontStyle.normal,
            decoration: e['underline'] == true ? TextDecoration.underline : TextDecoration.none))),
        );
      } else if (e['type'] == 'image') {
        final pic = pictureBytes(e['src']);
        child = pic == null ? null : Image.memory(pic, fit: BoxFit.contain);
      } else if (e['type'] == 'shape') {
        final fill = colorFrom(e['fill']), line = colorFrom(e['line']), lw = (n('lineW') <= 0 ? 1 : n('lineW')) * u;
        if (e['shape'] == 'line') {
          child = Align(alignment: Alignment.center, child: Container(height: lw, color: line ?? _body));
        } else {
          child = e['shape'] == 'ellipse'
              ? DecoratedBox(decoration: ShapeDecoration(color: fill, shape: OvalBorder(side: line == null ? BorderSide.none : BorderSide(color: line, width: lw))))
              : Container(decoration: BoxDecoration(color: fill, border: line == null ? null : Border.all(color: line, width: lw)));
        }
      }
      if (child == null) continue;
      out.add(Positioned(left: n('x') * k, top: n('y') * k, width: n('w') * k, height: n('h') * k, child: Transform.rotate(angle: n('rot') * 3.1415926535 / 180, child: child)));
    }
    return out;
  }
}
