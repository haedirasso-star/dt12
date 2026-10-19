part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  الرئيسية — نظرة شاملة. الأرقام محفوظة وتتحدث فقط عند «تحديث»
// ════════════════════════════════════════════════════════════════════
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic> _dash = {}, _sum = {}, _inst = {};
  DateTime? _at;
  bool _busy = false;
  String _err = '';

  @override bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  Future<void> _loadCached() async {
    final c = await DiskCache.read('home');
    if (c is Map) {
      final m = Map<String, dynamic>.from(c);
      _dash = m.m('dash'); _sum = m.m('sum'); _inst = m.m('inst');
      _at = await DiskCache.time('home');
      if (mounted) setState(() {});
    }
    // أول مرة على هذا الهاتف: حمّل تلقائياً مرة واحدة
    if (c == null && Supa.linked.value) _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() { _busy = true; _err = ''; });
    try {
      final r = await Future.wait([
        Supa.call('admin_dashboard').catchError((_) => <String, dynamic>{}),
        Supa.call('admin_summary').catchError((_) => <String, dynamic>{}),
        Supa.call('admin_installs').catchError((_) => <String, dynamic>{}),
      ]);
      _dash = r[0]; _sum = r[1]; _inst = r[2];
      _at = DateTime.now();
      await DiskCache.write('home', {'dash': _dash, 'sum': _sum, 'inst': _inst});
      try { await Store.loadHistory(); } catch (e) { CrashLog.add('history: $e'); }
      HapticFeedback.lightImpact();
    } catch (e) {
      _err = Fmt.err(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  String get _greet {
    final h = DateTime.now().hour;
    return h < 12 ? 'صباح الخير' : (h < 18 ? 'مساء الخير' : 'مساء النور');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      color: K.gold, backgroundColor: K.card,
      onRefresh: _refresh,
      child: ListView(padding: EdgeInsets.zero, children: [
        PageHeader(_greet, sub: _at == null ? 'اسحب للأسفل للتحديث' : 'آخر تحديث ${Fmt.ago(_at)}', actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: K.gold))
                        : const Icon(Icons.refresh_rounded, size: 28)),
        ]),
        Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ValueListenableBuilder<bool>(valueListenable: Supa.linked, builder: (_, l, __) => l ? const SizedBox.shrink()
              : Padding(padding: const EdgeInsets.only(bottom: 12), child: Banner2('قاعدة الاشتراكات غير مربوطة — الأرقام والمخزون والأكواد تحتاجها',
                  color: K.red, icon: Icons.link_off_rounded,
                  action: TextButton(onPressed: linkSupabase, child: const Text('ربط'))))),
          if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: ErrorBox(_err, onRetry: _refresh)),
          _pendingCard(),
          ValueListenableBuilder<int>(valueListenable: Engage.unread, builder: (_, n, __) => n == 0 ? const SizedBox.shrink()
              : Padding(padding: const EdgeInsets.only(top: 10), child: Box(
                  onTap: () => Nav.push(const ChatsPage()),
                  border: Colors.white24,
                  child: Row(children: [
                    const Icon(Icons.forum_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(child: Text('$n رسالة جديدة من المستخدمين', style: K.h3)),
                    const Icon(Icons.chevron_left_rounded, color: K.t2),
                  ])))),
          const SizedBox(height: 10),
          _botCard(),
          const SizedBox(height: 12),
          _controlStrip(),
          const Section('المشتركون'),
          KpiGrid(children: [
            Kpi(label: 'مشترك فعّال الآن', value: Fmt.n(_dash['premium_active'] as num?), icon: Icons.workspace_premium_rounded, color: K.gold,
                hint: _dash.isEmpty ? null : 'المنتهي: ${Fmt.n(_dash['premium_expired'] as num?)}', onTap: () => Shell.go(3)),
            Kpi(label: 'ينتهون خلال 7 أيام', value: Fmt.n(_dash['expiring_7d'] as num?), icon: Icons.timer_rounded, color: K.org,
                hint: _dash.isEmpty ? null : 'خلال 3 أيام: ${Fmt.n(_dash['expiring_3d'] as num?)}',
                onTap: () { MembersPage.filter.value = 'exp7'; Shell.go(3); }),
            Kpi(label: 'تفعيلات اليوم', value: Fmt.n(_dash['activated_today'] as num?), icon: Icons.bolt_rounded, color: K.grn,
                hint: _dash.isEmpty ? null : '7 أيام: ${Fmt.n(_dash['activated_7d'] as num?)} · 30 يوماً: ${Fmt.n(_dash['activated_30d'] as num?)}'),
            Kpi(label: 'جدّدوا اشتراكهم', value: Fmt.n(_dash['renewers'] as num?), icon: Icons.autorenew_rounded, color: K.cyn,
                hint: _dash['avg_months'] == null ? null : 'متوسط البقاء ${_dash['avg_months']} شهر'),
          ]),
          const Section('المخزون والأكواد'),
          KpiGrid(children: [
            Kpi(label: 'مقعد متاح للتفعيل', value: Fmt.n(_sum['stock_seats'] as num?), icon: Icons.event_seat_rounded, color: K.grn,
                hint: _sum.isEmpty ? null : 'حسابات متاحة: ${Fmt.n(_sum['lines_free'] as num?)} من ${Fmt.n(_sum['lines_total'] as num?)}',
                onTap: () => Shell.go(2)),
            Kpi(label: 'مشترك على حساب منتهٍ', value: Fmt.n(_sum['users_on_dead_lines'] as num?), icon: Icons.warning_amber_rounded,
                color: (_sum.i('users_on_dead_lines')) > 0 ? K.red : K.t2, hint: 'تحتاج نقل', onTap: () => Shell.go(2)),
            Kpi(label: 'كود غير مستخدم', value: Fmt.n(_dash['codes_unused'] as num?), icon: Icons.key_rounded, color: K.blu,
                hint: _dash.isEmpty ? null : 'مستخدم: ${Fmt.n(_dash['codes_used'] as num?)}', onTap: () => Nav.push(const CodesPage())),
            Kpi(label: 'حساب يحتاج مراجعة', value: Fmt.n(_sum['lines_review'] as num?), icon: Icons.rule_rounded, color: K.org, onTap: () => Shell.go(2)),
          ]),
          const Section('التطبيق'),
          KpiGrid(children: [
            Kpi(label: 'نشط اليوم', value: Fmt.n(_inst['active_today'] as num?), icon: Icons.phone_android_rounded, color: K.prp,
                hint: _inst.isEmpty ? null : 'هذا الأسبوع: ${Fmt.n(_inst['active_week'] as num?)}'),
            Kpi(label: 'تثبيت جديد اليوم', value: Fmt.n(_inst['today'] as num?), icon: Icons.download_rounded, color: K.blu,
                hint: _inst.isEmpty ? null : 'الإجمالي: ${Fmt.n(_inst['total'] as num?)}'),
          ]),
          _ordersChart(),
          _sourcesChart(),
        ])),
      ]),
    );
  }

  Widget _pendingCard() => ValueListenableBuilder<List<AppOrder>>(
    valueListenable: Store.pending,
    builder: (_, p, __) {
      final oldest = p.isEmpty ? null : p.map((o) => o.created ?? DateTime.now()).reduce((a, b) => a.isBefore(b) ? a : b);
      final hot = p.isNotEmpty;
      return Box(
        onTap: () => Shell.go(1),
        padding: const EdgeInsets.all(18),
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
            colors: hot ? [K.gold.withOpacity(.28), K.card] : [K.grn.withOpacity(.14), K.card]),
        border: (hot ? K.gold : K.grn).withOpacity(.4),
        child: Row(children: [
          Container(width: 58, height: 58, alignment: Alignment.center,
              decoration: BoxDecoration(color: (hot ? K.gold : K.grn).withOpacity(.18), borderRadius: BorderRadius.circular(18)),
              child: Icon(hot ? Icons.notifications_active_rounded : Icons.task_alt_rounded, color: hot ? K.gold : K.grn, size: 30)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hot ? 'طلبات بانتظار التفعيل' : 'لا طلبات بانتظارك', style: K.h3),
            const SizedBox(height: 4),
            Text(hot ? 'أقدمها ${Fmt.ago(oldest)} — اضغط للمراجعة' : 'ستصلك إشعارات فورية عند كل طلب جديد', style: K.sub),
          ])),
          if (hot) Text('${p.length}', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: K.gold)),
        ]),
      );
    },
  );

  Widget _botCard() => ValueListenableBuilder<int>(
    valueListenable: BotLog.rev,
    builder: (_, __, ___) => ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: ServerBot.last,
      builder: (_, last, __) {
        final log = BotLog.read().where((e) => '${e['kind']}' != 'activate' && '${e['kind']}' != 'run').toList();
        final dead = Fmt.numOf(last['dead']), soon = Fmt.numOf(last['soon3']);
        final warn = dead > 0 || soon > 0 || Fmt.numOf(last['seats']) < ServerBot.lowSeats;
        final c = warn ? K.org : K.grn;
        return Box(
          onTap: () => Nav.push(const BotPage()),
          padding: const EdgeInsets.all(14),
          border: c.withOpacity(.35),
          child: Row(children: [
            Container(width: 44, height: 44, alignment: Alignment.center,
                decoration: BoxDecoration(color: c.withOpacity(.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.smart_toy_rounded, color: c)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(warn ? 'مراقب السيرفرات: يحتاج انتباهك' : 'مراقب السيرفرات: كل شيء سليم', style: K.h3.copyWith(fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(log.isEmpty ? 'يفحص الحسابات وينقل المشتركين تلقائياً'
                  : '${log.first['title']} · ${Fmt.ago(DateTime.tryParse('${log.first['at']}'))}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: K.sub),
            ])),
            if (dead > 0) Pill('$dead على منتهٍ', color: K.red) else if (soon > 0) Pill('$soon قريب', color: K.org),
          ]),
        );
      },
    ),
  );

  Widget _controlStrip() => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('app_config').doc('remote_control').snapshots(),
    builder: (_, s) {
      final d = s.data?.data() ?? {};
      Widget chip(String k, String on, String off, IconData icon) {
        final v = d[k] == true;
        return Expanded(child: Box(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          color: v ? K.red.withOpacity(.12) : K.card,
          border: v ? K.red.withOpacity(.4) : null,
          onTap: () async {
            if (!await UI.confirm(v ? 'إيقاف «$on»؟' : 'تفعيل «$on»؟',
                v ? 'سيعود التطبيق للعمل الطبيعي عند كل المستخدمين.' : 'سيظهر هذا فوراً عند كل المستخدمين.', danger: !v)) return;
            try {
              await FirebaseFirestore.instance.collection('app_config').doc('remote_control')
                  .set({k: !v, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
              UI.toast(!v ? '$on مفعّل' : '$off');
            } catch (e) { UI.err(e); }
          },
          child: Column(children: [
            Icon(icon, color: v ? K.red : K.t2, size: 22),
            const SizedBox(height: 6),
            Text(v ? on : off, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: v ? K.red : K.t2)),
          ]),
        ));
      }
      return Row(children: [
        chip('maintenance', 'وضع الصيانة', 'لا صيانة', Icons.construction_rounded),
        const SizedBox(width: 8),
        chip('locked', 'التطبيق مقفول', 'التطبيق مفتوح', Icons.lock_rounded),
        const SizedBox(width: 8),
        chip('guest_only', 'ضيوف فقط', 'الدخول طبيعي', Icons.person_outline_rounded),
      ]);
    },
  );

  Widget _ordersChart() => ValueListenableBuilder<List<AppOrder>>(
    valueListenable: Store.history,
    builder: (_, h, __) {
      final all = [...Store.pending.value, ...h];
      final now = DateTime.now();
      final bars = <BarSeries>[];
      var rev = 0;
      for (var i = 13; i >= 0; i--) {
        final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        final day = all.where((o) { final c = o.created; return c != null && c.year == d.year && c.month == d.month && c.day == d.day; });
        bars.add(BarSeries(i == 0 ? 'اليوم' : '${d.day}/${d.month}', [
          day.where((o) => o.status == 'approved').length.toDouble(),
          day.where((o) => o.pending).length.toDouble(),
          day.where((o) => o.status == 'rejected').length.toDouble(),
        ]));
      }
      for (final o in h) {
        final c = o.created;
        if (o.status == 'approved' && c != null && now.difference(c).inDays < 30) rev += o.amount;
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Section('طلبات الاشتراك — 14 يوماً', sub: h.isEmpty ? 'اضغط تحديث لتحميل السجل' : 'إيراد 30 يوماً: ${Fmt.n(rev)} د.ع'),
        Box(child: Column(children: [
          BarChart(bars: bars, colors: const [K.grn, K.gold, K.red], height: 170),
          const SizedBox(height: 10),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Legend(K.grn, 'مفعّلة'), SizedBox(width: 14), _Legend(K.gold, 'منتظرة'), SizedBox(width: 14), _Legend(K.red, 'مرفوضة'),
          ]),
        ])),
      ]);
    },
  );

  Widget _sourcesChart() {
    final bySrc = _dash.m('by_source'), byPlan = _dash.m('by_plan');
    if (bySrc.isEmpty && byPlan.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Section('توزيع المشتركين'),
      if (bySrc.isNotEmpty) Box(child: Donut(
          data: bySrc.map((k, v) => MapEntry(Fmt.srcAr[k] ?? k, v is num ? v.toDouble() : 0.0)))),
      const SizedBox(height: 10),
      if (byPlan.isNotEmpty) Box(child: Donut(
          data: byPlan.map((k, v) => MapEntry(Fmt.plan(k), v is num ? v.toDouble() : 0.0)),
          colors: const [K.blu, K.prp, K.cyn, K.gold, K.org])),
    ]);
  }
}

class _Legend extends StatelessWidget {
  final Color c;
  final String t;
  const _Legend(this.c, this.t);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 5),
    Text(t, style: K.tiny.copyWith(color: K.t2)),
  ]);
}
