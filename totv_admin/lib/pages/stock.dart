part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  📦 المخزون — حسابات السيرفر + الهوست الحالي + التفعيل الذكي + النقل التلقائي
// ════════════════════════════════════════════════════════════════════
class Line {
  final Map<String, dynamic> r;
  Line(this.r);
  int get id => r.i('id');
  String get username => r.str('username');
  String get password => r.str('password');
  String get host => r.str('host');
  String get package => r.str('package');
  int get pkgDays => r.i('pkg_days');
  DateTime? get expiry => r.d('expiry_date');
  bool get disabled => r['disabled'] == true;
  bool get review => r['needs_review'] == true;
  String get reviewReason => r.str('review_reason');
  int get users => r.i('active_users');
  int get cap => r.i('cap') > 0 ? r.i('cap') : 10;
  int? get days => Fmt.daysLeft(expiry);
  List<Map<String, dynamic>> get people => r.l('users').map((e) => Map<String, dynamic>.from(e as Map)).toList();
  int get historyCount => r.i('history_count');

  String get state {
    if (disabled) return 'disabled';
    if (expiry != null && (days ?? 0) <= 0) return 'expired';
    if (review) return 'review';
    if (users >= cap) return 'full';
    return 'free';
  }
}

const _lnState = {
  'free': ('متاح', K.grn, Icons.check_circle_rounded),
  'full': ('ممتلئ', K.blu, Icons.groups_rounded),
  'expired': ('منتهي', K.red, Icons.cancel_rounded),
  'review': ('مراجعة', K.org, Icons.rule_rounded),
  'disabled': ('موقوف', K.t3, Icons.pause_circle_rounded),
};

class StockPage extends StatefulWidget {
  const StockPage({super.key});
  @override State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> with AutomaticKeepAliveClientMixin {
  List<Line> _lines = [];
  Map<String, dynamic> _meta = {}, _sum = {};
  int? _impact;
  DateTime? _at;
  bool _busy = false;
  String _err = '', _f = 'all';
  final _q = TextEditingController();
  int _show = 60;

  @override bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _cached(); }

  Future<void> _cached() async {
    final c = await DiskCache.read('stock');
    if (c is Map) {
      final m = Map<String, dynamic>.from(c);
      _apply(m.m('list'), m.m('sum'), m['impact'] as int?);
      _at = await DiskCache.time('stock');
      if (mounted) setState(() {});
    } else if (Supa.linked.value) {
      _load();
    }
  }

  void _apply(Map<String, dynamic> l, Map<String, dynamic> s, int? imp) {
    _lines = l.l('lines').map((e) => Line(Map<String, dynamic>.from(e as Map))).toList();
    _meta = Map<String, dynamic>.from(l)..remove('lines');
    _sum = s;
    _impact = imp;
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _err = ''; });
    try {
      final r = await Future.wait([
        Supa.call('admin_lines_list'),
        Supa.call('admin_summary').catchError((_) => <String, dynamic>{}),
        Supa.call('admin_host_impact').catchError((_) => <String, dynamic>{}),
      ]);
      final imp = r[2]['affected'] is num ? (r[2]['affected'] as num).toInt() : null;
      _apply(r[0], r[1], imp);
      _at = DateTime.now();
      StockLines.lines = _lines; StockLines.currentHost = _curHost; StockLines.at = _at;
      await DiskCache.write('stock', {'list': r[0], 'sum': r[1], 'impact': imp});
      // النقل التلقائي: كل 30 دقيقة كحد أقصى
      final last = Prefs.p.getInt('rescue_at') ?? 0;
      if ('${_meta['auto_rescue'] ?? 'on'}' == 'on' && DateTime.now().millisecondsSinceEpoch - last > 30 * 60000) {
        unawaited(_rescue(silent: true));
      }
    } catch (e) {
      _err = Fmt.err(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  String get _curHost => _meta.str('current_host');

  Future<void> _rescue({int? lineId, bool silent = false}) async {
    try {
      await Prefs.p.setInt('rescue_at', DateTime.now().millisecondsSinceEpoch);
      final r = await Supa.call('admin_rescue', {'p_dry': false, 'p_line_id': lineId});
      final moved = r.l('moved'), failed = r.l('failed');
      await _syncUsers(moved.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      if (moved.isNotEmpty) {
        BotLog.add('moved', '🔁 نُقل ${moved.length} مشترك', 'نقل ${silent ? 'تلقائي' : 'يدوي'} من حسابات منتهية/موقوفة');
        UI.toast('🔁 نُقل ${moved.length} مشترك تلقائياً لحسابات متاحة');
        if (!silent || moved.isNotEmpty) await _load();
      } else if (failed.isNotEmpty) {
        UI.toast('${failed.length} مشترك بحاجة لحسابات جديدة — أضف حسابات للمخزون', error: true);
      } else if (!silent) {
        UI.toast('لا يوجد مشترك على حساب منتهٍ أو موقوف');
      }
    } catch (e) { if (!silent) UI.err(e); }
  }

  /// كتابة بيانات الحساب الجديد عند المشتركين في Firestore (دفعات 400)
  static Future<void> _syncUsers(List<Map<String, dynamic>> rows) async {
    final fs = FirebaseFirestore.instance;
    for (var i = 0; i < rows.length; i += 400) {
      final b = fs.batch();
      for (final m in rows.skip(i).take(400)) {
        b.update(fs.collection('users').doc(m.str('uid')), {
          'subscription.host': m.str('host'), 'subscription.server_host': m.str('host'),
          'subscription.username': m.str('username'), 'subscription.password': m.str('password'),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      try { await b.commit(); } catch (e) { CrashLog.add('sync users: $e'); }
    }
  }

  Future<void> _patch(Line l, Map<String, dynamic> patch, {String? done}) async {
    if (patch['disabled'] == true && l.users > 0 &&
        !await UI.confirm('إيقاف ${l.username}؟', 'عليه ${l.users} مشترك — سيُنقلون فوراً لحسابات متاحة.', danger: true)) return;
    try {
      final r = await Supa.call('admin_line_update', {'p_id': l.id, 'p_patch': patch});
      if (patch['disabled'] == true || patch.containsKey('expiry_date')) await _rescue(lineId: l.id, silent: true);
      final uids = r.l('uids');
      if (r.i('users_updated') > 0 && uids.isNotEmpty) {
        final n = r.m('line');
        await _syncUsers(uids.map((u) => {'uid': '$u', 'host': n.str('host'), 'username': n.str('username'), 'password': n.str('password')}).toList());
        UI.toast('حُدّث الحساب و${r.i('users_updated')} مشترك عليه');
      } else {
        UI.toast(done ?? 'تم');
      }
      await _load();
    } catch (e) { UI.err(e); }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final q = _q.text.trim().toLowerCase();
    final cnt = <String, int>{};
    for (final l in _lines) { cnt[l.state] = (cnt[l.state] ?? 0) + 1; }
    final soon = _lines.where((l) { final d = l.days; return d != null && d > 0 && d <= 7; }).length;
    final dead = _lines.where((l) => l.state == 'expired' && l.users > 0).length;
    var list = _lines.where((l) {
      switch (_f) {
        case 'all': break;
        case 'soon': final d = l.days; if (!(d != null && d > 0 && d <= 7)) return false; break;
        case 'dead': if (!(l.state == 'expired' && l.users > 0)) return false; break;
        default: if (l.state != _f) return false;
      }
      if (q.isEmpty) return true;
      return [l.username, l.password, l.host, l.package, l.r.str('notes'), ...l.people.map((u) => u.str('email'))]
          .any((v) => v.toLowerCase().contains(q));
    }).toList();
    final fill = _meta.str('assign_mode') == 'fill';
    if (fill) {
      list.sort((a, b) => a.id.compareTo(b.id));
    } else {
      list.sort((a, b) {
        final s = (a.state == 'free' ? 0 : 1).compareTo(b.state == 'free' ? 0 : 1);
        if (s != 0) return s;
        final u = a.users.compareTo(b.users);
        if (u != 0) return u;
        return (a.expiry ?? DateTime(2000)).compareTo(b.expiry ?? DateTime(2000));
      });
    }
    final nextId = list.where((l) => l.state == 'free').map((l) => l.id).firstOrNull;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K.gold, foregroundColor: Colors.black,
        onPressed: () async { final ok = await Nav.push<bool>(AddLinesPage(currentHost: _curHost, existing: _lines.map((l) => l.username.toLowerCase()).toSet())); if (ok == true) _load(); },
        icon: const Icon(Icons.add_rounded), label: const Text('إضافة حسابات', style: TextStyle(fontWeight: FontWeight.w900))),
      body: RefreshIndicator(
        color: K.gold, backgroundColor: K.card, onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: PageHeader('المخزون', sub: _at == null ? 'حسابات السيرفر الجاهزة للتفعيل' : 'محدَّث ${Fmt.ago(_at)}', actions: [
            IconButton(tooltip: 'نقل المشتركين من الحسابات المنتهية', onPressed: () => _rescue(), icon: const Icon(Icons.swap_horiz_rounded, size: 26)),
            IconButton(onPressed: _busy ? null : _load, icon: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: K.gold))
                : const Icon(Icons.refresh_rounded, size: 28)),
          ])),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!Supa.linked.value) Padding(padding: const EdgeInsets.only(bottom: 12), child: Banner2('اربط قاعدة الاشتراكات لعرض المخزون',
                color: K.red, icon: Icons.link_off_rounded, action: TextButton(onPressed: linkSupabase, child: const Text('ربط')))),
            if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorBox(_err, onRetry: _load)),
            _hostCard(),
            const SizedBox(height: 12),
            KpiGrid(children: [
              Kpi(label: 'مقعد متاح للتفعيل', value: Fmt.n(_sum['stock_seats'] as num?), icon: Icons.event_seat_rounded, color: K.grn,
                  onTap: () => setState(() => _f = 'free')),
              Kpi(label: 'ينتهي خلال 7 أيام', value: '$soon', icon: Icons.timer_rounded, color: K.org, onTap: () => setState(() => _f = 'soon')),
              Kpi(label: 'مشترك فعّال الآن', value: Fmt.n(_sum['active_total'] as num?), icon: Icons.workspace_premium_rounded, color: K.gold,
                  hint: _sum.isEmpty ? null : 'كود ${Fmt.n(_sum['active_code'] as num?)} · أدمن ${Fmt.n(_sum['active_manual'] as num?)}'),
              Kpi(label: 'حساب منتهٍ عليه مشتركون', value: '$dead', icon: Icons.warning_rounded, color: dead > 0 ? K.red : K.t2,
                  onTap: () => setState(() => _f = 'dead')),
            ]),
            const SizedBox(height: 4),
            SearchBox(controller: _q, hint: 'بحث باليوزر أو الهوست أو بريد مشترك', onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            Filters<String>(value: _f, onChanged: (v) => setState(() { _f = v; _show = 60; }), items: [
              ('all', 'الكل', _lines.length), ('free', 'متاح', cnt['free'] ?? 0), ('full', 'ممتلئ', cnt['full'] ?? 0),
              ('soon', 'قريب الانتهاء', soon), ('review', 'مراجعة', cnt['review'] ?? 0),
              ('expired', 'منتهي', cnt['expired'] ?? 0), ('dead', 'عليه مشتركون', dead), ('disabled', 'موقوف', cnt['disabled'] ?? 0),
            ]),
            const SizedBox(height: 6),
            Text('${list.length} حساب · الترتيب = ترتيب التفعيل (${fill ? 'تعبئة' : 'الأقل ضغطاً أولاً'})', style: K.tiny),
            const SizedBox(height: 8),
          ]))),
          if (list.isEmpty && !_busy)
            SliverToBoxAdapter(child: EmptyView(icon: Icons.inventory_2_rounded, title: _lines.isEmpty ? 'المخزون فارغ' : 'لا نتائج',
                sub: _lines.isEmpty ? 'اضغط «إضافة حسابات» والصق رسالة الحسابات من البنل' : null))
          else
            SliverList.builder(
              itemCount: math.min(list.length, _show) + (list.length > _show ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _show) {
                  return Padding(padding: const EdgeInsets.all(16), child: OutlinedButton(
                      onPressed: () => setState(() => _show += 100), child: Text('عرض المزيد (${list.length - _show})')));
                }
                final l = list[i];
                return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: _lineCard(l, next: l.id == nextId));
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ]),
      ),
    );
  }

  Widget _hostCard() {
    final mode = _meta.str('assign_mode') == 'fill' ? 'fill' : 'smart';
    final cap = _meta.i('line_capacity') > 0 ? _meta.i('line_capacity') : 10;
    final auto = '${_meta['auto_rescue'] ?? 'on'}' == 'on';
    return Box(
      gradient: LinearGradient(colors: [K.blu.withOpacity(.12), K.card], begin: Alignment.topRight, end: Alignment.bottomLeft),
      border: K.blu.withOpacity(.3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.public_rounded, color: K.blu),
          const SizedBox(width: 8),
          const Expanded(child: Text('الهوست الحالي', style: K.h3)),
          if (_impact != null) Pill('$_impact مشترك فعّال', color: K.blu),
        ]),
        const SizedBox(height: 8),
        InkWell(
          onTap: _curHost.isEmpty ? null : () => UI.copy(_curHost),
          child: Text(_curHost.isEmpty ? 'لم يُحدَّد بعد — اضغط «تغيير»' : _curHost, textDirection: TextDirection.ltr,
              style: K.mono.copyWith(fontSize: 15, fontWeight: FontWeight.w800, color: _curHost.isEmpty ? K.red : K.t1)),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActBtn(Icons.edit_rounded, 'تغيير الهوست', _changeHost, color: K.blu),
          ActBtn(mode == 'fill' ? Icons.format_list_numbered_rounded : Icons.auto_awesome_rounded,
              mode == 'fill' ? 'الوضع: تعبئة' : 'الوضع: ذكي', () async {
            final v = await UI.pick<String>('طريقة اختيار الحساب عند التفعيل', [
              ('smart', 'ذكي — الحساب الأقل ضغطاً الذي يغطي المدة', Icons.auto_awesome_rounded),
              ('fill', 'تعبئة — يُملأ كل حساب حتى السعة ثم التالي', Icons.format_list_numbered_rounded),
            ]);
            if (v != null) await _setting('assign_mode', v, 'تم');
          }),
          ActBtn(Icons.groups_rounded, 'السعة: $cap', () async {
            final v = await UI.input('سعة كل حساب', number: true, initial: '$cap', help: 'كم مشترك على نفس يوزر السيرفر قبل الانتقال للتالي');
            if (v != null && (int.tryParse(v) ?? 0) > 0) await _setting('line_capacity', v, 'السعة: $v');
          }),
          ActBtn(auto ? Icons.autorenew_rounded : Icons.do_not_disturb_on_rounded, auto ? 'النقل التلقائي: يعمل' : 'النقل التلقائي: متوقف',
              () => _setting('auto_rescue', auto ? 'off' : 'on', auto ? 'أُوقف النقل التلقائي' : 'فُعّل النقل التلقائي'),
              color: auto ? K.grn : K.t3),
        ]),
      ]),
    );
  }

  Future<void> _setting(String k, String v, String msg) async {
    try { await Supa.call('admin_set_setting', {'p_key': k, 'p_value': v}); UI.toast(msg); await _load(); } catch (e) { UI.err(e); }
  }

  Future<void> _changeHost() async {
    final ctrl = TextEditingController();
    var apply = true;
    final hist = _meta.l('host_history').map((e) => '$e').where((x) => x != _curHost).take(6).toList();
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (s) => StatefulBuilder(
      builder: (s, set) => Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.of(s).viewInsets.bottom + 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('تغيير الهوست الحالي', style: K.h2),
          const SizedBox(height: 6),
          const Text('يُستخدم لكل حساب ليس له هوست خاص، ويُكتب تلقائياً عند كل تفعيل.', style: K.sub),
          const SizedBox(height: 14),
          TextField(controller: ctrl, autofocus: true, textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'الهوست الجديد', hintText: 'http://server.com:8080')),
          if (hist.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final h in hist) ActionChip(label: Text(h, textDirection: TextDirection.ltr), onPressed: () => ctrl.text = h),
            ]),
          ],
          SwitchRow(title: 'تطبيقه على كل المشتركين الحاليين', sub: _impact == null ? null : 'سيتغير عند $_impact مشترك فعّال',
              value: apply, onChanged: (v) => set(() => apply = v)),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => Navigator.pop(s, true), child: const Text('حفظ الهوست')),
        ]),
      )));
    final v = ctrl.text.trim();
    if (ok != true || v.isEmpty) return;
    try {
      final r = await Supa.call('admin_set_current_host', {'p_host': v, 'p_apply': apply});
      final uids = r.l('uids');
      final fs = FirebaseFirestore.instance;
      for (var i = 0; i < uids.length; i += 400) {
        final b = fs.batch();
        for (final u in uids.skip(i).take(400)) {
          b.update(fs.collection('users').doc('$u'), {'subscription.host': r.str('host'), 'subscription.server_host': r.str('host'),
              'updated_at': FieldValue.serverTimestamp()});
        }
        try { await b.commit(); } catch (e) { CrashLog.add('host fs: $e'); }
      }
      UI.toast('الهوست الحالي: ${r.str('host')}${apply ? ' — حُدِّث عند ${r.i('updated')} مشترك' : ''}');
      await _load();
    } catch (e) { UI.err(e); }
  }

  Widget _lineCard(Line l, {bool next = false}) {
    final (label, color, icon) = _lnState[l.state]!;
    final d = l.days;
    final ppl = l.people;
    return Box(
      padding: const EdgeInsets.all(14),
      border: next ? K.gold.withOpacity(.6) : null,
      onTap: () => _lineMenu(l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: InkWell(onTap: () => UI.copy(l.username, label: 'نُسخ اليوزر'), child: Text(l.username, textDirection: TextDirection.ltr,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: K.mono.copyWith(fontSize: 15.5, fontWeight: FontWeight.w900, color: K.gold)))),
              if (next) ...[const SizedBox(width: 6), const Pill('التالي', color: K.gold, solid: true)],
            ]),
            const SizedBox(height: 2),
            InkWell(onTap: () => UI.copy(l.password, label: 'نُسخ الباسوورد'), child: Text(l.password, textDirection: TextDirection.ltr,
                style: K.mono.copyWith(fontSize: 12.5, color: K.t2))),
            const SizedBox(height: 2),
            Text(l.host.isEmpty ? '🌐 الهوست الحالي' : '🖥 ${l.host}', textDirection: l.host.isEmpty ? null : TextDirection.ltr, style: K.tiny),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Pill(label, color: color, icon: icon),
            const SizedBox(height: 6),
            Pill(d == null ? 'بلا تاريخ' : (d <= 0 ? 'منتهي' : '$d يوم'),
                color: d == null ? K.t3 : (d <= 0 ? K.red : (d <= 7 ? K.org : K.grn))),
          ]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Text('${l.users}/${l.cap}', style: K.mono.copyWith(fontSize: 12.5, color: l.users >= l.cap ? K.blu : K.t1)),
          const SizedBox(width: 8),
          Expanded(child: Meter(l.users / l.cap, color: l.users >= l.cap ? K.blu : K.gold)),
          const SizedBox(width: 8),
          Text(l.package.isEmpty ? '' : l.package, maxLines: 1, style: K.tiny),
        ]),
        if (ppl.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final u in ppl.take(3))
            InkWell(
              onTap: () => Nav.push(MemberPage(uid: u.str('uid'), email: u.str('email'))),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                Icon(Icons.circle, size: 8, color: u['active'] == true ? K.grn : K.t3),
                const SizedBox(width: 6),
                Expanded(child: Text(u.str('email').isEmpty ? u.str('uid') : u.str('email'), maxLines: 1, overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr, style: K.tiny.copyWith(color: u['active'] == true ? K.t1 : K.t3))),
              ])),
            ),
          if (ppl.length > 3) Text('+${ppl.length - 3} آخرين', style: K.tiny.copyWith(color: K.gold)),
        ],
        if (l.review && l.reviewReason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
            child: Text('⚠ ${l.reviewReason}', style: const TextStyle(color: K.org, fontSize: 12))),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (l.state == 'free') ActBtn(Icons.person_add_alt_1_rounded, 'فعّل لمستخدم', () => _giveTo(l), filled: true, color: K.gold),
          if (l.review) ActBtn(Icons.done_all_rounded, 'اعتماد', () => _patch(l, {'needs_review': false}, done: 'اعتُمد الحساب'), color: K.grn),
          ActBtn(Icons.history_rounded, 'من استخدمه${l.historyCount > 0 ? ' (${l.historyCount})' : ''}', () => Nav.push(LineWhoPage(l.username))),
          ActBtn(Icons.more_horiz_rounded, 'المزيد', () => _lineMenu(l)),
        ]),
      ]),
    );
  }

  Future<void> _giveTo(Line l) async {
    final e = await UI.input('تفعيل ${l.username} لمستخدم', hint: 'بريد المستخدم', help: 'يجب أن يكون مسجلاً في التطبيق');
    if (e == null || e.isEmpty) return;
    final u = await findUser(e);
    if (u == null) return;
    await AutoActivateSheet.open(uid: u.$1, email: u.$2, name: u.$3, lineId: l.id);
    _load();
  }

  Future<void> _lineMenu(Line l) async {
    final a = await UI.pick<String>(l.username, [
      ('edit', 'تعديل الحساب', Icons.edit_rounded),
      ('copy', 'نسخ البيانات', Icons.copy_rounded),
      (l.disabled ? 'on' : 'off', l.disabled ? 'تشغيل الحساب' : 'إيقاف الحساب (ونقل مشتركيه)', l.disabled ? Icons.play_arrow_rounded : Icons.pause_rounded),
      ('move', 'نقل مشتركيه الآن', Icons.swap_horiz_rounded),
      ('del', 'حذف من المخزون', Icons.delete_rounded),
    ]);
    switch (a) {
      case 'edit': final ok = await Nav.push<bool>(LineEditPage(l)); if (ok == true) await _load(); break;
      case 'copy': await UI.copy('${l.host.isEmpty ? _curHost : l.host}\n${l.username}\n${l.password}'); break;
      case 'on': await _patch(l, {'disabled': false}, done: 'تم تشغيل الحساب'); break;
      case 'off': await _patch(l, {'disabled': true}, done: 'أُوقف الحساب'); break;
      case 'move': await _rescue(lineId: l.id); break;
      case 'del':
        if (!await UI.confirm('حذف ${l.username}؟', l.users > 0 ? 'عليه ${l.users} مشترك فعّال — لن يتأثر اشتراكهم.' : 'سيُحذف من المخزون.', danger: true, ok: 'حذف')) return;
        try { await Supa.call('admin_line_delete', {'p_id': l.id}); UI.toast('حُذف'); await _load(); } catch (e) { UI.err(e); }
        break;
    }
  }
}

/// البحث عن مستخدم بالبريد أو UID ⇐ (uid, email, name)
Future<(String, String, String)?> findUser(String q) async {
  q = q.trim();
  final users = FirebaseFirestore.instance.collection('users');
  try {
    final d = await users.doc(q).get();
    if (d.exists) return (d.id, '${d.data()?['email'] ?? ''}', '${d.data()?['display_name'] ?? ''}');
    for (final e in {q.toLowerCase(), q}) {
      final s = await users.where('email', isEqualTo: e).limit(1).get();
      if (s.docs.isNotEmpty) {
        final x = s.docs.first;
        return (x.id, '${x.data()['email'] ?? ''}', '${x.data()['display_name'] ?? ''}');
      }
    }
  } catch (e) { UI.err(e); return null; }
  UI.toast('لا يوجد مستخدم بهذا البريد — يجب أن يسجّل في التطبيق أولاً', error: true);
  return null;
}

// ════════════════════════════════════════════════════════════════════
//  تعديل حساب
// ════════════════════════════════════════════════════════════════════
class LineEditPage extends StatefulWidget {
  final Line l;
  const LineEditPage(this.l, {super.key});
  @override State<LineEditPage> createState() => _LineEditPageState();
}

class _LineEditPageState extends State<LineEditPage> {
  late final _host = TextEditingController(text: widget.l.host);
  late final _user = TextEditingController(text: widget.l.username);
  late final _pass = TextEditingController(text: widget.l.password);
  late final _pkg = TextEditingController(text: widget.l.package);
  late final _notes = TextEditingController(text: widget.l.r.str('notes'));
  late final _cap = TextEditingController(text: widget.l.r['capacity'] == null ? '' : '${widget.l.r['capacity']}');
  late DateTime? _exp = widget.l.expiry;
  bool _busy = false;

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _exp ?? DateTime.now().add(const Duration(days: 30)),
        firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_exp ?? DateTime(2000, 1, 1, 23, 59)));
    setState(() => _exp = DateTime(d.year, d.month, d.day, t?.hour ?? 23, t?.minute ?? 59));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final e = _exp;
      final iso = e == null ? '' : '${e.year}-${Fmt.two(e.month)}-${Fmt.two(e.day)}T${Fmt.two(e.hour)}:${Fmt.two(e.minute)}:00+03:00';
      final r = await Supa.call('admin_line_update', {'p_id': widget.l.id, 'p_patch': {
        'host': _host.text.trim(), 'username': _user.text.trim(), 'password': _pass.text.trim(),
        'expiry_date': iso, 'capacity': _cap.text.trim(), 'package': _pkg.text, 'notes': _notes.text, 'needs_review': false,
      }});
      final uids = r.l('uids');
      if (uids.isNotEmpty) {
        final n = r.m('line');
        await _StockPageState._syncUsers(uids.map((u) => {'uid': '$u', 'host': n.str('host'), 'username': n.str('username'), 'password': n.str('password')}).toList());
      }
      try { await Supa.call('admin_rescue', {'p_dry': false, 'p_line_id': widget.l.id}); } catch (_) {}
      UI.toast(uids.isEmpty ? 'حُفظ الحساب' : 'حُفظ وحُدّث ${uids.length} مشترك عليه');
      if (mounted) Navigator.pop(context, true);
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('تعديل ${widget.l.username}')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      InField(_host, 'Host (فارغ = الهوست الحالي)', ltr: true, icon: Icons.dns_rounded),
      InField(_user, 'Username', ltr: true, icon: Icons.person_rounded),
      InField(_pass, 'Password', ltr: true, icon: Icons.key_rounded),
      Box(onTap: _pickDate, padding: const EdgeInsets.all(14), child: Row(children: [
        const Icon(Icons.event_rounded, color: K.gold),
        const SizedBox(width: 10),
        Expanded(child: Text('ينتهي في البنل: ${Fmt.dt(_exp)}', style: K.body.copyWith(fontWeight: FontWeight.w800))),
        const Icon(Icons.edit_calendar_rounded, color: K.t3),
      ])),
      const SizedBox(height: 12),
      InField(_cap, 'سعة خاصة لهذا الحساب (فارغ = الافتراضي)', number: true, icon: Icons.groups_rounded),
      InField(_pkg, 'الباقة', icon: Icons.inventory_2_rounded),
      InField(_notes, 'ملاحظات', icon: Icons.sticky_note_2_rounded),
      const Banner2('تغيير اليوزر/الباسوورد/الهوست يُطبَّق تلقائياً على كل المشتركين على هذا الحساب.'),
    ]),
    bottomNavigationBar: BottomAction(child: BusyButton(label: 'حفظ', icon: Icons.save_rounded, busy: _busy, onPressed: _save)),
  );
}

// ════════════════════════════════════════════════════════════════════
//  من استخدم هذا الحساب (حالياً وسابقاً)
// ════════════════════════════════════════════════════════════════════
class LineWhoPage extends StatelessWidget {
  final String username;
  const LineWhoPage(this.username, {super.key});
  static const _reason = {'activate': 'تفعيل', 'renew': 'تجديد', 'auto-move': 'نقل تلقائي', 'backfill': 'قديم', 'code': 'كود', 'change': 'تغيير'};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('من استخدم $username')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: Supa.call('admin_line_people', {'p_username': username}),
      builder: (_, s) {
        if (s.hasError) return Padding(padding: const EdgeInsets.all(16), child: ErrorBox(Fmt.err(s.error!)));
        if (!s.hasData) return const Loading();
        final r = s.data!;
        final lines = r.l('lines'), cur = r.l('current'), hist = r.l('history'), codes = r.l('codes');
        final l = lines.isEmpty ? null : Map<String, dynamic>.from(lines.first as Map);
        final now = cur.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        Widget person(Map<String, dynamic> p, Widget trailing) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Box(padding: const EdgeInsets.all(12), onTap: () => Nav.push(MemberPage(uid: p.str('uid'), email: p.str('email'))),
            child: Row(children: [
              Avatar(p.str('email').isEmpty ? '?' : p.str('email'), size: 36),
              const SizedBox(width: 10),
              Expanded(child: Text(p.str('email').isEmpty ? p.str('uid') : p.str('email'), textDirection: TextDirection.ltr,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: K.body)),
              trailing,
            ])));
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (l != null) Box(child: Column(children: [
            InfoRow('الحساب', l.str('username'), copy: true, ltr: true, color: K.gold),
            InfoRow('Password', l.str('password'), copy: true, ltr: true),
            InfoRow('Host', l.str('host'), copy: true, ltr: true),
            InfoRow('ينتهي في البنل', Fmt.dt(l.d('expiry_date'))),
            InfoRow('السعة', '${now.where((p) => p['active'] == true).length} / ${l['cap'] ?? 10}'),
          ])) else const Banner2('هذا اليوزر غير موجود في المخزون (ربما حساب قديم أو يدوي).'),
          Section('🟢 يستخدمونه الآن (${now.where((p) => p['active'] == true).length})'),
          ...now.where((p) => p['active'] == true).map((p) => person(p, Pill('${Fmt.daysLeft(p.d('expiry')) ?? '—'} يوم', color: K.grn))),
          if (now.any((p) => p['active'] != true)) ...[
            const Section('⚪ انتهى اشتراكهم وهو آخر حساب لهم'),
            ...now.where((p) => p['active'] != true).map((p) => person(p, Pill('منتهي ${Fmt.dateShort(p.d('expiry'))}', color: K.red))),
          ],
          Section('🕘 استخدموه سابقاً (${hist.length})'),
          ...hist.map((e) {
            final h = Map<String, dynamic>.from(e as Map);
            return person(h, Text('${Fmt.dateShort(h.d('from'))} ← ${h.d('to') == null ? 'الآن' : Fmt.dateShort(h.d('to'))} · ${_reason[h.str('reason')] ?? h.str('reason')}', style: K.tiny));
          }),
          if (codes.isNotEmpty) ...[
            Section('🔑 أكواد على هذا الحساب (${codes.length})'),
            ...codes.map((e) {
              final c = Map<String, dynamic>.from(e as Map);
              return Padding(padding: const EdgeInsets.only(bottom: 8), child: Box(padding: const EdgeInsets.all(12), onTap: () => UI.copy(c.str('code')),
                  child: Row(children: [
                    Text(c.str('code'), style: K.mono.copyWith(color: K.gold)),
                    const Spacer(),
                    Text(c.str('email').isEmpty ? 'غير مستخدم' : c.str('email'), style: K.tiny),
                  ])));
            }),
          ],
        ]);
      },
    ),
  );
}

// ════════════════════════════════════════════════════════════════════
//  ➕ إضافة حسابات: لصق رسالة / إدخال يدوي / صورة بالذكاء الاصطناعي
// ════════════════════════════════════════════════════════════════════
class AddLinesPage extends StatefulWidget {
  final String currentHost;
  final Set<String> existing;
  const AddLinesPage({super.key, required this.currentHost, required this.existing});
  @override State<AddLinesPage> createState() => _AddLinesPageState();
}

class _AddLinesPageState extends State<AddLinesPage> {
  final _text = TextEditingController();
  final _mu = TextEditingController(), _mp = TextEditingController(), _mpkg = TextEditingController();
  DateTime? _mexp;
  List<LineRow> _rows = [];
  bool _busy = false, _ai = false;
  int _tab = 0;

  void _analyze() {
    if (_text.text.trim().isEmpty) { UI.toast('الصق الرسالة أولاً', error: true); return; }
    final r = Panel.parseAny(_text.text);
    for (final x in r) { if (widget.existing.contains(x.username.toLowerCase())) x.take = true; }
    setState(() => _rows = r);
    if (r.isEmpty) UI.toast('لم أجد حسابات في النص — جرّب «قراءة صورة بالذكاء الاصطناعي»', error: true);
  }

  Future<void> _aiImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 2200);
    if (img == null) return;
    setState(() => _ai = true);
    try {
      final bytes = await img.readAsBytes();
      final j = await AI.json(
        'استخرج كل حسابات IPTV (Xtream) من الصورة. أعد JSON فقط: {"rows":[{"host":"","username":"","password":"","expiry":"YYYY-MM-DD HH:MM","expired":false,"max_conn":1,"package":"","uncertain":false}]}\n'
        '- انسخ اليوزر والباسوورد حرفاً بحرف. انتبه لـ 0/O و1/l/I و5/S. إن شككت ضع uncertain:true.\n'
        '- "منتهي الصلاحية" أو Expired ⇐ expired:true و expiry:"".\n- host فقط إن كان مكتوباً صراحة. لا تخترع صفوفاً.',
        extra: [{'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(bytes)}}]);
      final rows = (j is Map ? (j['rows'] as List? ?? []) : (j as List)).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final out = <LineRow>[];
      final unsure = <LineRow>{};
      for (final m in rows) {
        final r = LineRow(username: Panel.toLatin(m.str('username')).trim(), password: Panel.toLatin(m.str('password')).trim(),
            host: m.str('host').isEmpty ? '' : Panel.normHost(m.str('host')), package: m.str('package'))
          ..pkgDays = Panel.pkgDays(m.str('package'))
          ..expired = m['expired'] == true
          ..expiryDate = m['expired'] == true || m.str('expiry').isEmpty ? null : Panel.parseDate(m.str('expiry'))
          ..maxConn = math.max(m.i('max_conn'), 1);
        if (r.username.isEmpty || r.password.isEmpty) continue;
        out.add(r);
        if (m['uncertain'] == true) unsure.add(r);
      }
      Panel.finalize(out);
      for (final r in unsure) {
        r.needsReview = true;
        r.reviewReason = [r.reviewReason, 'قراءة غير مؤكدة من الصورة'].where((x) => x.isNotEmpty).join(' · ');
      }
      setState(() { _rows = out; _tab = 0; });
      if (out.isEmpty) UI.toast('لم يجد حسابات في الصورة', error: true);
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _ai = false);
  }

  void _manualAdd() {
    if (_mu.text.trim().isEmpty || _mp.text.trim().isEmpty) { UI.toast('اكتب اليوزر والباسوورد', error: true); return; }
    if (_mexp == null) { UI.toast('حدد تاريخ الانتهاء', error: true); return; }
    final e = _mexp!;
    final r = LineRow(username: _mu.text.trim(), password: _mp.text.trim(), package: _mpkg.text.trim())
      ..pkgDays = Panel.pkgDays(_mpkg.text)
      ..expiryDate = '${e.year}-${Fmt.two(e.month)}-${Fmt.two(e.day)}T${Fmt.two(e.hour)}:${Fmt.two(e.minute)}:00+03:00';
    Panel.finalize([r]);
    setState(() { _rows = [..._rows, r]; _mu.clear(); _mp.clear(); });
  }

  Future<void> _defaultExpiry() async {
    final v = await UI.input('تاريخ للحسابات بلا تاريخ', number: true, hint: 'عدد الأيام من اليوم', help: 'مثال: 30');
    final d = int.tryParse(v ?? '');
    if (d == null || d <= 0) return;
    final e = DateTime.now().add(Duration(days: d));
    final iso = '${e.year}-${Fmt.two(e.month)}-${Fmt.two(e.day)}T23:59:00+03:00';
    setState(() {
      for (final r in _rows) { if (r.expiryDate == null && !r.expired) r.expiryDate = iso; }
      Panel.finalize(_rows);
    });
  }

  Future<void> _save() async {
    final rows = _rows.where((r) => r.take).toList();
    if (rows.isEmpty) { UI.toast('لم تحدد أي حساب', error: true); return; }
    if (widget.currentHost.isEmpty && rows.any((r) => r.host.isEmpty)) {
      UI.toast('حدّد «الهوست الحالي» أولاً من صفحة المخزون أو اكتب هوستاً لكل حساب', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Supa.call('admin_lines_import', {'p_rows': rows.map((x) => x.toJson()).toList(), 'p_host': '', 'p_source': _tab == 1 ? 'manual' : 'text'});
      UI.toast('أُضيف ${r.i('inserted')} · حُدّث ${r.i('updated')}${r.i('expired_skipped') > 0 ? ' · منتهي لم يُضف ${r.i('expired_skipped')}' : ''}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final act = _rows.where((r) => r.active).length;
    final noExp = _rows.where((r) => r.expiryDate == null && !r.expired).length;
    final hosts = _rows.map((r) => r.host).where((h) => h.isNotEmpty).toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة حسابات للمخزون')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('لصق رسالة'), icon: Icon(Icons.content_paste_rounded)),
            ButtonSegment(value: 1, label: Text('يدوي'), icon: Icon(Icons.edit_rounded)),
            ButtonSegment(value: 2, label: Text('صورة'), icon: Icon(Icons.image_rounded)),
          ],
          selected: {_tab}, onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: 14),
        if (_tab == 0) ...[
          TextField(controller: _text, maxLines: 8, minLines: 5, textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: 'الصق هنا رسالة الحسابات من البنل أو واتساب أو تلجرام…\nجدول · Username: / Password: · روابط m3u · يوزر باسوورد تاريخ')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: _analyze, icon: const Icon(Icons.auto_fix_high_rounded), label: const Text('تحليل'))),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: () async {
              final d = await Clipboard.getData('text/plain');
              if (d?.text != null) { _text.text = d!.text!; _analyze(); }
            }, icon: const Icon(Icons.paste_rounded), label: const Text('لصق')),
          ]),
        ],
        if (_tab == 1) ...[
          InField(_mu, 'Username', ltr: true),
          InField(_mp, 'Password', ltr: true),
          InField(_mpkg, 'الباقة (اختياري)', hint: 'مثال: باقة شهر'),
          Box(padding: const EdgeInsets.all(14), onTap: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2035));
            if (d != null) setState(() => _mexp = DateTime(d.year, d.month, d.day, 23, 59));
          }, child: Row(children: [
            const Icon(Icons.event_rounded, color: K.gold),
            const SizedBox(width: 10),
            Text(_mexp == null ? 'تاريخ الانتهاء' : 'ينتهي ${Fmt.date(_mexp)}', style: K.body.copyWith(fontWeight: FontWeight.w800)),
          ])),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _manualAdd, icon: const Icon(Icons.add_rounded), label: const Text('إضافة للقائمة')),
        ],
        if (_tab == 2) ...[
          const Banner2('اختر صورة جدول الحسابات من البنل — يقرأها الذكاء الاصطناعي (Gemini). راجع الباسوورد حرفاً بحرف.',
              icon: Icons.auto_awesome_rounded),
          const SizedBox(height: 10),
          BusyButton(label: 'اختيار صورة', icon: Icons.image_search_rounded, busy: _ai, onPressed: _aiImage),
        ],
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 18),
          Box(color: K.card2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('وجدت ${_rows.length} حساب · شغّال $act · منتهي ${_rows.length - act}', style: K.h3),
            const SizedBox(height: 4),
            Text(hosts.isEmpty
                ? 'لا يوجد هوست في الرسالة — ستتبع كلها الهوست الحالي ${widget.currentHost.isEmpty ? '(غير محدد!)' : widget.currentHost}'
                : 'هوست مذكور: ${hosts.join(' , ')} — الحسابات بلا هوست تتبع الهوست الحالي', style: K.sub),
            if (noExp > 0) ...[
              const SizedBox(height: 8),
              ActBtn(Icons.event_available_rounded, '$noExp بلا تاريخ — حدّد تاريخاً', _defaultExpiry, color: K.org),
            ],
          ])),
          const SizedBox(height: 10),
          for (var i = 0; i < _rows.length; i++) _rowTile(i),
        ],
        const SizedBox(height: 80),
      ]),
      bottomNavigationBar: _rows.isEmpty ? null : BottomAction(child: BusyButton(
          label: 'حفظ ${_rows.where((r) => r.take).length} حساب في المخزون', icon: Icons.save_rounded, busy: _busy, onPressed: _save)),
    );
  }

  Widget _rowTile(int i) {
    final r = _rows[i];
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Box(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      color: r.expired ? K.card.withOpacity(.5) : null,
      border: r.needsReview && r.active ? K.org.withOpacity(.5) : null,
      child: Row(children: [
        Checkbox(value: r.take, activeColor: K.gold, checkColor: Colors.black, onChanged: (v) => setState(() => r.take = v ?? false)),
        Expanded(child: InkWell(
          onTap: () => _editRow(r),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.username, textDirection: TextDirection.ltr, style: K.mono.copyWith(fontWeight: FontWeight.w900)),
            Text(r.password, textDirection: TextDirection.ltr, style: K.mono.copyWith(fontSize: 12, color: K.t2)),
            Text('${r.expired ? 'منتهي' : (r.expiryDate == null ? 'بلا تاريخ' : Fmt.dt(DateTime.tryParse(r.expiryDate!)?.toLocal()))}'
                '${r.host.isEmpty ? '' : ' · ${r.host}'}', style: K.tiny),
            if (r.needsReview) Text('⚠ ${r.reviewReason}', style: const TextStyle(color: K.org, fontSize: 11.5)),
          ]),
        )),
        Pill(r.expired ? 'منتهي' : 'شغّال', color: r.expired ? K.red : K.grn),
      ]),
    ));
  }

  Future<void> _editRow(LineRow r) async {
    final u = await UI.input('اليوزر', initial: r.username);
    if (u == null) return;
    final p = await UI.input('الباسوورد', initial: r.password);
    if (p == null) return;
    setState(() { r.username = u; r.password = p; Panel.finalize(_rows); r.take = r.active; });
  }
}
