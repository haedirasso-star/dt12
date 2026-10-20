part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🗂 قاعدة المستخدمين على الهاتف
//  • «تحميل الكل»: كل المستخدمين وبياناتهم مرة واحدة (حقول خفيفة فقط)
//  • «تحديث الجديد»: فقط من دخل التطبيق منذ آخر تحميل ⇐ قراءات قليلة
//  • تبقى محفوظة على الهاتف — لا قراءة إلا عند ضغطك الزر
//  • بحث وفلاتر فورية بلا إنترنت + تصدير CSV
// ════════════════════════════════════════════════════════════════════
class UsersDb {
  static const _file = 'users_all_v1';
  static final rows = Live<List<Map<String, dynamic>>>([]);
  static final progress = Live<int>(-1);          // -1 = لا تحميل جارٍ
  static DateTime? at;                             // آخر تحميل
  static bool _loaded = false;
  static bool busy = false;

  static const _mask = [
    'email', 'display_name', 'name', 'phone', 'phone_number', 'status', 'last_seen', 'created_at',
    'last_login', 'platform', 'app_version', 'subscription.plan', 'subscription.expiry_date',
    'subscription.username', 'subscription.agent', 'free_watch.used_ms',
  ];

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final c = await DiskCache.read(_file);
    if (c is Map) {
      at = DateTime.tryParse('${c['at'] ?? ''}');
      rows.value = ((c['rows'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  }

  static Map<String, dynamic> _compact(String id, Map<String, dynamic> m) {
    final sub = m.m('subscription');
    final fw = m.m('free_watch');
    String iso(dynamic v) => v is DateTime ? v.toIso8601String() : (v == null ? '' : '$v');
    return {
      'id': id,
      'email': m.str('email').toLowerCase(),
      'name': m.str('display_name').isNotEmpty ? m.str('display_name') : m.str('name'),
      'phone': m.str('phone').isNotEmpty ? m.str('phone') : m.str('phone_number'),
      'status': m.str('status'),
      'seen': iso(m['last_seen'] ?? m['last_login']),
      'created': iso(m['created_at']),
      'platform': m.str('platform'),
      'ver': m.str('app_version'),
      'plan': sub.str('plan'),
      'exp': iso(sub['expiry_date']),
      'user': sub.str('username'),
      'agent': sub.str('agent'),
      'free': fw.i('used_ms'),
    };
  }

  /// [full] = كل المستخدمين · وإلا من نشط منذ آخر تحميل فقط
  static Future<int> download({bool full = true}) async {
    if (busy) return 0;
    busy = true;
    progress.value = 0;
    final byId = {for (final r in rows.value) r.str('id'): r};
    final since = full ? null : at?.subtract(const Duration(minutes: 10));
    final started = DateTime.now();
    var fetched = 0;
    try {
      String? cursorName;
      String? cursorSeen;
      while (true) {
        final q = <String, dynamic>{
          'from': [{'collectionId': 'users'}],
          'select': {'fields': _mask.map((f) => {'fieldPath': f}).toList()},
          'limit': 1000,
        };
        if (since == null) {
          q['orderBy'] = [{'field': {'fieldPath': '__name__'}, 'direction': 'ASCENDING'}];
          if (cursorName != null) q['startAt'] = {'values': [{'referenceValue': cursorName}], 'before': false};
        } else {
          q['where'] = {'fieldFilter': {'field': {'fieldPath': 'last_seen'}, 'op': 'GREATER_THAN_OR_EQUAL',
              'value': {'timestampValue': since.toUtc().toIso8601String()}}};
          q['orderBy'] = [
            {'field': {'fieldPath': 'last_seen'}, 'direction': 'ASCENDING'},
            {'field': {'fieldPath': '__name__'}, 'direction': 'ASCENDING'},
          ];
          if (cursorName != null && cursorSeen != null) {
            q['startAt'] = {'values': [{'timestampValue': cursorSeen}, {'referenceValue': cursorName}], 'before': false};
          }
        }
        final r = await Net.req('POST', '${FsRest._base}:runQuery', headers: await FsRest._h(),
            body: {'structuredQuery': q}, timeout: const Duration(seconds: 90));
        if (!r.ok) throw Exception(r.code == 403 ? 'لا صلاحية لقراءة المستخدمين' : 'Firestore HTTP ${r.code}');
        var n = 0;
        for (final row in (r.body as List? ?? const [])) {
          final d = (row as Map)['document'];
          if (d is! Map) continue;
          final name = '${d['name']}';
          final raw = (d['fields'] as Map?) ?? const {};
          final m = FsRest.fields(raw);
          final id = name.split('/').last;
          byId[id] = _compact(id, m);
          cursorName = name;
          final ls = raw['last_seen'];
          if (ls is Map && ls['timestampValue'] != null) cursorSeen = '${ls['timestampValue']}';
          n++;
        }
        fetched += n;
        progress.value = fetched;
        if (n < 1000) break;
      }
      final list = byId.values.toList()
        ..sort((a, b) => b.str('seen').compareTo(a.str('seen')));
      rows.value = list;
      at = started;
      await DiskCache.write(_file, {'at': at!.toIso8601String(), 'rows': list});
      BotLog.add('users', '🗂 تحميل المستخدمين', '${full ? 'كامل' : 'تحديث'}: $fetched قراءة · المجموع ${list.length}');
      return fetched;
    } finally {
      busy = false;
      progress.value = -1;
    }
  }

  static Future<void> clear() async {
    rows.value = [];
    at = null;
    await DiskCache.write(_file, {'at': '', 'rows': []});
  }

  static Future<String> exportCsv(List<Map<String, dynamic>> list) async {
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    final b = StringBuffer('﻿uid,email,name,phone,plan,expiry,server_user,status,last_seen,created,platform,version\n');
    for (final r in list) {
      b.writeln([r.str('id'), r.str('email'), r.str('name'), r.str('phone'), r.str('plan'), r.str('exp'), r.str('user'),
          r.str('status'), r.str('seen'), r.str('created'), r.str('platform'), r.str('ver')].map(esc).join(','));
    }
    final dir = await getTemporaryDirectory();
    final t = DateTime.now();
    final f = File('${dir.path}/totv_users_${t.year}${Fmt.two(t.month)}${Fmt.two(t.day)}.csv');
    await f.writeAsString(b.toString());
    return f.path;
  }
}

class UsersDbPage extends StatefulWidget {
  const UsersDbPage({super.key});
  @override State<UsersDbPage> createState() => _UsersDbPageState();
}

class _UsersDbPageState extends State<UsersDbPage> {
  final _q = TextEditingController();
  String _f = 'all';
  int _show = 80;

  @override
  void initState() { super.initState(); UsersDb.load().then((_) { if (mounted) setState(() {}); }); }
  @override
  void dispose() { _q.dispose(); super.dispose(); }

  Future<void> _download(bool full) async {
    final n = UsersDb.rows.value.length;
    if (full) {
      if (!await UI.confirm('تحميل كل المستخدمين؟',
          'يقرأ كل المستخدمين مرة واحدة (قراءة لكل مستخدم من حصة Firebase اليومية'
          '${n > 0 ? '، حوالي ${Fmt.n(n)}' : ''}).\nبعدها استخدم «تحديث الجديد» فقط — أرخص بكثير.', ok: 'تحميل')) return;
    } else if (UsersDb.at == null) {
      UI.toast('حمّل الكل أولاً مرة واحدة', error: true);
      return;
    }
    setState(() {});
    try {
      final got = await UsersDb.download(full: full);
      UI.toast(full ? 'حُمّل ${Fmt.n(UsersDb.rows.value.length)} مستخدم ✅' : 'حُدّث $got مستخدم ✅');
    } catch (e) { UI.err(e); }
    if (mounted) setState(() {});
  }

  bool _match(Map<String, dynamic> r, DateTime now) {
    final seen = DateTime.tryParse(r.str('seen'));
    final created = DateTime.tryParse(r.str('created'));
    final exp = DateTime.tryParse(r.str('exp'));
    final sub = Subs.of(r.str('id'), r.str('email'));
    final paid = (sub?.active ?? false) || (exp != null && exp.isAfter(now));
    switch (_f) {
      case 'today': return seen != null && now.difference(seen).inHours < 24;
      case 'week': return seen != null && now.difference(seen).inDays < 7;
      case 'new': return created != null && now.difference(created).inDays < 7;
      case 'paid': return paid;
      case 'free': return !paid && r.str('plan') != 'trial' && r.str('status') != 'banned';
      case 'trial': return r.str('plan') == 'trial';
      case 'banned': return r.str('status') == 'banned';
      case 'lost': return !paid && exp != null;                 // كان مشتركاً وانتهى
      case 'idle': return seen == null || now.difference(seen).inDays >= 30;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('قاعدة المستخدمين'), actions: [
      IconButton(
        tooltip: 'تصدير CSV',
        onPressed: UsersDb.rows.value.isEmpty ? null : () async {
          final now = DateTime.now();
          final list = UsersDb.rows.value.where((r) => _match(r, now)).toList();
          try {
            final p = await UsersDb.exportCsv(list);
            await Share.shareXFiles([XFile(p)], text: 'مستخدمو TOTV+ (${list.length})');
          } catch (e) { UI.err(e); }
        },
        icon: const Icon(Icons.ios_share_rounded)),
    ]),
    body: ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: UsersDb.rows,
      builder: (_, all, __) {
        final now = DateTime.now();
        final ql = _q.text.trim().toLowerCase();
        final list = all.where((r) => _match(r, now) && (ql.isEmpty ||
            [r.str('email'), r.str('name'), r.str('phone'), r.str('id'), r.str('user')].any((v) => v.toLowerCase().contains(ql)))).toList();
        int count(String f) { final o = _f; _f = f; final c = all.where((r) => _match(r, now)).length; _f = o; return c; }
        return ListView(padding: const EdgeInsets.all(16), children: [
          Box(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.storage_rounded, color: K.gold),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(all.isEmpty ? 'لا يوجد مستخدمون محفوظون' : '${Fmt.n(all.length)} مستخدم محفوظ على الهاتف', style: K.h3),
                Text(UsersDb.at == null ? 'اضغط «تحميل الكل» مرة واحدة' : 'آخر تحميل ${Fmt.ago(UsersDb.at)} · ${Fmt.dt(UsersDb.at)}', style: K.tiny),
              ])),
            ]),
            ValueListenableBuilder<int>(valueListenable: UsersDb.progress, builder: (_, p, __) => p < 0 ? const SizedBox(height: 12)
                : Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(children: [
                    const LinearProgressIndicator(color: K.gold),
                    const SizedBox(height: 6),
                    Text('جاري التحميل… ${Fmt.n(p)}', style: K.tiny),
                  ]))),
            Row(children: [
              Expanded(child: BusyButton(label: 'تحميل الكل', icon: Icons.cloud_download_rounded,
                  busy: UsersDb.busy, onPressed: () => _download(true))),
              const SizedBox(width: 8),
              Expanded(child: BusyButton(label: 'تحديث الجديد', icon: Icons.sync_rounded, color: K.blu,
                  busy: UsersDb.busy, onPressed: UsersDb.at == null ? null : () => _download(false))),
            ]),
            const SizedBox(height: 6),
            const Text('«تحديث الجديد» يقرأ فقط من فتح التطبيق منذ آخر تحميل — يوفّر حصة Firebase.', style: K.tiny, textAlign: TextAlign.center),
          ])),
          const SizedBox(height: 12),
          SearchBox(controller: _q, hint: 'بحث فوري: بريد، اسم، هاتف، UID، يوزر', onChanged: (_) => setState(() => _show = 80)),
          const SizedBox(height: 10),
          if (all.isNotEmpty) Filters<String>(value: _f, onChanged: (v) => setState(() { _f = v; _show = 80; }), items: [
            ('all', 'الكل', all.length), ('today', 'نشط اليوم', count('today')), ('week', 'نشط 7 أيام', count('week')),
            ('new', 'جدد 7 أيام', count('new')), ('paid', 'مشتركون', count('paid')), ('free', 'مجانيون', count('free')),
            ('lost', 'انتهى اشتراكهم', count('lost')), ('trial', 'تجريبي', count('trial')), ('idle', 'غائبون 30 يوماً', count('idle')),
            ('banned', 'محظورون', count('banned')),
          ]),
          const SizedBox(height: 10),
          if (all.isNotEmpty) Text('${Fmt.n(list.length)} نتيجة', style: K.sub),
          const SizedBox(height: 6),
          for (final r in list.take(_show)) _tile(r, now),
          if (list.length > _show) Padding(padding: const EdgeInsets.all(12), child: OutlinedButton(
              onPressed: () => setState(() => _show += 120), child: Text('عرض المزيد (${Fmt.n(list.length - _show)})'))),
          const SizedBox(height: 30),
        ]);
      },
    ),
  );

  Widget _tile(Map<String, dynamic> r, DateTime now) {
    final sub = Subs.of(r.str('id'), r.str('email'));
    final exp = sub?.expiry ?? DateTime.tryParse(r.str('exp'));
    final paid = exp != null && exp.isAfter(now);
    final seen = DateTime.tryParse(r.str('seen'));
    final name = r.str('name'), email = r.str('email');
    String label; Color c;
    if (r.str('status') == 'banned') { label = 'محظور'; c = K.red; }
    else if (paid) { final d = exp!.difference(now).inDays; label = '$d يوم'; c = d <= 3 ? K.red : (d <= 7 ? K.org : K.grn); }
    else if (exp != null) { label = 'منتهٍ'; c = K.t3; }
    else if (r.str('plan') == 'trial') { label = 'تجريبي'; c = K.cyn; }
    else { label = 'مجاني'; c = K.t3; }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Box(
        padding: const EdgeInsets.all(12),
        onTap: () => Nav.push(MemberPage(uid: r.str('id'), email: email)),
        child: Row(children: [
          Avatar(name.isEmpty ? email : name, size: 40),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? (email.isEmpty ? r.str('id') : email) : name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: K.body.copyWith(fontWeight: FontWeight.w800)),
            Text(email.isEmpty ? r.str('id') : email, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: K.tiny),
            Text([
              if (seen != null) 'آخر ظهور ${Fmt.ago(seen)}',
              if (r.str('phone').isNotEmpty) r.str('phone'),
              if (r.str('platform').isNotEmpty) '${r.str('platform')} ${r.str('ver')}',
            ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: K.tiny.copyWith(color: K.t2)),
          ])),
          Pill(label, color: c),
        ]),
      ),
    );
  }
}
