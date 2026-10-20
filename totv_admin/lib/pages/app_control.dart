part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🎛 التحكم بالتطبيق — يتغير عند كل المستخدمين فوراً (app_config)
// ════════════════════════════════════════════════════════════════════
class AppControlPage extends StatefulWidget {
  const AppControlPage({super.key});
  @override State<AppControlPage> createState() => _AppControlPageState();
}

class _AppControlPageState extends State<AppControlPage> {
  final _cfg = FirebaseFirestore.instance.collection('app_config');
  Map<String, Map<String, dynamic>> _d = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait(['remote_control', 'remote_config', 'version', 'settings'].map((k) => _cfg.doc(k).get()));
      _d = {for (final s in r) s.id: s.data() ?? {}};
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _loading = false);
  }

  dynamic _v(String doc, String k) => _d[doc]?[k];

  Future<void> _save(String doc, String k, dynamic v) async {
    try {
      await _cfg.doc(doc).set({k: v, 'updated_at': FieldValue.serverTimestamp(), 'updated_by': Store.by}, SetOptions(merge: true));
      (_d[doc] ??= {})[k] = v;
      if (doc == 'version') {
        final h = Map<String, dynamic>.from(_d['version']!)..remove('updated_at');
        unawaited(FirebaseFirestore.instance.collection('version_history')
            .add({...h, 'logged_at': FieldValue.serverTimestamp(), 'updated_by': Store.by}).then((_) {}, onError: (_) {}));
      }
      setState(() {});
      UI.toast('حُفظ — يصل لكل المستخدمين فوراً');
    } catch (e) { UI.err(e); }
  }

  Future<void> _edit(String doc, String k, String label, {bool number = false, String? help, bool secret = false}) async {
    final cur = _v(doc, k);
    final v = await UI.input(label, initial: cur == null ? '' : '$cur', number: number, help: help);
    if (v == null) return;
    await _save(doc, k, number ? (int.tryParse(v) ?? 0) : v);
  }

  Widget _row(String doc, String k, String label, IconData icon, {bool number = false, String? help, bool secret = false}) {
    final v = _v(doc, k);
    final s = v == null || '$v'.isEmpty ? 'غير مضبوط' : (secret ? '•••• ${'$v'.length > 4 ? '$v'.substring('$v'.length - 4) : ''}' : '$v');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Icon(icon, color: K.gold),
      title: Text(label, style: K.body.copyWith(fontWeight: FontWeight.w800)),
      subtitle: Text(s, maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr,
          textAlign: TextAlign.right, style: K.sub.copyWith(color: v == null || '$v'.isEmpty ? K.t3 : K.t2)),
      trailing: const Icon(Icons.edit_rounded, size: 18, color: K.t3),
      onTap: () => _edit(doc, k, label, number: number, help: help, secret: secret),
    );
  }

  Widget _toggle(String k, String title, String on, String off, IconData icon) {
    final v = _v('remote_control', k) == true;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: SwitchRow(
      title: title, sub: v ? on : off, value: v, icon: icon, color: K.red,
      onChanged: (x) async {
        if (!await UI.confirm(x ? 'تفعيل «$title»؟' : 'إيقاف «$title»؟', 'يتغير عند كل المستخدمين فوراً.', danger: x)) return;
        await _save('remote_control', k, x);
      }));
  }

  Widget _group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(title, style: K.h3)),
      Box(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: children)),
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('التحكم بالتطبيق'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
    body: _loading ? const Loading() : ListView(padding: const EdgeInsets.all(16), children: [
      _group('🎮 مفاتيح النظام', [
        _toggle('maintenance', 'وضع الصيانة', 'التطبيق تحت الصيانة الآن', 'التطبيق يعمل طبيعياً', Icons.construction_rounded),
        _toggle('locked', 'قفل التطبيق', 'التطبيق مقفول', 'التطبيق مفتوح', Icons.lock_rounded),
        _toggle('guest_only', 'وضع الضيوف فقط', 'الدخول كضيف فقط', 'الكل يسجل دخول', Icons.person_outline_rounded),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: SwitchRow(
          title: 'المشغّل الاحترافي الجديد',
          sub: _v('remote_control', 'player_engine') == 'legacy'
              ? 'مُوقف — المستخدمون على المشغّل القديم'
              : 'يعمل — أوقفه فقط إن ظهرت مشكلة تشغيل عامة',
          icon: Icons.smart_display_rounded, color: K.grn,
          value: _v('remote_control', 'player_engine') != 'legacy',
          onChanged: (x) async {
            if (!await UI.confirm(x ? 'تشغيل المشغّل الجديد؟' : 'الرجوع للمشغّل القديم؟',
                'يتغير عند كل المستخدمين فوراً (من الفتح التالي للمشغّل).')) return;
            await _save('remote_control', 'player_engine', x ? 'pro' : 'legacy');
          })),
        const Divider(),
        _row('remote_control', 'maint_msg', 'رسالة الصيانة', Icons.message_rounded),
        _row('remote_control', 'lock_msg', 'رسالة القفل', Icons.message_outlined),
      ]),
      _group('🌐 الاتصال بالسيرفر', [
        _row('remote_config', 'server_host', 'السيرفر الرئيسي', Icons.dns_rounded),
        _row('remote_config', 'default_server_host', 'السيرفر الافتراضي (التجريبي)', Icons.dns_outlined),
        _row('remote_config', 'username', 'يوزر الافتراضي', Icons.person_rounded),
        _row('remote_config', 'password', 'باسوورد الافتراضي', Icons.key_rounded),
      ]),
      _group('💬 الدعم والاشتراك', [
        _row('remote_config', 'whatsapp', 'رقم واتساب', Icons.chat_rounded, help: 'بالصيغة الدولية بدون + مثل 9647714415816'),
        _row('remote_config', 'telegram', 'رابط تلجرام', Icons.send_rounded),
        _row('remote_config', 'buy_url', 'رابط الشراء', Icons.shopping_cart_rounded),
        _row('remote_config', 'sports_feed', 'رابط خلاصة المباريات', Icons.sports_soccer_rounded,
            help: 'رابط GitHub Pages لمستودع totv-sports مثل https://user.github.io/totv-sports'),
      ]),
      _group('🚀 الإصدار والتحديث', [
        _row('version', 'current_version', 'الإصدار الحالي', Icons.new_releases_rounded),
        _row('version', 'min_version', 'الحد الأدنى (رقم البناء)', Icons.low_priority_rounded, number: true,
            help: 'أي نسخة أقل من هذا الرقم يُطلب منها التحديث'),
        _row('version', 'store_url', 'رابط التحديث', Icons.link_rounded),
        _row('version', 'update_msg', 'رسالة التحديث', Icons.message_rounded),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: SwitchRow(
          title: 'تحديث إجباري', sub: 'يمنع استخدام النسخ القديمة', icon: Icons.system_update_rounded, color: K.org,
          value: _v('version', 'force_update') == true,
          onChanged: (x) => _save('version', 'force_update', x))),
        ListTile(
          leading: const Icon(Icons.history_rounded, color: K.t2),
          title: const Text('سجل الإصدارات', style: TextStyle(fontWeight: FontWeight.w800)),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => Nav.push(const VersionHistoryPage()),
        ),
      ]),
      _group('🔑 المفاتيح', [
        _row('settings', 'ai_key', 'مفتاح Gemini (الذكاء الاصطناعي)', Icons.auto_awesome_rounded, secret: true,
            help: 'من aistudio.google.com ← Get API key. يُستخدم لكتابة إشعارات المباريات وقراءة صور الحسابات.'),
        _row('settings', 'tmdb_key', 'مفتاح TMDB', Icons.movie_rounded, secret: true),
      ]),
    ]),
  );
}

class VersionHistoryPage extends StatelessWidget {
  const VersionHistoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('سجل الإصدارات')),
    body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('version_history').orderBy('logged_at', descending: true).limit(20).get(),
      builder: (_, s) {
        if (s.hasError) return Padding(padding: const EdgeInsets.all(16), child: ErrorBox(Fmt.err(s.error!)));
        if (!s.hasData) return const Loading();
        if (s.data!.docs.isEmpty) return const EmptyView(title: 'لا سجل بعد');
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final d in s.data!.docs) Padding(padding: const EdgeInsets.only(bottom: 8), child: Box(padding: const EdgeInsets.all(14), child: Row(children: [
            Text('${d.data()['current_version'] ?? '—'}', style: K.mono.copyWith(color: K.gold, fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            Pill(d.data()['force_update'] == true ? 'إجباري' : 'اختياري', color: d.data()['force_update'] == true ? K.red : K.grn),
            const Spacer(),
            Text(Fmt.dt(Fmt.toDate(d.data()['logged_at'])), style: K.tiny),
          ]))),
        ]);
      },
    ),
  );
}

// ════════════════════════════════════════════════════════════════════
//  💳 طرق الدفع — الأرقام والأسماء التي تظهر للمستخدم عند الاشتراك
// ════════════════════════════════════════════════════════════════════
class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});
  @override State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  static const _methods = [
    ('fib', 'FIB — مصرف العراق الأول', '07714415816', 'حيدر عصام', Color(0xFF00C9A7)),
    ('zain', 'Zain Cash — زين كاش', '07714415816', '', Color(0xFFE5E5E5)),
    ('qi', 'Qi Card — كي كارد', '7065169257', 'حيدر عصام', Color(0xFFFFD800)),
  ];
  static const _plans = [('monthly', 'شهري', 5000), ('quarterly', '3 أشهر', 13000), ('yearly', 'سنوي', 45000)];
  final _doc = FirebaseFirestore.instance.collection('app_config').doc('payment_numbers');
  final _plansDoc = FirebaseFirestore.instance.collection('app_config').doc('plans');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طرق الدفع والأسعار')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _doc.snapshots(),
      builder: (_, s) {
        final d = s.data?.data() ?? {};
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Banner2('هذه الأرقام تظهر للمستخدم في خطوة «التحويل» عند الاشتراك. أي تغيير يصل للتطبيق فوراً.', icon: Icons.info_rounded),
          const Section('أرقام التحويل'),
          for (final (id, label, defNum, defName, color) in _methods) () {
            final m = d[id] is Map ? Map<String, dynamic>.from(d[id] as Map) : <String, dynamic>{};
            final number = m.str('number').isNotEmpty ? m.str('number') : defNum;
            final name = m.str('name').isNotEmpty ? m.str('name') : defName;
            final custom = m.str('number').isNotEmpty || m.str('name').isNotEmpty;
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Box(
              gradient: LinearGradient(colors: [color.withOpacity(.12), K.card], begin: Alignment.topRight, end: Alignment.bottomLeft),
              border: color.withOpacity(.3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: K.h3)),
                  Pill(custom ? 'مخصص' : 'افتراضي', color: custom ? K.gold : K.t3),
                ]),
                const SizedBox(height: 10),
                InfoRow('الرقم', number, copy: true, ltr: true, color: K.gold2),
                InfoRow('الاسم', name.isEmpty ? '—' : name),
                const SizedBox(height: 6),
                Row(children: [
                  ActBtn(Icons.edit_rounded, 'تغيير الرقم', () async {
                    final v = await UI.input('رقم $label', initial: number, number: true);
                    if (v != null && v.isNotEmpty) await _set(id, {'number': v, 'name': name});
                  }),
                  const SizedBox(width: 8),
                  ActBtn(Icons.badge_rounded, 'تغيير الاسم', () async {
                    final v = await UI.input('اسم صاحب الحساب', initial: name);
                    if (v != null) await _set(id, {'number': number, 'name': v});
                  }),
                ]),
              ]),
            ));
          }(),
          const Section('أسعار الباقات', sub: 'تُحفظ في app_config/plans — تظهر في التطبيق بعد تحديثه القادم'),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _plansDoc.snapshots(),
            builder: (_, ps) {
              final p = ps.data?.data() ?? {};
              return Box(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: [
                for (final (id, t, def) in _plans) () {
                  final m = p[id] is Map ? Map<String, dynamic>.from(p[id] as Map) : <String, dynamic>{};
                  final price = m.i('price_num') > 0 ? m.i('price_num') : def;
                  return ListTile(
                    leading: const Icon(Icons.sell_rounded, color: K.gold),
                    title: Text(t, style: K.body.copyWith(fontWeight: FontWeight.w800)),
                    subtitle: Text('${Fmt.n(price)} د.ع', style: K.sub.copyWith(color: K.gold2)),
                    trailing: const Icon(Icons.edit_rounded, size: 18, color: K.t3),
                    onTap: () async {
                      final v = await UI.input('سعر $t (د.ع)', initial: '$price', number: true);
                      final n = int.tryParse(v ?? '');
                      if (n == null || n <= 0) return;
                      try {
                        await _plansDoc.set({id: {'price_num': n, 'price': Fmt.n(n)}, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                        UI.toast('حُفظ السعر');
                      } catch (e) { UI.err(e); }
                    },
                  );
                }(),
              ]));
            },
          ),
        ]);
      },
    ),
  );

  Future<void> _set(String id, Map<String, String> v) async {
    try {
      await _doc.set({id: v, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      UI.toast('حُفظ — يظهر للمستخدمين فوراً');
    } catch (e) { UI.err(e); }
  }
}

// ════════════════════════════════════════════════════════════════════
//  🖥 السيرفرات
// ════════════════════════════════════════════════════════════════════
class ServersPage extends StatefulWidget {
  const ServersPage({super.key});
  @override State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  final _col = FirebaseFirestore.instance.collection('servers');
  final Map<String, (bool, int)> _ping = {};
  final Set<String> _pinging = {};

  Future<void> _pingOne(String id, Map<String, dynamic> x) async {
    setState(() => _pinging.add(id));
    final sw = Stopwatch()..start();
    var ok = false;
    try {
      final host = x.str('host').replaceAll(RegExp(r'/+$'), '');
      final r = await Net.req('GET', '$host/player_api.php?username=${Uri.encodeQueryComponent(x.str('username'))}&password=${Uri.encodeQueryComponent(x.str('password'))}',
          timeout: const Duration(seconds: 10));
      ok = r.code > 0 && r.code < 500;
    } catch (_) {}
    sw.stop();
    if (mounted) setState(() { _pinging.remove(id); _ping[id] = (ok, sw.elapsedMilliseconds); });
  }

  Future<void> _add() async {
    final name = TextEditingController(), host = TextEditingController(), user = TextEditingController(), pass = TextEditingController(), pri = TextEditingController(text: '1');
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (s) => Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.of(s).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('إضافة سيرفر', style: K.h2),
        const SizedBox(height: 14),
        InField(name, 'الاسم', icon: Icons.label_rounded),
        InField(host, 'Host', ltr: true, icon: Icons.dns_rounded),
        InField(user, 'Username', ltr: true, icon: Icons.person_rounded),
        InField(pass, 'Password', ltr: true, icon: Icons.key_rounded),
        InField(pri, 'الأولوية (1 = الأعلى)', number: true, icon: Icons.low_priority_rounded),
        FilledButton(onPressed: () => Navigator.pop(s, true), child: const Text('إضافة')),
      ])),
    ));
    if (ok != true) return;
    if (host.text.trim().isEmpty || user.text.trim().isEmpty) { UI.toast('الرابط والمستخدم مطلوبان', error: true); return; }
    try {
      await _col.add({'name': name.text.trim(), 'host': host.text.trim(), 'username': user.text.trim(), 'password': pass.text.trim(),
        'priority': int.tryParse(pri.text) ?? 1, 'active': true, 'created_at': FieldValue.serverTimestamp()});
      UI.toast('أُضيف السيرفر');
    } catch (e) { UI.err(e); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('السيرفرات')),
    floatingActionButton: FloatingActionButton(backgroundColor: K.gold, foregroundColor: Colors.black, onPressed: _add, child: const Icon(Icons.add_rounded)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _col.orderBy('priority').snapshots(),
      builder: (_, s) {
        if (s.hasError) return Padding(padding: const EdgeInsets.all(16), child: ErrorBox(Fmt.err(s.error!)));
        if (!s.hasData) return const Loading();
        final docs = s.data!.docs;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(child: Text('${docs.where((d) => d.data()['active'] != false).length} فعّال من ${docs.length}', style: K.sub)),
            ActBtn(Icons.network_ping_rounded, 'فحص الكل', () { for (final d in docs) { _pingOne(d.id, d.data()); } }, color: K.blu),
          ]),
          const SizedBox(height: 12),
          if (docs.isEmpty) const EmptyView(icon: Icons.dns_rounded, title: 'لا سيرفرات'),
          for (final d in docs) () {
            final x = d.data();
            final a = x['active'] != false;
            final p = _ping[d.id];
            final c = p == null ? K.t3 : (!p.$1 ? K.red : (p.$2 < 500 ? K.grn : (p.$2 < 2000 ? K.gold : K.red)));
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Box(
              border: a ? K.grn.withOpacity(.2) : K.red.withOpacity(.2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.str('name').isEmpty ? d.id : x.str('name'), style: K.h3),
                    Text(x.str('host'), textDirection: TextDirection.ltr, style: K.tiny),
                  ])),
                  Text(_pinging.contains(d.id) ? '…' : (p == null ? 'P${x['priority'] ?? 99}' : (p.$1 ? '${p.$2}ms' : 'لا يستجيب')),
                      style: K.mono.copyWith(color: c, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ActBtn(Icons.network_ping_rounded, 'فحص', () => _pingOne(d.id, x), color: K.blu),
                  ActBtn(a ? Icons.pause_rounded : Icons.play_arrow_rounded, a ? 'إيقاف' : 'تفعيل', () async {
                    try { await _col.doc(d.id).update({'active': !a}); } catch (e) { UI.err(e); }
                  }, color: a ? K.org : K.grn),
                  ActBtn(Icons.copy_rounded, 'نسخ', () => UI.copy('${x.str('host')}\n${x.str('username')}\n${x.str('password')}')),
                  ActBtn(Icons.delete_rounded, 'حذف', () async {
                    if (!await UI.confirm('حذف السيرفر؟', x.str('host'), danger: true, ok: 'حذف')) return;
                    try { await _col.doc(d.id).delete(); } catch (e) { UI.err(e); }
                  }, color: K.red),
                ]),
              ]),
            ));
          }(),
        ]);
      },
    ),
  );
}
