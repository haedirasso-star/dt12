part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  المحلّل الذكي لرسائل الحسابات (نقل حرفي من لوحة الويب)
//  يفهم: جدول البنل · «Username: x / Password: y» · روابط m3u
//        وروابط http://host/user/pass · أسطر «يوزر باسوورد تاريخ»
// ════════════════════════════════════════════════════════════════════
class LineRow {
  String panelId = '', reseller = '', fullName = '', notes = '';
  String username, password, host;
  String package;
  int? pkgDays;
  String? createdOn;      // YYYY-MM-DD
  String? expiryDate;     // ISO مع +03:00
  bool expired = false;
  int maxConn = 1;
  bool needsReview = false;
  String reviewReason = '';
  bool take = true;
  LineRow({required this.username, required this.password, this.host = '', this.package = ''});

  bool get active => !expired;

  Map<String, dynamic> toJson() => {
    'panel_id': panelId, 'reseller': reseller, 'full_name': fullName, 'notes': notes,
    'username': username, 'password': password, 'host': host,
    'package': package, 'pkg_days': pkgDays, 'created_on': createdOn,
    'expiry_date': expiryDate, 'expired': expired, 'max_conn': maxConn,
    'needs_review': needsReview, 'review_reason': reviewReason,
  };
}

class Panel {
  static const tz = '+03:00'; // توقيت بغداد — تواريخ البنل محلية
  static final dateRe = RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?');
  static final dmyRe = RegExp(r'(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})(?:[ T]+(\d{1,2}):(\d{2}))?');
  static final expiredRe = RegExp(r'منته|انته|expired|غير\s*فعال', caseSensitive: false);
  static final pkgRe = RegExp(r'باق|package|bouquet|شهر|اشهر|أشهر|عام|سنة|سنه|month|year|يوم|ايام|أيام|days?', caseSensitive: false);
  static final connRe = RegExp(r'^(\d+)\s*/\s*(\d+)$');
  static final tokenRe = RegExp(r'^[A-Za-z0-9._@#$!%*+\-=~]{3,}$');
  static final _arDigits = {'٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9'};

  static String toLatin(String s) => s.replaceAllMapped(RegExp('[٠-٩]'), (m) => _arDigits[m[0]]!);
  static String _p(String? n) => (n ?? '0').padLeft(2, '0');

  static String? parseDate(String s) {
    s = toLatin(s).trim();
    var m = dateRe.firstMatch(s);
    if (m != null) return '${m[1]}-${_p(m[2])}-${_p(m[3])}T${_p(m[4])}:${_p(m[5])}:00$tz';
    m = dmyRe.firstMatch(s);
    if (m != null) return '${m[3]}-${_p(m[2])}-${_p(m[1])}T${_p(m[4])}:${_p(m[5])}:00$tz';
    return null;
  }

  static bool isDateCell(String c) => parseDate(c) != null && RegExp(r'\d{4}').hasMatch(toLatin(c));

  static int? pkgDays(String? s) {
    s = toLatin(s ?? '').toLowerCase();
    if (s.isEmpty) return null;
    RegExpMatch? m;
    if ((m = RegExp(r'(\d+)\s*(يوم|ايام|أيام|days?)').firstMatch(s)) != null) return int.parse(m![1]!);
    if (RegExp(r'عامين|سنتين').hasMatch(s)) return 730;
    if ((m = RegExp(r'(\d+)\s*(عام|اعوام|أعوام|سنة|سنوات|سنه|years?)').firstMatch(s)) != null) return int.parse(m![1]!) * 365;
    if (RegExp(r'عام|سنة|سنه|year').hasMatch(s)) return 365;
    if (RegExp(r'شهرين').hasMatch(s)) return 60;
    if ((m = RegExp(r'(\d+)\s*(شهر|اشهر|أشهر|months?)').firstMatch(s)) != null) return int.parse(m![1]!) * 30;
    if (RegExp(r'شهر|month').hasMatch(s)) return 30;
    return null;
  }

  static String normHost(String v) {
    v = v.trim().replaceAll(RegExp(r'[\s،,]+$'), '');
    final m = RegExp(r'(https?://)?([a-z0-9][a-z0-9.-]*\.[a-z]{2,}|\d{1,3}(?:\.\d{1,3}){3})(:\d{2,5})?', caseSensitive: false).firstMatch(v);
    if (m == null) return '';
    return '${m[1] ?? 'http://'}${m[2]!.toLowerCase()}${m[3] ?? ''}';
  }

  static List<String> _tokenizeLoose(String line) {
    final t = line.split(RegExp(r'\s+'));
    final out = <String>[];
    for (var i = 0; i < t.length; i++) {
      final w = t[i];
      final nx = i + 1 < t.length ? t[i + 1] : '';
      if (dateRe.hasMatch(w) && RegExp(r'^\d{1,2}:\d{2}').hasMatch(nx)) { out.add('$w $nx'); i++; continue; }
      if (w.startsWith('منته') && nx.startsWith('الصلاح')) { out.add('$w $nx'); i++; continue; }
      if (w.startsWith('باق')) {
        var pk = w;
        while (i + 1 < t.length && !dateRe.hasMatch(t[i + 1]) && !connRe.hasMatch(t[i + 1]) && !expiredRe.hasMatch(t[i + 1])) {
          pk += ' ${t[++i]}';
        }
        out.add(pk);
        continue;
      }
      out.add(w);
    }
    return out;
  }

  static LineRow? _parseCells(List<String> cells) {
    final nz = <(String, int)>[];
    for (var i = 0; i < cells.length; i++) { if (cells[i].isNotEmpty) nz.add((cells[i], i)); }
    if (nz.length < 3) return null;
    final idCell = nz.where((x) => RegExp(r'^\d{5,10}$').hasMatch(x.$1)).firstOrNull;
    final dateCells = nz.where((x) => isDateCell(x.$1) || expiredRe.hasMatch(x.$1)).toList();
    final firstDateIdx = dateCells.isEmpty ? 1 << 30 : dateCells.first.$2;
    final pkgCell = nz.where((x) => x.$2 < firstDateIdx && !isDateCell(x.$1) && RegExp(r'باق|package', caseSensitive: false).hasMatch(x.$1)).firstOrNull
        ?? nz.where((x) => x.$2 < firstDateIdx && !isDateCell(x.$1) && pkgRe.hasMatch(x.$1) && x.$1.contains(' ')).firstOrNull;
    final connCell = nz.where((x) => connRe.hasMatch(x.$1)).firstOrNull;
    final stopIdx = pkgCell?.$2 ?? firstDateIdx;
    final before = nz.where((x) => x.$2 < stopIdx && x != idCell).toList();
    if (before.length < 2) return null;
    final pass = before[before.length - 1], user = before[before.length - 2];
    final middle = before.sublist(0, before.length - 2);

    String? created, expiry;
    var expired = false;
    final dates = dateCells.where((x) => x.$2 > stopIdx || pkgCell == null).toList();
    for (final d in dates) {
      if (expiredRe.hasMatch(d.$1) && !isDateCell(d.$1)) { expired = true; continue; }
      if (created == null) { created = parseDate(d.$1); }
      else { expiry ??= parseDate(d.$1); }
    }
    if (created != null && expiry == null && !expired && dates.length == 1) {
      if (RegExp(r'\d{1,2}:\d{2}').hasMatch(dates.first.$1)) { expiry = created; created = null; }
    }
    final lastDateIdx = dates.isEmpty ? stopIdx : dates.last.$2;
    final notes = nz.where((x) => x.$2 > lastDateIdx && x != connCell).map((x) => x.$1).join(' ').trim();
    final conn = connCell == null ? null : connRe.firstMatch(connCell.$1);

    final r = LineRow(username: user.$1, password: pass.$1, package: pkgCell?.$1 ?? '')
      ..panelId = idCell?.$1 ?? ''
      ..reseller = middle.isNotEmpty ? middle.first.$1 : ''
      ..fullName = middle.skip(1).map((x) => x.$1).join(' ')
      ..pkgDays = pkgDays(pkgCell?.$1)
      ..createdOn = created?.substring(0, 10)
      ..expiryDate = expiry
      ..expired = expired
      ..maxConn = conn == null ? 1 : math.max(int.parse(conn[2]!), 1)
      ..notes = notes;
    return r;
  }

  static final _keys = <(String, RegExp)>[
    ('created', RegExp(r'created|إنشاء|انشاء|أنشئ', caseSensitive: false)),
    ('expiry', RegExp(r'exp|valid|until|انتهاء|ينتهي|الانتهاء|صلاحي|تاريخ', caseSensitive: false)),
    ('password', RegExp(r'pass|pwd|باس|كلمة\s*المرور|كلمه\s*المرور|الرمز|رمز|كلمة\s*السر', caseSensitive: false)),
    ('username', RegExp(r'user|login|يوزر|اسم\s*المستخدم|المستخدم|اليوزر', caseSensitive: false)),
    ('host', RegExp(r'host|url|server|portal|dns|domain|هوست|سيرفر|السيرفر|رابط|الرابط|الخادم|بورتال|دومين', caseSensitive: false)),
    ('max', RegExp(r'max|conn|اتصال|اجهز|أجهز|شاشات', caseSensitive: false)),
    ('package', RegExp(r'package|plan|bouquet|باق|اشتراك', caseSensitive: false)),
  ];
  static String? _keyOf(String k) {
    for (final (name, re) in _keys) { if (re.hasMatch(k)) return name; }
    return null;
  }

  /// تحليل أي رسالة فيها حسابات
  static List<LineRow> parseAny(String text) {
    text = toLatin(text).replaceAll(RegExp('[‎‏‪-‮⁦-⁩]'), '');
    final rows = <LineRow>[];
    var blockHost = '', lineHost = '';
    Map<String, String>? kv;

    LineRow mk(Map<String, String> o) {
      final r = LineRow(username: o['username'] ?? '', password: o['password'] ?? '', host: o['host'] ?? '', package: o['package'] ?? '')
        ..pkgDays = pkgDays(o['package'])
        ..createdOn = o['created'] == null ? null : parseDate(o['created']!)?.substring(0, 10)
        ..expiryDate = o['expiry']
        ..expired = o['expired'] == '1'
        ..maxConn = math.max(int.tryParse(o['max'] ?? '') ?? 1, 1);
      return r;
    }
    void flush() {
      if (kv != null && (kv!['username'] ?? '').isNotEmpty && (kv!['password'] ?? '').isNotEmpty) rows.add(mk(kv!));
      kv = null;
    }

    final kvRe = RegExp(r'^[^\p{L}\p{N}]*([\p{L}\s_.]{2,30}?)\s*[:：=＝]\s*(.*)$', unicode: true);
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'اسم المستخدم|username', caseSensitive: false).hasMatch(line) &&
          RegExp(r'كلمة المرور|password', caseSensitive: false).hasMatch(line) && !RegExp(r'[:：=]').hasMatch(line)) continue;

      // (1) روابط فيها الحساب
      var hit = false;
      for (final m in RegExp(r'(https?://[^\s/?#]+)/(?:get|player_api|xmltv)\.php\?(\S+)', caseSensitive: false).allMatches(line)) {
        try {
          final q = Uri.splitQueryString(m[2]!.replaceAll('&amp;', '&'));
          if ((q['username'] ?? '').isNotEmpty && (q['password'] ?? '').isNotEmpty) {
            rows.add(mk({'host': normHost(m[1]!), 'username': q['username']!, 'password': q['password']!}));
            hit = true;
          }
        } catch (_) {}
      }
      for (final m in RegExp(r'(https?://[^\s/?#]+)/(?:live/|movie/|series/)?([A-Za-z0-9._@-]{3,})/([A-Za-z0-9._@-]{3,})/\d+', caseSensitive: false).allMatches(line)) {
        rows.add(mk({'host': normHost(m[1]!), 'username': m[2]!, 'password': m[3]!}));
        hit = true;
      }
      if (hit) continue;

      // (2) مفتاح: قيمة
      final km = kvRe.firstMatch(line);
      final key = km == null ? null : _keyOf(km[1]!);
      if (key != null) {
        final v = km![2]!.trim();
        if (key == 'host') {
          final h = normHost(v);
          if (kv != null && (kv!['username'] ?? '').isNotEmpty && (kv!['password'] ?? '').isNotEmpty) flush();
          if (h.isNotEmpty) blockHost = h;
          if (kv != null) kv!['host'] = blockHost;
          continue;
        }
        if (key == 'username' && kv != null && (kv!['username'] ?? '').isNotEmpty) flush();
        kv ??= {'host': blockHost};
        if (key == 'username' || key == 'password') {
          kv![key] = v.split(RegExp(r'\s+')).first;
        } else if (key == 'expiry') {
          if (expiredRe.hasMatch(v) && !dateRe.hasMatch(v)) { kv!['expired'] = '1'; }
          else { final d = parseDate(v); if (d != null) kv!['expiry'] = d; }
        } else if (key == 'created') {
          kv!['created'] = v;
        } else if (key == 'max') {
          final mm = RegExp(r'(\d+)\s*$').firstMatch(v) ?? RegExp(r'\d+').firstMatch(v);
          if (mm != null) kv!['max'] = mm.groupCount >= 1 && mm[1] != null ? mm[1]! : mm[0]!;
        } else if (key == 'package') {
          kv!['package'] = v;
        }
        continue;
      }
      if (kv != null && (kv!['username'] ?? '').isNotEmpty && (kv!['password'] ?? '').isNotEmpty) flush();

      // (3) سطر هوست وحده
      if (RegExp(r'^(https?://)?[a-z0-9][a-z0-9.-]*\.[a-z]{2,}(:\d{2,5})?/?$', caseSensitive: false).hasMatch(line) ||
          RegExp(r'^(https?://)?\d{1,3}(\.\d{1,3}){3}(:\d{2,5})?/?$').hasMatch(line)) {
        blockHost = lineHost = normHost(line);
        continue;
      }

      // (4) صف جدول البنل
      if (line.contains('\t') || (RegExp(r'باق|منته').hasMatch(line) && dateRe.hasMatch(line))) {
        final r = line.contains('\t') ? _parseCells(raw.split('\t').map((c) => c.trim()).toList()) : _parseCells(_tokenizeLoose(line));
        if (r != null) { r.host = lineHost; rows.add(r); continue; }
      }

      // (5) سطر بسيط: يوزر باسوورد [تاريخ]
      final dates = dateRe.allMatches(line).map((m) => m[0]!).toList();
      final rest = line.replaceAll(dateRe, ' ').replaceAll(RegExp(r'\d{1,2}:\d{2}'), ' ');
      final toks = rest.split(RegExp(r'[\s|,;:/\\]+')).where((t) => tokenRe.hasMatch(t) && !RegExp(r'^\d{1,2}$').hasMatch(t)).toList();
      String? u, p;
      if (toks.length == 2) { u = toks[0]; p = toks[1]; }
      else if (toks.length == 3 && RegExp(r'^\d{5,10}$').hasMatch(toks[0])) { u = toks[1]; p = toks[2]; }
      if (u != null && p != null && !RegExp(r'^https?$', caseSensitive: false).hasMatch(u)) {
        final o = <String, String>{'username': u, 'password': p, 'host': blockHost};
        if (dates.length >= 2) { o['created'] = dates[0]; final e = parseDate(dates[1]); if (e != null) o['expiry'] = e; }
        else if (dates.length == 1) { final e = parseDate(dates[0]); if (e != null) o['expiry'] = e; }
        if (expiredRe.hasMatch(line) && dates.length < 2) {
          o['expired'] = '1'; o.remove('expiry');
          if (dates.isNotEmpty) o['created'] = dates[0];
        }
        rows.add(mk(o));
      }
    }
    flush();

    // دمج المكرر
    final map = <String, LineRow>{};
    for (final r in rows) {
      final k = '${r.username.toLowerCase()}|${r.password}';
      final o = map[k];
      if (o == null) { map[k] = r; continue; }
      if (o.host.isEmpty) o.host = r.host;
      if (o.package.isEmpty) o.package = r.package;
      o.pkgDays ??= r.pkgDays;
      o.createdOn ??= r.createdOn;
      o.expiryDate ??= r.expiryDate;
    }
    return finalize(map.values.toList());
  }

  /// فحص الجودة: يحدد ما يحتاج مراجعة قبل الحفظ
  static List<LineRow> finalize(List<LineRow> rows) {
    final seen = <String>{};
    final now = DateTime.now();
    final ar = RegExp(r'[؀-ۿ\s]');
    for (final r in rows) {
      final why = <String>[];
      final k = r.username.toLowerCase();
      if (!seen.add(k)) why.add('مكرّر في نفس الدفعة');
      if (ar.hasMatch(r.username) || ar.hasMatch(r.password)) why.add('حروف غير متوقعة');
      if (r.password.length < 6) why.add('باسوورد قصير');
      if (r.username.length < 3) why.add('يوزر قصير');
      if (!r.expired && r.expiryDate == null) why.add('بلا تاريخ انتهاء');
      final exp = r.expiryDate == null ? null : DateTime.tryParse(r.expiryDate!);
      if (r.createdOn != null && exp != null && r.pkgDays != null) {
        final c = DateTime.tryParse('${r.createdOn}T00:00:00$tz');
        if (c != null) {
          final span = exp.difference(c).inHours / 24;
          final tol = math.max(3, r.pkgDays! * .04);
          if ((span - r.pkgDays!).abs() > tol + 1) why.add('التاريخ لا يطابق الباقة (${span.round()} يوم)');
        }
      }
      if (exp != null && !exp.isAfter(now)) r.expired = true;
      r.needsReview = why.isNotEmpty;
      r.reviewReason = why.join(' · ');
      r.take = !r.expired;
    }
    return rows;
  }
}
