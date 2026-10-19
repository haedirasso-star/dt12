part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🤖 مراقب السيرفرات — الحالة · الرسوم · السجل · الإعدادات
// ════════════════════════════════════════════════════════════════════
class BotPage extends StatefulWidget {
  const BotPage({super.key});
  @override State<BotPage> createState() => _BotPageState();
}

class _BotPageState extends State<BotPage> {
  bool _busy = false;
  String _f = 'all';
  List<Line> _lines = [];
  Map<String, dynamic> _meta = {};

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    try { await Prefs.p.reload(); } catch (_) {}
    final c = await DiskCache.read('stock');
    if (c is Map) {
      final l = Map<String, dynamic>.from(c).m('list');
      _lines = l.l('lines').map((e) => Line(Map<String, dynamic>.from(e as Map))).toList();
      _meta = l;
    }
    ServerBot.last.value = Prefs.getJson('bot_last_v1') ?? {};
    if (mounted) setState(() {});
  }

  Future<void> _runNow() async {
    setState(() => _busy = true);
    final r = await ServerBot.run(manual: true);
    await _loadLocal();
    if (mounted) setState(() => _busy = false);
    if (r.error.isNotEmpty) {
      UI.toast(r.error, error: true);
    } else {
      UI.toast(r.alerts > 0 ? '${r.alerts} تنبيه جديد${r.moved > 0 ? ' · نُقل ${r.moved} مشترك' : ''}' : 'كل شيء سليم ✅');
    }
  }

  Future<void> _setAutoRescue(bool v) async {
    try {
      await Supa.call('admin_set_setting', {'p_key': 'auto_rescue', 'p_value': v ? 'on' : 'off'});
      _meta['auto_rescue'] = v ? 'on' : 'off';
      setState(() {});
      UI.toast(v ? 'فُعّل النقل التلقائي' : 'أُوقف النقل التلقائي');
    } catch (e) { UI.err(e); }
  }

  static const _kinds = {
    'dead': (Icons.dangerous_rounded, K.red, 'انتهاء'),
    'soon': (Icons.alarm_rounded, K.org, 'قرب الانتهاء'),
    'expired': (Icons.event_busy_rounded, K.t3, 'انتهاء'),
    'low': (Icons.inventory_rounded, K.org, 'مخزون'),
    'moved': (Icons.swap_horiz_rounded, K.blu, 'نقل'),
    'failed': (Icons.report_rounded, K.red, 'نقل'),
    'activate': (Icons.bolt_rounded, K.grn, 'تفعيل'),
    'run': (Icons.smart_toy_rounded, K.t2, 'فحص'),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مراقب السيرفرات'), actions: [
      IconButton(onPressed: _busy ? null : _runNow, icon: _busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: K.gold))
          : const Icon(Icons.play_circle_fill_rounded, size: 28, color: K.gold)),
    ]),
    body: ValueListenableBuilder<int>(
      valueListenable: BotLog.rev,
      builder: (_, __, ___) => ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: ServerBot.last,
        builder: (_, last, __) => RefreshIndicator(
          color: K.gold, onRefresh: _runNow,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _statusCard(last),
            const SizedBox(height: 12),
            KpiGrid(children: [
              Kpi(label: 'مقعد متاح للتفعيل', value: Fmt.n(last['seats'] as num?), icon: Icons.event_seat_rounded,
                  color: Fmt.numOf(last['seats']) < ServerBot.lowSeats ? K.red : K.grn, hint: 'التنبيه تحت ${ServerBot.lowSeats}'),
              Kpi(label: 'مشترك على حساب منتهٍ', value: Fmt.n(last['dead'] as num?), icon: Icons.dangerous_rounded,
                  color: Fmt.numOf(last['dead']) > 0 ? K.red : K.t2, hint: 'يُنقلون تلقائياً'),
              Kpi(label: 'حساب ينتهي خلال 3 أيام', value: Fmt.n(last['soon3'] as num?), icon: Icons.alarm_rounded, color: K.org,
                  hint: 'وعليه مشتركون'),
              Kpi(label: 'حساب متاح / ممتلئ', value: '${Fmt.n(last['free'] as num?)} / ${Fmt.n(last['full'] as num?)}',
                  icon: Icons.dns_rounded, color: K.blu, hint: 'من ${Fmt.n(last['lines'] as num?)} حساب'),
            ]),
            _expiryChart(),
            _stateDonut(),
            _seatsTrend(),
            _upcoming(),
            _settings(),
            _log(),
            const SizedBox(height: 30),
          ]),
        ),
      ),
    ),
  );

  Widget _statusCard(Map<String, dynamic> last) {
    final at = DateTime.tryParse('${last['at'] ?? ''}');
    final err = '${last['error'] ?? ''}';
    final ok = at != null && err.isEmpty;
    return Box(
      gradient: LinearGradient(colors: [(ok ? K.grn : K.org).withOpacity(.16), K.card], begin: Alignment.topRight, end: Alignment.bottomLeft),
      border: (ok ? K.grn : K.org).withOpacity(.35),
      child: Row(children: [
        Container(width: 56, height: 56, alignment: Alignment.center,
            decoration: BoxDecoration(color: (ok ? K.grn : K.org).withOpacity(.18), borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.smart_toy_rounded, color: ok ? K.grn : K.org, size: 30)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ok ? 'البوت يعمل' : (at == null ? 'لم يعمل بعد' : 'آخر فحص فيه مشكلة'), style: K.h3),
          const SizedBox(height: 3),
          Text(at == null ? 'اضغط ▶ للفحص الآن' : 'آخر فحص ${Fmt.ago(at)}${last['bg'] == true ? ' (في الخلفية)' : ''}', style: K.sub),
          if (err.isNotEmpty) Text(err, style: K.tiny.copyWith(color: K.org)),
          Text(ServerBot.background ? 'يعمل كل ${ServerBot.intervalMin} دقيقة حتى والتطبيق مغلق' : 'يعمل فقط والتطبيق مفتوح', style: K.tiny),
        ])),
      ]),
    );
  }

  // انتهاء الحسابات خلال 14 يوماً (عليها مشتركون / فارغة)
  Widget _expiryChart() {
    if (_lines.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final bars = <BarSeries>[];
    for (var i = 0; i < 14; i++) {
      final d = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      final day = _lines.where((l) {
        final e = l.expiry;
        return !l.disabled && e != null && e.year == d.year && e.month == d.month && e.day == d.day;
      });
      bars.add(BarSeries(i == 0 ? 'اليوم' : '${d.day}/${d.month}', [
        day.where((l) => l.users > 0).length.toDouble(),
        day.where((l) => l.users == 0).length.toDouble(),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Section('انتهاء حسابات السيرفر — 14 يوماً', sub: 'عدد الحسابات التي تنتهي كل يوم'),
      Box(child: Column(children: [
        BarChart(bars: bars, colors: const [K.org, K.t3], height: 150),
        const SizedBox(height: 8),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Lg(K.org, 'عليها مشتركون'), SizedBox(width: 14), _Lg(K.t3, 'فارغة'),
        ]),
      ])),
    ]);
  }

  Widget _stateDonut() {
    if (_lines.isEmpty) return const SizedBox.shrink();
    final m = <String, double>{};
    const ar = {'free': 'متاح', 'full': 'ممتلئ', 'expired': 'منتهي', 'review': 'مراجعة', 'disabled': 'موقوف'};
    for (final l in _lines) { m[ar[l.state]!] = (m[ar[l.state]!] ?? 0) + 1; }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Section('حالة الحسابات'),
      Box(child: Donut(data: m, center: '${_lines.length}', colors: const [K.grn, K.blu, K.red, K.org, K.t3])),
    ]);
  }

  Widget _seatsTrend() {
    final m = (Prefs.getList('bot_metrics_v1') ?? []).map((e) => Map<String, dynamic>.from(e as Map)).take(16).toList().reversed.toList();
    if (m.length < 2) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Section('المقاعد المتاحة عبر الوقت', sub: 'لقطة كل فحص للبوت'),
      Box(child: BarChart(height: 140, colors: const [K.grn], bars: [
        for (final x in m) BarSeries(Fmt.time(DateTime.tryParse('${x['t']}')), [Fmt.numOf(x['seats']).toDouble()]),
      ])),
    ]);
  }

  Widget _upcoming() {
    final now = DateTime.now();
    final l = _lines.where((x) => !x.disabled && x.users > 0 && x.expiry != null && x.expiry!.isBefore(now.add(const Duration(days: 7))))
        .toList()..sort((a, b) => a.expiry!.compareTo(b.expiry!));
    if (l.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Section('حسابات تحتاج انتباهك (${l.length})', sub: 'منتهية أو تنتهي خلال 7 أيام وعليها مشتركون'),
      for (final x in l) Padding(padding: const EdgeInsets.only(bottom: 8), child: Box(
        padding: const EdgeInsets.all(12),
        border: (x.expiry!.isBefore(now) ? K.red : K.org).withOpacity(.4),
        onTap: () => Nav.push(LineWhoPage(x.username)),
        child: Row(children: [
          Icon(x.expiry!.isBefore(now) ? Icons.dangerous_rounded : Icons.alarm_rounded, color: x.expiry!.isBefore(now) ? K.red : K.org),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.username, textDirection: TextDirection.ltr, style: K.mono.copyWith(fontWeight: FontWeight.w900)),
            Text(x.expiry!.isBefore(now) ? 'انتهى ${Fmt.ago(x.expiry)}' : 'ينتهي ${Fmt.dayLabel(x.expiry!)} ${Fmt.time(x.expiry)}', style: K.tiny),
          ])),
          Pill('${x.users} مشترك', color: x.expiry!.isBefore(now) ? K.red : K.org),
        ]),
      )),
      if (l.any((x) => x.expiry!.isBefore(now)))
        OutlinedButton.icon(onPressed: _busy ? null : _runNow, icon: const Icon(Icons.swap_horiz_rounded), label: const Text('نقل المشتركين الآن')),
    ]);
  }

  Widget _settings() {
    final auto = '${_meta['auto_rescue'] ?? 'on'}' == 'on';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Section('الإعدادات'),
      Box(padding: const EdgeInsets.fromLTRB(14, 6, 14, 6), child: Column(children: [
        SwitchRow(title: 'العمل في الخلفية', sub: 'يفحص حتى والتطبيق مغلق ويرسل إشعاراً', icon: Icons.nightlight_round,
            value: ServerBot.background, onChanged: (v) async {
              await Prefs.p.setBool('bot_bg', v);
              await ServerBot.schedule();
              setState(() {});
            }),
        const Divider(),
        SwitchRow(title: 'النقل التلقائي', sub: 'ينقل مشتركي الحساب المنتهي إلى حساب متاح فوراً', icon: Icons.swap_horiz_rounded,
            value: auto, onChanged: _setAutoRescue),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_rounded, color: K.gold),
          title: const Text('فترة الفحص في الخلفية', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('كل ${ServerBot.intervalMin} دقيقة', style: K.tiny),
          onTap: () async {
            final v = await UI.pick<int>('فترة الفحص', [(15, 'كل 15 دقيقة', null), (30, 'كل 30 دقيقة', null), (60, 'كل ساعة', null), (180, 'كل 3 ساعات', null)]);
            if (v == null) return;
            await Prefs.p.setInt('bot_interval', v);
            await ServerBot.schedule();
            setState(() {});
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_rounded, color: K.gold),
          title: const Text('تنبيه انخفاض المخزون', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('عندما تقل المقاعد عن ${ServerBot.lowSeats}', style: K.tiny),
          onTap: () async {
            final v = int.tryParse(await UI.input('حد التنبيه (مقاعد)', number: true, initial: '${ServerBot.lowSeats}') ?? '');
            if (v == null || v < 0) return;
            await Prefs.p.setInt('bot_low', v);
            setState(() {});
          },
        ),
      ])),
    ]);
  }

  Widget _log() {
    final all = BotLog.read();
    final list = all.where((e) {
      final k = '${e['kind']}';
      switch (_f) {
        case 'alerts': return k == 'dead' || k == 'soon' || k == 'low' || k == 'failed' || k == 'expired';
        case 'moved': return k == 'moved' || k == 'failed';
        case 'activate': return k == 'activate';
      }
      return true;
    }).toList();
    final out = <Widget>[
      Section('سجل البوت والتفعيلات (${all.length})', trailing: all.isEmpty ? null : IconButton(
          icon: const Icon(Icons.delete_sweep_rounded, color: K.t3),
          onPressed: () async { if (await UI.confirm('مسح السجل؟', 'لن يؤثر على البيانات.')) await BotLog.clear(); })),
      Filters<String>(value: _f, onChanged: (v) => setState(() => _f = v), items: [
        ('all', 'الكل', all.length), ('alerts', 'تنبيهات', null), ('moved', 'النقل', null), ('activate', 'التفعيلات', null),
      ]),
      const SizedBox(height: 10),
    ];
    if (list.isEmpty) {
      out.add(const EmptyView(icon: Icons.history_rounded, title: 'السجل فارغ', sub: 'يظهر هنا كل ما يفعله البوت وكل تفعيل تجريه'));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
    }
    String? lastDay;
    for (final e in list.take(150)) {
      final at = DateTime.tryParse('${e['at']}');
      final day = at == null ? '' : '${at.year}-${at.month}-${at.day}';
      if (day != lastDay && at != null) {
        lastDay = day;
        out.add(Padding(padding: const EdgeInsets.fromLTRB(2, 10, 2, 6), child: Text(Fmt.dayLabel(at), style: K.sub.copyWith(fontWeight: FontWeight.w800))));
      }
      final (icon, color, tag) = _kinds['${e['kind']}'] ?? (Icons.info_rounded, K.t2, '');
      out.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 34, child: Column(children: [
          Container(width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withOpacity(.15), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color)),
          Expanded(child: Container(width: 2, color: K.line)),
        ])),
        const SizedBox(width: 10),
        Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${e['title']}', style: K.body.copyWith(fontWeight: FontWeight.w800, fontSize: 13.5))),
            Text(Fmt.time(at), style: K.tiny),
          ]),
          if ('${e['body']}'.isNotEmpty) Text('${e['body']}', style: K.sub),
          if (tag.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Pill(tag, color: color)),
        ]))),
      ])));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }
}

class _Lg extends StatelessWidget {
  final Color c;
  final String t;
  const _Lg(this.c, this.t);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 5),
    Text(t, style: K.tiny.copyWith(color: K.t2)),
  ]);
}
