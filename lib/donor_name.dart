/// How a donor from the directory is shown on a slide. Same rules as the back office, so a name looks the same wherever it was added.
String donorText(Map c, {bool family = false, String? style}) {
  String clean(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
  final name = clean(c['name']);
  if (c['kind'] != 'satsangi') return name;
  final company = clean(c['company']);
  final base = family ? '$name & Family' : name;
  if (company.isEmpty || style == 'name') return base;
  if (style == 'company') return company;
  return '$base ($company)';
}

/// Directory entries that match what is typed (name or company), names that start with it first.
List<Map> matchContacts(Iterable<Map> contacts, String typed, {int limit = 6}) {
  final q = typed.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  if (q.isEmpty) return [];
  int rank(Map c) {
    final n = '${c['name']}'.toLowerCase(), co = '${c['company'] ?? ''}'.toLowerCase();
    if (n.startsWith(q)) return 0;
    if (n.contains(q)) return 1;
    if (co.contains(q)) return 2;
    return 3;
  }

  final hits = [for (final c in contacts) if (rank(c) < 3) c]..sort((a, b) => rank(a).compareTo(rank(b)));
  return hits.take(limit).toList();
}
