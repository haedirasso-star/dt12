part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  📣 إشعار فوري لكل المستخدمين — يظهر كأنه من تطبيق TOTV+
// ════════════════════════════════════════════════════════════════════
class NotifyPage extends StatefulWidget {
  final String? title, body, image, topic;
  const NotifyPage({super.key, this.title, this.body, this.image, this.topic});
  @override State<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends State<NotifyPage> {
  static const _kHist = 'notify_history_v2';
  late final _t = TextEditingController(text: widget.title ?? '');
  late final _b = TextEditingController(text: widget.body ?? '');
  late final _img = TextEditingController(text: widget.image ?? '');
  late String _topic = widget.topic ?? 'all_users';
  bool _busy = false, _ai = false;
  List<Map<String, dynamic>> _hist = [];

  static const _topics = {'all_users': 'جميع المستخدمين', 'matches': 'من فعّل إشعارات المباريات', 'admins': 'تجربة — المشرفين فقط'};
  static const _templates = [
    ('🔥 عرض لفترة محدودة', 'اشترك الآن واحصل على أفضل سعر — العرض ينتهي قريباً'),
    ('🎬 محتوى جديد', 'أضفنا أفلاماً ومسلسلات جديدة — شاهدها الآن على TOTV+'),
    ('⚽ مباراة الليلة', 'لا تفوّت مباراة الليلة — تابعها مباشرة على TOTV+'),
    ('🛠️ تحديث مهم', 'حدّث التطبيق للحصول على أفضل تجربة مشاهدة'),
  ];

  @override
  void initState() {
    super.initState();
    for (final c in [_t, _b, _img]) { c.addListener(() => setState(() {})); }
    _hist = (Prefs.getList(_kHist) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _aiWrite() async {
    final idea = await UI.input('ما فكرة الإشعار؟', hint: 'مثال: خصم 20% على الاشتراك السنوي حتى الجمعة', multiline: true, ok: 'اكتب لي');
    if (idea == null || idea.isEmpty) return;
    setState(() => _ai = true);
    try {
      final j = await AI.json('أنت كاتب إشعارات تسويقية لتطبيق بث عربي اسمه TOTV+. اكتب إشعاراً جذاباً قصيراً بالعربية لهذه الفكرة: $idea\n'
          'الشروط: عنوان ≤ 45 حرفاً يبدأ برمز تعبيري مناسب، ونص ≤ 120 حرفاً يدعو لفتح التطبيق. لا تخترع أسعاراً أو مواعيد غير مذكورة. '
          'أعد JSON فقط: {"title":"...","body":"..."}');
      if (j is Map) { _t.text = '${j['title'] ?? ''}'; _b.text = '${j['body'] ?? ''}'; }
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _ai = false);
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final t = _t.text.trim(), b = _b.text.trim(), img = _img.text.trim();
    if (t.isEmpty || b.isEmpty) { UI.toast('اكتب العنوان والنص', error: true); return; }
    if (img.isNotEmpty && !img.startsWith('https://')) { UI.toast('رابط الصورة يجب أن يبدأ بـ https://', error: true); return; }
    if (_topic != 'admins' && !await UI.confirm('إرسال إلى ${_topics[_topic]}؟', '«$t»\n$b', ok: 'إرسال الآن')) return;
    setState(() => _busy = true);
    try {
      final r = await PushApi.send({'action': 'broadcast', 'title': t, 'body': b, 'image': img, 'topic': _topic});
      if (r.ok) {
        HapticFeedback.heavyImpact();
        _hist.insert(0, {'t': t, 'b': b, 'img': img, 'to': _topic, 'at': DateTime.now().toIso8601String()});
        if (_hist.length > 40) _hist = _hist.take(40).toList();
        await Prefs.setJson(_kHist, _hist);
        _t.clear(); _b.clear(); _img.clear();
        UI.toast('تم الإرسال فوراً ✅');
      } else {
        UI.toast(PushApi.explain(r), error: true);
      }
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  Widget _preview() {
    final t = _t.text.trim().isEmpty ? 'عنوان الإشعار' : _t.text.trim();
    final b = _b.text.trim().isEmpty ? 'نص الإشعار يظهر هنا' : _b.text.trim();
    final img = _img.text.trim().startsWith('https://') ? _img.text.trim() : PushApi.icon;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF26262F), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 20, height: 20, alignment: Alignment.center, decoration: const BoxDecoration(color: K.gold, shape: BoxShape.circle),
              child: const Text('T', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w900))),
          const SizedBox(width: 6),
          const Text('TOTV+ • الآن', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 3),
            Text(b, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
          ])),
          const SizedBox(width: 10),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(img, width: 52, height: 52, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 52, height: 52, color: Colors.black, alignment: Alignment.center,
                  child: const Text('T', style: TextStyle(color: K.gold, fontSize: 26, fontWeight: FontWeight.w900))))),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إشعار فوري'), actions: [
      IconButton(tooltip: 'فحص النظام', onPressed: () => Nav.push(const SystemCheckPage()), icon: const Icon(Icons.health_and_safety_rounded)),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('معاينة على هاتف المستخدم', style: K.sub),
      const SizedBox(height: 8),
      _preview(),
      const SizedBox(height: 16),
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
        Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ActionChip(
          avatar: _ai ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: K.gold)) : const Icon(Icons.auto_awesome_rounded, size: 16, color: K.gold),
          label: const Text('اكتب بالذكاء الاصطناعي'), onPressed: _ai ? null : _aiWrite)),
        for (final (t, b) in _templates)
          Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ActionChip(label: Text(t), onPressed: () { _t.text = t; _b.text = b; })),
      ])),
      const SizedBox(height: 14),
      TextField(controller: _t, maxLength: 65, decoration: const InputDecoration(labelText: 'العنوان')),
      const SizedBox(height: 6),
      TextField(controller: _b, maxLength: 240, maxLines: 4, minLines: 3, decoration: const InputDecoration(labelText: 'نص الإشعار')),
      const SizedBox(height: 6),
      TextField(controller: _img, textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'رابط صورة (اختياري — الافتراضي أيقونة TOTV+)', hintText: 'https://')),
      const SizedBox(height: 14),
      const Text('المستلمون', style: K.h3),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _topics.entries)
          ChoiceChip(label: Text(e.value), selected: _topic == e.key, selectedColor: K.gold,
              labelStyle: TextStyle(fontWeight: FontWeight.w800, color: _topic == e.key ? Colors.black : K.t1),
              onSelected: (_) => setState(() => _topic = e.key)),
      ]),
      if (_hist.isNotEmpty) ...[
        const Section('آخر الإشعارات المرسلة'),
        for (final h in _hist) Padding(padding: const EdgeInsets.only(bottom: 8), child: Box(
          padding: const EdgeInsets.all(12),
          onTap: () => setState(() { _t.text = '${h['t']}'; _b.text = '${h['b']}'; _img.text = '${h['img'] ?? ''}'; }),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${h['t']}', style: K.body.copyWith(fontWeight: FontWeight.w800)),
              Text('${h['b']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: K.sub),
              Text('${_topics[h['to']] ?? h['to']} · ${Fmt.ago(DateTime.tryParse('${h['at']}'))}', style: K.tiny),
            ])),
            const Icon(Icons.replay_rounded, color: K.gold),
          ]),
        )),
      ],
      const SizedBox(height: 20),
    ]),
    bottomNavigationBar: BottomAction(child: BusyButton(label: 'إرسال الإشعار الآن', icon: Icons.send_rounded, busy: _busy, onPressed: _send)),
  );
}

// ════════════════════════════════════════════════════════════════════
//  ⚽ إشعارات المباريات — جدول «صافرة البداية» + كتابة بالذكاء الاصطناعي
// ════════════════════════════════════════════════════════════════════
class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});
  @override State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  String _feed = '';
  Map<String, dynamic> _m = {}, _state = {}, _status = {};
  bool _loading = true;
  String _err = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _err = ''; });
    try {
      final rc = await FirebaseFirestore.instance.collection('app_config').doc('remote_config').get();
      _feed = '${rc.data()?['sports_feed'] ?? ''}'.trim().replaceAll(RegExp(r'/+$'), '');
      if (_feed.isEmpty) throw Exception('لم يُضبط رابط خلاصة المباريات — المزيد ← التحكم بالتطبيق ← رابط خلاصة المباريات');
      final t = DateTime.now().millisecondsSinceEpoch;
      final r = await Future.wait([
        Net.req('GET', '$_feed/matches.json?r=$t'),
        Net.req('GET', '$_feed/state.json?r=$t'),
        Net.req('GET', '$_feed/status.json?r=$t'),
      ]);
      if (!r[0].ok || r[0].body is! Map) throw Exception('تعذّر قراءة matches.json (HTTP ${r[0].code})');
      _m = Map<String, dynamic>.from(r[0].body as Map);
      _state = r[1].body is Map ? Map<String, dynamic>.from(r[1].body as Map) : {};
      _status = r[2].body is Map ? Map<String, dynamic>.from(r[2].body as Map) : {};
    } catch (e) { _err = Fmt.err(e); }
    if (mounted) setState(() => _loading = false);
  }

  String _url(String p) => p.isEmpty ? '' : (p.startsWith('http') ? p : '$_feed/$p');

  @override
  Widget build(BuildContext context) {
    final leagues = _m.m('leagues');
    final notified = _state.m('notified');
    final now = DateTime.now();
    final matches = _m.l('matches').map((e) => Map<String, dynamic>.from(e as Map)).where((x) {
      final ts = DateTime.fromMillisecondsSinceEpoch(x.i('ts') * 1000);
      return ts.isAfter(now.subtract(const Duration(hours: 3)));
    }).toList()..sort((a, b) => a.i('ts').compareTo(b.i('ts')));
    final sentToday = (_state.m('notifyDay')['count'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('إشعارات المباريات'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading ? const Loading(text: 'جاري قراءة جدول المباريات…') : RefreshIndicator(color: K.gold, onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_err.isNotEmpty) ErrorBox(_err, onRetry: _load) else ...[
          Box(gradient: LinearGradient(colors: [K.grn.withOpacity(.14), K.card], begin: Alignment.topRight, end: Alignment.bottomLeft),
            border: K.grn.withOpacity(.3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.sports_rounded, color: K.grn), SizedBox(width: 8), Text('صافرة البداية — تلقائي', style: K.h3)]),
              const SizedBox(height: 6),
              const Text('عند انطلاق أي مباراة يُرسل إشعار حماسي يكتبه الذكاء الاصطناعي مع صورة المباراة وشعاري الفريقين — لمن فعّل إشعارات المباريات.', style: K.sub),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill('أُرسل اليوم: $sentToday', color: K.grn),
                if (_state['used'] != null) Pill('طلبات API اليوم: ${_state['used']}', color: K.blu),
                if (_m['updated'] != null) Pill('الخلاصة محدّثة ${Fmt.ago(DateTime.fromMillisecondsSinceEpoch(Fmt.numOf(_m['updated']) * 1000))}', color: K.t2),
                if ('${_state['lastError'] ?? _status['lastError'] ?? ''}'.isNotEmpty) const Pill('آخر تشغيل فيه خطأ', color: K.red),
              ]),
            ])),
          const SizedBox(height: 6),
          if (matches.isEmpty) const EmptyView(icon: Icons.sports_soccer_rounded, title: 'لا مباريات قادمة في البطولات المتابَعة'),
          ...() {
            final out = <Widget>[];
            String? lastDay;
            for (final x in matches) {
              final ts = DateTime.fromMillisecondsSinceEpoch(x.i('ts') * 1000);
              final day = '${ts.year}-${ts.month}-${ts.day}';
              if (day != lastDay) { lastDay = day; out.add(Section(Fmt.dayLabel(ts))); }
              out.add(_matchCard(x, leagues, notified.containsKey('${x['id']}'), ts));
            }
            return out;
          }(),
        ],
        const SizedBox(height: 20),
      ])),
    );
  }

  Widget _matchCard(Map<String, dynamic> x, Map<String, dynamic> leagues, bool sent, DateTime ts) {
    final h = x.m('h'), a = x.m('a');
    final lg = leagues.m('${x['lg']}');
    final started = ts.isBefore(DateTime.now());
    String n(Map<String, dynamic> t) => t.str('ar').isNotEmpty ? t.str('ar') : t.str('n');
    Widget team(Map<String, dynamic> t) => Expanded(child: Column(children: [
      SizedBox(width: 40, height: 40, child: t.str('logo').isEmpty ? const Icon(Icons.shield_rounded, color: K.t3)
          : Image.network(_url(t.str('logo')), errorBuilder: (_, __, ___) => const Icon(Icons.shield_rounded, color: K.t3))),
      const SizedBox(height: 6),
      Text(n(t), maxLines: 2, textAlign: TextAlign.center, style: K.body.copyWith(fontWeight: FontWeight.w800, fontSize: 13)),
    ]));
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Box(
      border: x['imp'] == true ? K.gold.withOpacity(.4) : null,
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(lg.str('ar'), style: K.tiny.copyWith(color: K.t2))),
          if (x['imp'] == true) const Pill('مهمة', color: K.gold, icon: Icons.star_rounded),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          team(h),
          Column(children: [
            Text(Fmt.time(ts), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: K.gold)),
            Text(started ? 'بدأت' : 'بعد ${Fmt.dur(ts.difference(DateTime.now()).inSeconds)}', style: K.tiny),
          ]),
          team(a),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Pill(sent ? 'أُرسل إشعار البداية ✓' : (started ? 'لم يُرسل' : 'سيُرسل تلقائياً عند البداية'),
              color: sent ? K.grn : (started ? K.t3 : K.blu), icon: sent ? Icons.notifications_active_rounded : Icons.schedule_rounded),
          const Spacer(),
          ActBtn(Icons.campaign_rounded, 'إشعار الآن', () => _compose(x, h, a, lg, ts), color: K.gold),
        ]),
      ]),
    ));
  }

  Future<void> _compose(Map<String, dynamic> x, Map<String, dynamic> h, Map<String, dynamic> a, Map<String, dynamic> lg, DateTime ts) async {
    String n(Map<String, dynamic> t) => t.str('ar').isNotEmpty ? t.str('ar') : t.str('n');
    final started = ts.isBefore(DateTime.now());
    var title = started ? '🔔 صافرة البداية! ${n(h)} × ${n(a)}' : '⚽ ${n(h)} × ${n(a)} الليلة';
    var body = started ? '${lg.str('ar')} — انطلقت المباراة الآن، تابعها مباشرة على TOTV+ ⚽🔥'
        : '${lg.str('ar')} — الساعة ${Fmt.time(ts)}، لا تفوّتها على TOTV+ 🔥';
    UI.toast('🤖 يكتب الذكاء الاصطناعي…');
    try {
      final j = await AI.json('أنت معلّق ومحرر إشعارات لتطبيق بث رياضي عربي اسمه TOTV+. '
          '${started ? 'صافرة البداية انطلقت للتو.' : 'المباراة تبدأ الساعة ${Fmt.time(ts)} بتوقيت بغداد.'} '
          'اكتب إشعاراً حماسياً قصيراً بروح المعلّق العربي.\nالمباراة: ${n(h)} ضد ${n(a)}\nالبطولة: ${lg.str('ar')}\nالملعب: ${x.str('venue')}\n'
          'الشروط: عنوان ≤ 45 حرفاً يبدأ برمز 🔔 أو ⚽ ويذكر الفريقين، ونص ≤ 110 أحرف يدعو للمشاهدة على TOTV+. '
          'ممنوع ذكر أي نتيجة أو أهداف أو أخبار غير مذكورة هنا. أعد JSON فقط: {"title":"...","body":"..."}');
      if (j is Map && '${j['title'] ?? ''}'.length >= 8) { title = '${j['title']}'; body = '${j['body'] ?? body}'; }
    } catch (e) { UI.toast('الذكاء الاصطناعي غير متاح — نص جاهز بدلاً منه', error: true); }
    final poster = _url(x.str('poster'));
    await Nav.push(NotifyPage(title: title, body: body, image: poster.startsWith('https://') ? poster : '', topic: 'matches'));
  }
}

// ════════════════════════════════════════════════════════════════════
//  🩺 فحص النظام — يبين بالضبط أين المشكلة وكيف تُحل
// ════════════════════════════════════════════════════════════════════
class SystemCheckPage extends StatefulWidget {
  const SystemCheckPage({super.key});
  @override State<SystemCheckPage> createState() => _SystemCheckPageState();
}

class _SystemCheckPageState extends State<SystemCheckPage> {
  bool _loading = true, _busy = false;
  bool? _fsOk, _supaOk;
  String _fsErr = '', _supaErr = '';
  NetResult? _h;

  @override
  void initState() { super.initState(); _run(); }

  Future<void> _run() async {
    setState(() => _loading = true);
    await AdminPush.ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('remote_control').get(const GetOptions(source: Source.server));
      _fsOk = true; _fsErr = '';
    } catch (e) { _fsOk = false; _fsErr = Fmt.err(e); }
    if (Supa.linked.value) {
      try { await Supa.call('admin_summary'); _supaOk = true; _supaErr = ''; } catch (e) { _supaOk = false; _supaErr = Fmt.err(e); }
    } else { _supaOk = false; _supaErr = 'غير مربوطة'; }
    try { _h = await PushApi.health(); } catch (_) { _h = NetResult(0, null, ''); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _test(String kind) async {
    setState(() => _busy = true);
    try {
      final r = await PushApi.send(kind == 'order'
          ? {'action': 'order', 'order_id': 'TEST', 'name': 'تجربة من تطبيق الإدارة', 'plan': 'شهر', 'price': '5,000', 'method': 'اختبار'}
          : {'action': 'broadcast', 'topic': 'admins', 'title': '✅ تجربة الإشعارات', 'body': 'إذا وصلك هذا فكل شيء يعمل'});
      UI.toast(r.ok ? 'أُرسل — يجب أن يصلك خلال ثوانٍ (أغلق التطبيق لترى إشعار النظام)' : PushApi.explain(r), error: !r.ok);
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  Widget _row(bool? ok, String title, String detail, {String? fix}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Box(
      border: ok == false ? K.red.withOpacity(.45) : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok == null ? Icons.help_outline_rounded : ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: ok == null ? K.t3 : ok ? K.grn : K.red, size: 26),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: K.h3.copyWith(fontSize: 14.5)),
          const SizedBox(height: 2),
          Text(detail, style: K.sub),
          if (ok == false && fix != null) ...[
            const SizedBox(height: 8),
            Container(width: double.infinity, padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: K.gold.withOpacity(.08), borderRadius: BorderRadius.circular(10)),
                child: Text(fix, style: K.sub.copyWith(color: K.t1))),
          ],
        ])),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final h = _h;
    final hj = h?.body is Map ? Map<String, dynamic>.from(h!.body as Map) : <String, dynamic>{};
    final fnOk = h?.code == 200;
    final log = CrashLog.read();
    final perm = AdminPush.permission;
    return Scaffold(
      appBar: AppBar(title: const Text('فحص النظام'), actions: [IconButton(onPressed: _loading ? null : _run, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading ? const Loading(text: 'جاري الفحص…') : ListView(padding: const EdgeInsets.all(16), children: [
        const Section('الاتصالات', padding: EdgeInsets.fromLTRB(2, 0, 2, 10)),
        _row(true, 'Firebase', 'الإعداد: ${Boot.mode} · ${FirebaseAuth.instance.currentUser?.email ?? ''}'),
        _row(_fsOk, 'قاعدة بيانات Firestore', _fsOk == true ? 'تعمل' : _fsErr, fix: 'تحقق من الإنترنت، ومن أن بريدك مشرف في قواعد Firestore.'),
        _row(_supaOk, 'قاعدة الاشتراكات (Supabase)', _supaOk == true ? 'مربوطة · ${Supa.email}' : _supaErr,
            fix: 'المزيد ← ربط قاعدة الاشتراكات، واكتب كلمة مرور حسابك فيها.'),
        const Section('استقبال إشعارات الطلبات على هذا الهاتف'),
        if (AdminPush.safeMode || AdminPush.token == null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: FilledButton.icon(
            onPressed: _busy ? null : () async { setState(() => _busy = true); await AdminPush.retry(); if (mounted) setState(() => _busy = false); _run(); },
            icon: const Icon(Icons.notifications_active_rounded), label: const Text('إعادة تفعيل الإشعارات'))),
        _row(perm == null ? null : perm == AuthorizationStatus.authorized || perm == AuthorizationStatus.provisional,
            'إذن الإشعارات', 'السماح للتطبيق بعرض الإشعارات', fix: 'الإعدادات ← التطبيقات ← TOTV+ Admin ← الإشعارات ← تفعيل'),
        _row(AdminPush.token != null, 'تسجيل الهاتف في FCM', AdminPush.token != null ? 'مسجّل' : (AdminPush.error.isEmpty ? 'غير مسجّل' : AdminPush.error),
            fix: 'تحقق من الإنترنت ثم «إعادة تفعيل الإشعارات». إن استمر: أضف تطبيق com.totv.admin في Firebase وضع google-services.json.'),
        _row(AdminPush.subscribed, 'قناة «طلبات الاشتراك»', 'الهاتف مشترك في إشعارات الطلبات'),
        _row(true, 'الطلبات المباشرة داخل التطبيق', 'تصل فوراً بصوت الكاش ما دام التطبيق مفتوحاً أو في الخلفية'),
        const Section('دالة الإرسال (Supabase «push»)'),
        _row(fnOk, 'الدالة منشورة', h == null || h.code == 0 ? 'لا اتصال' : (fnOk ? 'تعمل' : 'الرد: ${h.code}'),
            fix: 'الدالة غير منشورة: في GitHub أضف 3 أسرار (SUPABASE_ACCESS_TOKEN و FCM_SERVICE_ACCOUNT و ADMIN_EMAILS) ثم Actions ← «Supabase — Deploy push function» ← Run workflow.'),
        _row(fnOk ? hj['fcm'] == true : null, 'مفتاح Firebase في الدالة', fnOk ? (hj['fcm'] == true ? 'مضبوط (${hj['project'] ?? ''})' : 'غير مضبوط') : '—',
            fix: 'أضف سرّ FCM_SERVICE_ACCOUNT = محتوى ملف JSON من Firebase ← Service accounts ← Generate new private key.'),
        _row(fnOk ? Fmt.numOf(hj['admins']) > 0 : null, 'بريد المشرف', fnOk ? 'عدد البريدات المسموحة: ${hj['admins'] ?? 0}' : '—',
            fix: 'أضف سرّ ADMIN_EMAILS = بريدك.'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => AdminPush.show('🔔 تجربة محلية', 'هذا صوت وشكل إشعار الطلبات'),
              icon: const Icon(Icons.volume_up_rounded), label: const Text('تجربة الصوت'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _test('order'), icon: const Icon(Icons.receipt_long_rounded), label: const Text('إشعار طلب'))),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _busy ? null : () => _test('broadcast'), icon: const Icon(Icons.campaign_rounded), label: const Text('إشعار للمشرفين فقط')),
        if (log.isNotEmpty) ...[
          Section('سجل الأخطاء (${log.length})', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.copy_rounded, size: 20), onPressed: () => UI.copy(log.join('\n'), label: 'نُسخ السجل')),
            IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20), onPressed: () async { await CrashLog.clear(); setState(() {}); }),
          ])),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(log.join('\n\n'), textDirection: TextDirection.ltr, style: K.mono.copyWith(fontSize: 11, color: K.t2))),
        ],
        const SizedBox(height: 30),
      ]),
    );
  }
}
