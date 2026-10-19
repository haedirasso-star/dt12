part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🔑 أكواد التفعيل — توليد · بحث · إيقاف · إعادة تعيين · حذف
// ════════════════════════════════════════════════════════════════════
String prettyCode(String c) {
  final s = c.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (s.length == 12 && s.startsWith('TOTV')) return 'TOTV-${s.substring(4, 8)}-${s.substring(8)}';
  return s;
}

class CodesPage extends StatefulWidget {
  const CodesPage({super.key});
  @override State<CodesPage> createState() => _CodesPageState();
}

class _CodesPageState extends State<CodesPage> {
  List<Map<String, dynamic>> _codes = [];
  Map<String, dynamic> _st = {};
  DateTime? _at;
  bool _busy = false;
  String _f = 'unused';
  final _q = TextEditingController();

  @override
  void initState() { super.initState(); _cached(); }

  Future<void> _cached() async {
    final c = await DiskCache.read('codes');
    if (c is Map) {
      final m = Map<String, dynamic>.from(c);
      _codes = m.l('codes').map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _st = m.m('stats');
      _at = await DiskCache.time('codes');
      if (mounted) setState(() {});
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await Supa.call('admin_list_codes', {'p_limit': 1000});
      _codes = r.l('codes').map((e) => Map<String, dynamic>.from(e as Map)).toList();
      try { _st = await Supa.call('admin_stats'); } catch (_) {}
      _at = DateTime.now();
      await DiskCache.write('codes', {'codes': _codes, 'stats': _st});
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  bool _disabled(Map<String, dynamic> c) => c['disabled'] == true || c.str('status') == 'disabled';
  bool _used(Map<String, dynamic> c) => c['used'] == true;

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase().replaceAll('-', '');
    final list = _codes.where((c) {
      switch (_f) {
        case 'unused': if (_used(c) || _disabled(c)) return false; break;
        case 'used': if (!_used(c)) return false; break;
        case 'disabled': if (!_disabled(c)) return false; break;
      }
      if (q.isEmpty) return true;
      return [c.str('code'), c.str('username'), c.str('host'), c.str('used_by_email'), c.str('agent'), c.str('note')]
          .any((v) => v.toLowerCase().contains(q));
    }).toList();
    final unused = _codes.where((c) => !_used(c) && !_disabled(c)).length;
    final used = _codes.where(_used).length;
    final dis = _codes.where(_disabled).length;
    return Scaffold(
      appBar: AppBar(title: const Text('أكواد التفعيل'), actions: [
        IconButton(onPressed: _busy ? null : _load, icon: _busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: K.gold))
            : const Icon(Icons.refresh_rounded)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K.gold, foregroundColor: Colors.black,
        onPressed: () async { final ok = await Nav.push<bool>(const GenerateCodesPage()); if (ok == true) _load(); },
        icon: const Icon(Icons.add_rounded), label: const Text('توليد أكواد', style: TextStyle(fontWeight: FontWeight.w900))),
      body: RefreshIndicator(color: K.gold, onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_at != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('محدَّث ${Fmt.ago(_at)}', style: K.tiny)),
        KpiGrid(columns: 3, children: [
          Kpi(label: 'متاح للبيع', value: Fmt.n(_st['codes_unused'] as num? ?? unused), icon: Icons.sell_rounded, color: K.grn, onTap: () => setState(() => _f = 'unused')),
          Kpi(label: 'مستخدم', value: Fmt.n(_st['codes_used'] as num? ?? used), icon: Icons.how_to_reg_rounded, color: K.blu, onTap: () => setState(() => _f = 'used')),
          Kpi(label: 'الإجمالي', value: Fmt.n(_st['codes_total'] as num? ?? _codes.length), icon: Icons.key_rounded, color: K.gold, onTap: () => setState(() => _f = 'all')),
        ]),
        SearchBox(controller: _q, hint: 'بحث بالكود أو اليوزر أو بريد المستخدم', onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        Filters<String>(value: _f, onChanged: (v) => setState(() => _f = v), items: [
          ('unused', 'متاح', unused), ('used', 'مستخدم', used), ('disabled', 'موقوف', dis), ('all', 'الكل', _codes.length),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty) EmptyView(icon: Icons.key_off_rounded, title: _codes.isEmpty ? 'لا أكواد بعد' : 'لا نتائج')
        else ...list.take(300).map(_tile),
        const SizedBox(height: 80),
      ])),
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final used = _used(c), dis = _disabled(c);
    final exp = c.d('expiry_date');
    final d = Fmt.daysLeft(exp);
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Box(
      padding: const EdgeInsets.all(12),
      onTap: () => _detail(c),
      child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: (dis ? K.t3 : used ? K.blu : K.grn).withOpacity(.14), borderRadius: BorderRadius.circular(12)),
            child: Icon(dis ? Icons.pause_rounded : used ? Icons.person_rounded : Icons.key_rounded, color: dis ? K.t3 : used ? K.blu : K.grn)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(prettyCode(c.str('code')), textDirection: TextDirection.ltr, style: K.mono.copyWith(fontWeight: FontWeight.w900, color: K.gold)),
          Text(used ? (c.str('used_by_email').isEmpty ? 'مستخدم' : c.str('used_by_email')) : '${Fmt.plan(c.str('plan'))} · ${c.i('days')} يوم · ${c.str('username')}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: K.tiny),
        ])),
        if (used && d != null) Pill(d > 0 ? '$d يوم' : 'منتهي', color: d > 0 ? K.grn : K.red)
        else if (dis) const Pill('موقوف', color: K.t3)
        else IconButton(icon: const Icon(Icons.copy_rounded, size: 20, color: K.t2), onPressed: () => UI.copy(prettyCode(c.str('code')))),
      ]),
    ));
  }

  Future<void> _detail(Map<String, dynamic> c) async {
    final code = c.str('code');
    final used = _used(c), dis = _disabled(c);
    final a = await UI.pick<String>(prettyCode(code), [
      ('copy', 'نسخ الكود', Icons.copy_rounded),
      ('share', 'مشاركة الكود مع رسالة', Icons.share_rounded),
      ('info', 'التفاصيل', Icons.info_rounded),
      (dis ? 'enable' : 'disable', dis ? 'تشغيل الكود' : 'إيقاف الكود', dis ? Icons.play_arrow_rounded : Icons.pause_rounded),
      if (used) ('release', 'إعادة تعيين (يفقد المشترك اشتراكه)', Icons.restart_alt_rounded),
      ('delete', 'حذف نهائي', Icons.delete_rounded),
    ]);
    if (a == null) return;
    if (a == 'copy') { await UI.copy(prettyCode(code)); return; }
    if (a == 'share') {
      await Share.share('🎟 كود اشتراك TOTV+\n${prettyCode(code)}\nالمدة: ${c.i('days')} يوم\nافتح التطبيق ← المزيد ← تفعيل بكود');
      return;
    }
    if (a == 'info') {
      await UI.sheet(ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), children: [
        Text(prettyCode(code), style: K.h2.copyWith(color: K.gold)),
        const SizedBox(height: 12),
        Box(child: Column(children: [
          InfoRow('الحالة', dis ? 'موقوف' : (used ? 'مستخدم' : 'متاح')),
          InfoRow('الباقة', '${Fmt.plan(c.str('plan'))} · ${c.i('days')} يوم'),
          InfoRow('Host', c.str('host'), copy: true, ltr: true),
          InfoRow('Username', c.str('username'), copy: true, ltr: true),
          InfoRow('Password', c.str('password'), copy: true, ltr: true),
          if (used) InfoRow('المستخدم', c.str('used_by_email'), copy: true, ltr: true),
          if (used) InfoRow('استُخدم', Fmt.dt(c.d('used_at'))),
          if (used) InfoRow('ينتهي', Fmt.dt(c.d('expiry_date'))),
          if (c.str('agent').isNotEmpty) InfoRow('الوكيل', c.str('agent')),
          if (c.str('note').isNotEmpty) InfoRow('ملاحظة', c.str('note')),
          InfoRow('أُنشئ', Fmt.dt(c.d('created_at'))),
        ])),
        if (used && c.str('used_by_uid').isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () { Navigator.pop(context); Nav.push(MemberPage(uid: c.str('used_by_uid'), email: c.str('used_by_email'))); },
              icon: const Icon(Icons.person_rounded), label: const Text('ملف المشترك')),
        ],
      ]), initial: .7);
      return;
    }
    if (a == 'release' && !await UI.confirm('إعادة تعيين الكود؟', 'سيصبح متاحاً من جديد وسيفقد المشترك الحالي اشتراكه.', danger: true)) return;
    if (a == 'delete' && !await UI.confirm('حذف الكود نهائياً؟', prettyCode(code), danger: true, ok: 'حذف')) return;
    try {
      await Supa.call('admin_set_code_state', {'p_code': code, 'p_action': a});
      UI.toast({'enable': 'تم التشغيل', 'disable': 'تم الإيقاف', 'release': 'أُعيد التعيين', 'delete': 'حُذف'}[a] ?? 'تم');
      _load();
    } catch (e) { UI.err(e); }
  }
}

// ════════════════════════════════════════════════════════════════════
//  توليد أكواد
// ════════════════════════════════════════════════════════════════════
class GenerateCodesPage extends StatefulWidget {
  const GenerateCodesPage({super.key});
  @override State<GenerateCodesPage> createState() => _GenerateCodesPageState();
}

class _GenerateCodesPageState extends State<GenerateCodesPage> {
  final _host = TextEditingController(), _user = TextEditingController(), _pass = TextEditingController();
  final _days = TextEditingController(text: '30'), _count = TextEditingController(text: '2');
  final _agent = TextEditingController(), _note = TextEditingController();
  String _plan = 'monthly';
  bool _busy = false;
  List<String> _out = [];

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('app_config').doc('remote_config').get().then((d) {
      final h = '${d.data()?['server_host'] ?? ''}';
      if (_host.text.isEmpty && h.isNotEmpty && mounted) setState(() => _host.text = h);
    }).catchError((_) {});
  }

  Future<void> _gen() async {
    final host = _host.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (host.isEmpty || _user.text.trim().isEmpty || _pass.text.trim().isEmpty) { UI.toast('أكمل Host و Username و Password', error: true); return; }
    final count = (int.tryParse(_count.text) ?? 2).clamp(1, 100);
    setState(() => _busy = true);
    try {
      final r = await Supa.call('admin_generate_codes', {
        'p_host': host, 'p_user': _user.text.trim(), 'p_pass': _pass.text.trim(), 'p_plan': _plan,
        'p_days': int.tryParse(_days.text) ?? kPlanDays[_plan] ?? 30, 'p_count': count,
        'p_agent': _agent.text.trim(), 'p_note': _note.text.trim()});
      setState(() => _out = r.l('codes').map((e) => prettyCode('$e')).toList());
      HapticFeedback.heavyImpact();
      UI.toast('تم توليد ${_out.length} كود');
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('توليد أكواد')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_out.isNotEmpty) ...[
        Box(color: K.grn.withOpacity(.08), border: K.grn.withOpacity(.35), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('✅ ${_out.length} كود جاهز للبيع', style: K.h3),
          const SizedBox(height: 10),
          for (final c in _out) InkWell(onTap: () => UI.copy(c), child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
            Text(c, textDirection: TextDirection.ltr, style: K.mono.copyWith(fontSize: 16, fontWeight: FontWeight.w900, color: K.gold)),
            const Spacer(),
            const Icon(Icons.copy_rounded, size: 18, color: K.t3),
          ]))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => UI.copy(_out.join('\n'), label: 'نُسخت كل الأكواد'), icon: const Icon(Icons.copy_all_rounded), label: const Text('نسخ الكل'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => Share.share(_out.join('\n')), icon: const Icon(Icons.share_rounded), label: const Text('مشاركة'))),
          ]),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('تم')),
        ])),
        const SizedBox(height: 16),
      ],
      const Text('بيانات السيرفر', style: K.h3),
      const SizedBox(height: 8),
      InField(_host, 'Host', ltr: true, icon: Icons.dns_rounded),
      InField(_user, 'Username', ltr: true, icon: Icons.person_rounded),
      InField(_pass, 'Password', ltr: true, icon: Icons.key_rounded),
      const Text('الباقة', style: K.h3),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'monthly', label: Text('شهري')), ButtonSegment(value: 'quarterly', label: Text('3 أشهر')), ButtonSegment(value: 'yearly', label: Text('سنوي'))],
        selected: {_plan},
        onSelectionChanged: (s) => setState(() { _plan = s.first; _days.text = '${kPlanDays[_plan]}'; }),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: InField(_days, 'الأيام', number: true)),
        const SizedBox(width: 10),
        Expanded(child: InField(_count, 'عدد الأكواد', number: true)),
      ]),
      InField(_agent, 'الوكيل (اختياري)', icon: Icons.badge_rounded),
      InField(_note, 'ملاحظة (اختياري)', icon: Icons.sticky_note_2_rounded),
    ]),
    bottomNavigationBar: BottomAction(child: BusyButton(label: 'توليد الأكواد', icon: Icons.key_rounded, busy: _busy, onPressed: _gen)),
  );
}
