part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  مخزون الحسابات المشترك (للتفعيل والاختيار اليدوي والبوت)
// ════════════════════════════════════════════════════════════════════
class StockLines {
  static List<Line> lines = [];
  static String currentHost = '';
  static DateTime? at;

  /// من المحفوظ أولاً، ويُحدَّث من القاعدة إن كان قديماً (أكثر من 3 دقائق) أو عند الطلب
  static Future<List<Line>> load({bool force = false}) async {
    if (!force && lines.isNotEmpty && at != null && DateTime.now().difference(at!).inMinutes < 3) return lines;
    if (!force && lines.isEmpty) {
      final c = await DiskCache.read('stock');
      if (c is Map) {
        _apply(Map<String, dynamic>.from(c).m('list'));
        at = await DiskCache.time('stock');
        if (at != null && DateTime.now().difference(at!).inMinutes < 3) return lines;
      }
    }
    final l = await Supa.call('admin_lines_list');
    _apply(l);
    at = DateTime.now();
    final old = await DiskCache.read('stock');
    final o = old is Map ? Map<String, dynamic>.from(old) : <String, dynamic>{};
    await DiskCache.write('stock', {'list': l, 'sum': o['sum'] ?? {}, 'impact': o['impact']});
    return lines;
  }

  static void _apply(Map<String, dynamic> l) {
    lines = l.l('lines').map((e) => Line(Map<String, dynamic>.from(e as Map))).toList();
    currentHost = l.str('current_host');
  }

  /// أنسب حساب حسب خياراتك (تجاوز السعة / مدة أقصر) — نفس منطق القاعدة لكن بمرونة
  static Line? best({required DateTime needUntil, required bool overCap, required bool shorter, String? sameUser}) {
    final now = DateTime.now();
    final c = lines.where((l) {
      if (l.disabled) return false;
      final e = l.expiry;
      if (e == null || !e.isAfter(now.add(const Duration(hours: 24)))) return false;
      if (l.host.isEmpty && currentHost.isEmpty) return false;
      if (!overCap && l.users >= l.cap) return false;
      if (!shorter && e.isBefore(needUntil)) return false;
      return true;
    }).toList();
    if (c.isEmpty) return null;
    // نفس حسابه الحالي أولاً إن كان صالحاً
    if (sameUser != null && sameUser.isNotEmpty) {
      final s = c.where((l) => l.username.toLowerCase() == sameUser.toLowerCase()).firstOrNull;
      if (s != null) return s;
    }
    c.sort((a, b) {
      final ca = !a.expiry!.isBefore(needUntil), cb = !b.expiry!.isBefore(needUntil);
      if (ca != cb) return ca ? -1 : 1;                       // يغطي المدة أولاً
      if (a.review != b.review) return a.review ? 1 : -1;      // غير المراجَع أخيراً
      final fa = a.users < a.cap, fb = b.users < b.cap;
      if (fa != fb) return fa ? -1 : 1;                        // غير الممتلئ أولاً
      final u = (a.users / a.cap).compareTo(b.users / b.cap);  // الأقل ضغطاً
      if (u != 0) return u;
      return ca ? a.expiry!.compareTo(b.expiry!) : b.expiry!.compareTo(a.expiry!);
    });
    return c.first;
  }
}

/// نافذة اختيار حساب من المخزون (لكل الحالات: متاح، ممتلئ، أقصر)
Future<Line?> pickStockLine({DateTime? needUntil, String title = 'اختر حساباً من المخزون'}) async {
  try { await StockLines.load(); } catch (e) { UI.err(e); return null; }
  final now = DateTime.now();
  final list = StockLines.lines.where((l) => !l.disabled && l.expiry != null && l.expiry!.isAfter(now)).toList()
    ..sort((a, b) {
      final fa = a.users < a.cap, fb = b.users < b.cap;
      if (fa != fb) return fa ? -1 : 1;
      return b.expiry!.compareTo(a.expiry!);
    });
  if (list.isEmpty) { UI.toast('لا توجد حسابات صالحة في المخزون — أضف حسابات أولاً', error: true); return null; }
  return UI.sheet<Line>(Builder(builder: (ctx) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    children: [
      Text(title, style: K.h2),
      const SizedBox(height: 4),
      const Text('الممتلئ يمكن اختياره (تجاوز السعة) — والأقصر يمكن اختياره (ستنقله لاحقاً)', style: K.sub),
      const SizedBox(height: 12),
      for (final l in list) () {
        final full = l.users >= l.cap;
        final short = needUntil != null && l.expiry!.isBefore(needUntil);
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: Box(
          padding: const EdgeInsets.all(12),
          border: full || short ? K.org.withOpacity(.35) : K.grn.withOpacity(.3),
          onTap: () => Navigator.pop(ctx, l),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.username, textDirection: TextDirection.ltr, style: K.mono.copyWith(fontWeight: FontWeight.w900, color: K.gold)),
              const SizedBox(height: 2),
              Text('ينتهي ${Fmt.dt(l.expiry)} · ${l.days} يوم', style: K.tiny),
              const SizedBox(height: 6),
              Row(children: [
                SizedBox(width: 90, child: Meter(l.users / l.cap, color: full ? K.org : K.grn)),
                const SizedBox(width: 8),
                Text('${l.users}/${l.cap}', style: K.tiny.copyWith(color: K.t1)),
              ]),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (full) const Pill('ممتلئ', color: K.org),
              if (short) ...[const SizedBox(height: 4), const Pill('أقصر', color: K.org)],
              if (!full && !short) const Pill('مناسب', color: K.grn),
            ]),
          ]),
        ));
      }(),
    ],
  )), initial: .85);
}

// ════════════════════════════════════════════════════════════════════
//  ⚡ التفعيل التلقائي من المخزون — مع خيارات التجاوز والاختيار اليدوي
// ════════════════════════════════════════════════════════════════════
class AutoActivateSheet extends StatefulWidget {
  final String uid, email, name;
  final int days;
  final AppOrder? order;
  final int? lineId;
  final bool quiet;   // جائزة: بلا رسالة «تم تفعيل اشتراكك» (تصله رسالة الجائزة بدلها)
  const AutoActivateSheet({super.key, required this.uid, required this.email, required this.name,
      this.days = 30, this.order, this.lineId, this.quiet = false});

  static Future<void> open({required String uid, String email = '', String name = '', int days = 30, AppOrder? order,
      int? lineId, bool quiet = false}) async {
    if (!Supa.linked.value) { UI.toast('اربط قاعدة الاشتراكات أولاً (المزيد)', error: true); return; }
    await UI.sheet(AutoActivateSheet(uid: uid, email: email, name: name, days: days, order: order, lineId: lineId,
        quiet: quiet), initial: .92);
  }

  @override State<AutoActivateSheet> createState() => _AutoActivateSheetState();
}

class _AutoActivateSheetState extends State<AutoActivateSheet> {
  late final _days = TextEditingController(text: '${widget.days}');
  bool _short = Prefs.p.getBool('aa_short') ?? false;
  bool _over = Prefs.p.getBool('aa_over') ?? false;
  bool _busy = false, _loading = false;
  int? _lineId;              // حساب محدد (يدوياً أو اختاره التطبيق عند التجاوز)
  bool _manualPick = false;  // اخترته أنت
  Map<String, dynamic>? _prev;
  String _prevErr = '';
  Map<String, dynamic>? _noStock;
  Map<String, dynamic>? _done;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _lineId = widget.lineId;
    _manualPick = widget.lineId != null;
    _preview();
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  int get _d => int.tryParse(_days.text.trim()) ?? 0;

  /// تاريخ نهاية الاشتراك المطلوب (يُضاف على المتبقي إن كان فعّالاً)
  DateTime get _needUntil {
    final s = Subs.of(widget.uid, widget.email);
    final base = s?.expiry != null && s!.expiry!.isAfter(DateTime.now()) ? s.expiry! : DateTime.now();
    return base.add(Duration(days: _d));
  }

  Map<String, dynamic> _params(bool dry, int? lineId) => {
    'p_uid': widget.uid, 'p_email': widget.email, 'p_name': widget.name, 'p_days': _d,
    'p_line_id': lineId, 'p_allow_shorter': _short, 'p_dry': dry,
  };

  void _schedule() { _t?.cancel(); _t = Timer(const Duration(milliseconds: 400), _preview); }

  Future<Map<String, dynamic>> _dry(int? lineId) async {
    final r = await Supa.rpc('admin_assign_line', _params(true, lineId));
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  Future<void> _preview() async {
    if (_d <= 0) return;
    setState(() { _loading = true; _prevErr = ''; _noStock = null; });
    try {
      Map<String, dynamic> m;
      if (_manualPick && _lineId != null) {
        m = await _dry(_lineId);
      } else {
        _lineId = null;
        m = await _dry(null);
        // لا يوجد حساب ضمن الشروط ⇐ إن سمحت بالتجاوز نختار نحن الأنسب ونمرره مباشرة
        if (m['ok'] != true && m.str('error') == 'NO_STOCK' && (_over || _short)) {
          await StockLines.load();
          final s = Subs.of(widget.uid, widget.email);
          final l = StockLines.best(needUntil: _needUntil, overCap: _over, shorter: _short, sameUser: s?.username);
          if (l != null) { _lineId = l.id; m = await _dry(l.id); }
        }
      }
      if (m['ok'] != true) {
        _prev = null;
        final e = m.str('error');
        if (e == 'NO_STOCK') {
          _noStock = m;
        } else {
          _prevErr = e == 'NO_HOST' ? 'لم تحدد «الهوست الحالي» — من صفحة المخزون' : (Supa._errAr[e] ?? e);
        }
      } else {
        _prev = m;
      }
    } catch (e) {
      _prev = null;
      _prevErr = Fmt.err(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final r = await Supa.call('admin_assign_line', _params(false, _lineId));
      final exp = r.d('expiry') ?? DateTime.now().add(Duration(days: _d));
      final host = r.str('host');
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'subscription': {
          'plan': 'premium', 'host': host, 'server_host': host,
          'username': r.str('username'), 'password': r.str('password'),
          'expiry_date': Timestamp.fromDate(exp),
          'activated_at': FieldValue.serverTimestamp(), 'updated_at': FieldValue.serverTimestamp(),
          'activated_by': Store.by, 'source': 'stock', 'days': _d,
        },
        'status': 'active', 'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      unawaited(FirebaseFirestore.instance.collection('orders').add({
        'uid': widget.uid, 'email': widget.email, 'display_name': widget.name, 'plan': 'premium', 'duration_days': _d,
        'note': 'تفعيل تلقائي — حساب #${r['line_id']}${_over ? ' (تجاوز السعة)' : ''}', 'status': 'active', 'activated_by': Store.by, 'agent': '',
        'created': FieldValue.serverTimestamp(), 'expiry_date': Timestamp.fromDate(exp),
      }).then((_) {}, onError: (e) => CrashLog.add('order log: $e')));
      if (widget.order != null) {
        await Store.markDone(widget.order!, days: _d, expiry: exp, username: r.str('username'));
      }
      if (!widget.quiet) {
        unawaited(Engage.afterActivation(uid: widget.uid, email: widget.email, name: widget.name, days: _d,
            expiry: exp, paid: widget.order != null || _d >= 28));
      }
      BotLog.add('activate', 'تفعيل ${widget.name.isEmpty ? widget.email : widget.name}',
          '$_d يوم على ${r.str('username')}${r['warning'] != null ? ' · حساب أقصر' : ''}${(_prev?.i('users_on_line') ?? 0) >= (_prev?.i('cap') ?? 99) ? ' · تجاوز السعة' : ''}');
      StockLines.at = null; // المخزون تغيّر
      HapticFeedback.heavyImpact();
      setState(() => _done = {...r, '_exp': exp});
    } catch (e) {
      UI.err(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pick() async {
    final l = await pickStockLine(needUntil: _needUntil);
    if (l == null) return;
    setState(() { _lineId = l.id; _manualPick = true; });
    _preview();
  }

  @override
  Widget build(BuildContext context) => _done != null ? _success() : ListView(
    controller: PrimaryScrollController.of(context),
    padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.of(context).viewInsets.bottom + 24),
    children: [
      const Text('⚡ تفعيل من المخزون', style: K.h2),
      const SizedBox(height: 4),
      const Text('يختار أنسب حساب سيرفر ويفعّله فوراً — أو اختر حساباً بنفسك', style: K.sub),
      const SizedBox(height: 14),
      Box(child: Row(children: [
        Avatar(widget.name.isEmpty ? widget.email : widget.name),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.name.isEmpty ? '—' : widget.name, style: K.h3),
          Text(widget.email.isEmpty ? widget.uid : widget.email, textDirection: TextDirection.ltr, style: K.tiny),
          if (Subs.of(widget.uid, widget.email)?.active == true)
            Text('مشترك حالياً — المدة تُضاف على المتبقي (${Subs.of(widget.uid, widget.email)!.daysLeft} يوم)', style: K.tiny.copyWith(color: K.grn)),
        ])),
      ])),
      if (widget.order != null) ...[
        const SizedBox(height: 10),
        Banner2('طلب من التطبيق — سيُعلَّم «مُفعَّل» تلقائياً (${widget.order!.planTitle} · ${widget.order!.method})', icon: Icons.receipt_long_rounded),
      ],
      const SizedBox(height: 16),
      const Text('المدة', style: K.h3),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(width: 110, child: TextField(
          controller: _days, keyboardType: TextInputType.number, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          decoration: const InputDecoration(suffixText: 'يوم'),
          onChanged: (_) => _schedule())),
        const SizedBox(width: 10),
        Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (d, t) in const [(30, 'شهر'), (60, 'شهرين'), (90, '3 أشهر'), (180, '6 أشهر'), (365, 'سنة')])
            ChoiceChip(label: Text(t), selected: _d == d, selectedColor: K.gold,
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: _d == d ? Colors.black : K.t1),
                onSelected: (_) { _days.text = '$d'; _preview(); }),
        ])),
      ]),
      const SizedBox(height: 10),
      Box(padding: const EdgeInsets.fromLTRB(12, 4, 12, 4), child: Column(children: [
        SwitchRow(title: 'تجاوز حد السعة', sub: 'يفعّل حتى لو امتلأ الحساب (أكثر من ${StockLines.lines.isEmpty ? 10 : StockLines.lines.first.cap} مشترك)',
            icon: Icons.group_add_rounded, color: K.org, value: _over,
            onChanged: (v) { setState(() => _over = v); Prefs.p.setBool('aa_over', v); if (!_manualPick) _preview(); }),
        const Divider(),
        SwitchRow(title: 'اشتراك أطول من صلاحية السيرفر', sub: 'يفعّل على حساب ينتهي قبل نهاية الاشتراك — البوت ينقله تلقائياً عند انتهائه',
            icon: Icons.more_time_rounded, color: K.org, value: _short,
            onChanged: (v) { setState(() => _short = v); Prefs.p.setBool('aa_short', v); _preview(); }),
      ])),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.list_alt_rounded),
            label: Text(_manualPick ? 'تغيير الحساب' : 'اختيار حساب بنفسي'))),
        if (_manualPick) ...[
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () { setState(() { _manualPick = false; _lineId = null; }); _preview(); }, child: const Text('تلقائي')),
        ],
      ]),
      const SizedBox(height: 12),
      _previewBox(),
      const SizedBox(height: 16),
      BusyButton(label: 'تفعيل الآن', icon: Icons.bolt_rounded, busy: _busy,
          onPressed: _prev == null || _loading ? null : _confirm),
    ],
  );

  Widget _previewBox() {
    if (_loading) return const Box(child: Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2.4, color: K.gold))));
    if (_prevErr.isNotEmpty) return ErrorBox(_prevErr, onRetry: _preview);
    final ns = _noStock;
    if (ns != null) {
      return Box(color: K.red.withOpacity(.06), border: K.red.withOpacity(.35), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [Icon(Icons.inventory_rounded, color: K.red), SizedBox(width: 8), Expanded(child: Text('لا يوجد حساب ضمن الشروط العادية', style: K.h3))]),
        const SizedBox(height: 6),
        Text('المطلوب حساب يبقى حتى ${Fmt.dateShort(ns.d('need_until') ?? _needUntil)} وفيه مكان.\n'
            'المتاح ضمن السعة: ${ns.i('available')} · أطولها ينتهي ${Fmt.dateShort(ns.d('best_expiry'))}', style: K.sub),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!_over) ActBtn(Icons.group_add_rounded, 'فعّل مع تجاوز السعة', () { setState(() => _over = true); _preview(); }, filled: true, color: K.gold),
          if (!_short) ActBtn(Icons.more_time_rounded, 'اسمح بحساب أقصر', () { setState(() => _short = true); _preview(); }, color: K.org),
          ActBtn(Icons.list_alt_rounded, 'اختر حساباً بنفسي', _pick),
          ActBtn(Icons.add_box_rounded, 'أضف حسابات للمخزون', () { Navigator.pop(context); Shell.go(2); }),
        ]),
      ]));
    }
    final r = _prev;
    if (r == null) return const SizedBox.shrink();
    final same = r['same_line'] == true, renew = r['renew'] == true;
    final over = r.i('users_on_line') >= r.i('cap') && !same;
    final shortW = r['warning'] == 'LINE_SHORTER';
    return Box(
      color: (over || shortW ? K.org : K.grn).withOpacity(.06), border: (over || shortW ? K.org : K.grn).withOpacity(.35),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(same ? Icons.recycling_rounded : (renew ? Icons.autorenew_rounded : Icons.fiber_new_rounded), color: K.grn),
          const SizedBox(width: 8),
          Expanded(child: Text(same ? 'تجديد على نفس حسابه — لا يحتاج تغيير شيء في جهازه'
              : (renew ? 'تجديد — سيُنقل لحساب يغطي المدة' : 'اشتراك جديد'), style: K.h3.copyWith(fontSize: 14))),
          if (_manualPick) const Pill('اخترته أنت', color: K.gold),
        ]),
        const Divider(height: 22),
        InfoRow('الحساب', '${r.str('username')}  #${r['line_id'] ?? ''}', ltr: true, color: K.gold),
        InfoRow('الهوست', r.str('host').replaceFirst('http://', ''), ltr: true),
        InfoRow('ينتهي في البنل', Fmt.dt(r.d('line_expiry'))),
        InfoRow('الضغط', '${r.i('users_on_line')} / ${r['cap'] ?? 10}${same ? '' : '  ⇐  ${r.i('users_on_line') + 1}'}', color: over ? K.org : null),
        InfoRow('اشتراكه ينتهي', Fmt.dt(r.d('expiry')), color: K.grn),
        if (over) const Padding(padding: EdgeInsets.only(top: 6), child: Text('⚠ تجاوز السعة — الحساب ممتلئ وسيُضاف عليه مشترك إضافي', style: TextStyle(color: K.org, fontSize: 12.5))),
        if (shortW) const Padding(padding: EdgeInsets.only(top: 6), child: Text('⚠ الحساب ينتهي قبل نهاية الاشتراك — البوت سينقله تلقائياً لحساب آخر عند انتهائه', style: TextStyle(color: K.org, fontSize: 12.5))),
      ]),
    );
  }

  Widget _success() {
    final r = _done!;
    final exp = r['_exp'] as DateTime;
    final msg = 'تم تفعيل اشتراكك في TOTV+ ✅\nالمدة: $_d يوم — ينتهي ${Fmt.dateShort(exp)}\nافتح التطبيق وسيعمل تلقائياً.';
    final phone = widget.order?.phone ?? '';
    return ListView(controller: PrimaryScrollController.of(context), padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), children: [
      const Center(child: Icon(Icons.verified_rounded, size: 72, color: K.grn)),
      const SizedBox(height: 10),
      Center(child: Text('تم التفعيل — $_d يوم', style: K.h2)),
      Center(child: Text(r['same_line'] == true ? 'على نفس حسابه' : 'ينتهي ${Fmt.date(exp)}', style: K.sub)),
      const SizedBox(height: 16),
      Box(child: Column(children: [
        InfoRow('المستخدم', widget.email.isEmpty ? widget.uid : widget.email, ltr: true),
        InfoRow('Host', r.str('host'), copy: true, ltr: true),
        InfoRow('Username', r.str('username'), copy: true, ltr: true),
        InfoRow('Password', r.str('password'), copy: true, ltr: true),
        InfoRow('ينتهي', Fmt.dt(exp), color: K.grn),
      ])),
      if (r['warning'] != null) ...[const SizedBox(height: 10),
        Banner2('الحساب في البنل ينتهي ${Fmt.dt(r.d('line_expiry'))} — البوت سينقله تلقائياً عند انتهائه', color: K.org, icon: Icons.warning_rounded)],
      const SizedBox(height: 16),
      if (phone.isNotEmpty) ...[
        FilledButton.icon(onPressed: () => UI.whatsapp(phone, text: msg), icon: const Icon(Icons.chat_rounded), label: const Text('إرسال رسالة للعميل (واتساب)')),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(onPressed: () => UI.copy(msg), icon: const Icon(Icons.copy_rounded), label: const Text('نسخ رسالة للعميل')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () => UI.copy('${r.str('host')}\n${r.str('username')}\n${r.str('password')}'),
          icon: const Icon(Icons.vpn_key_rounded), label: const Text('نسخ بيانات الحساب')),
      const SizedBox(height: 8),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════
//  ✍️ التفعيل اليدوي — أنت تكتب بيانات السيرفر (أو تجريبي/مجاني)
// ════════════════════════════════════════════════════════════════════
class ManualActivatePage extends StatefulWidget {
  final AppOrder? order;
  final String? uid;
  const ManualActivatePage({super.key, this.order, this.uid});
  @override State<ManualActivatePage> createState() => _ManualActivatePageState();
}

class _ManualActivatePageState extends State<ManualActivatePage> {
  final _q = TextEditingController();
  final _days = TextEditingController(text: '30');
  final _host = TextEditingController(), _user = TextEditingController(), _pass = TextEditingController();
  final _note = TextEditingController(), _agent = TextEditingController();
  Map<String, dynamic>? _u; // المستخدم المختار (id + بياناته)
  List<Map<String, dynamic>> _results = [];
  String _plan = 'premium';
  bool _busy = false, _searching = false;

  @override
  void initState() {
    super.initState();
    final o = widget.order;
    if (o != null) {
      _days.text = '${o.days}';
      if (o.method.isNotEmpty) _note.text = 'دفع عبر: ${o.method}';
      _select(o.uid);
    } else if (widget.uid != null) {
      _select(widget.uid!);
    }
    _prefillHost();
  }

  Future<void> _prefillHost() async {
    try {
      final d = await FirebaseFirestore.instance.collection('app_config').doc('remote_config').get();
      final h = '${d.data()?['server_host'] ?? d.data()?['default_server_host'] ?? ''}';
      if (_host.text.isEmpty && h.isNotEmpty) _host.text = h;
    } catch (_) {}
  }

  Future<void> _select(String uid) async {
    try {
      final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      setState(() {
        _u = {'id': uid, ...(d.data() ?? {'email': widget.order?.email ?? '', 'display_name': widget.order?.name ?? ''})};
        _results = [];
      });
    } catch (e) { UI.err(e); }
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.length < 3) { UI.toast('اكتب 3 أحرف على الأقل', error: true); return; }
    setState(() => _searching = true);
    final out = <String, Map<String, dynamic>>{};
    final users = FirebaseFirestore.instance.collection('users');
    try {
      final byId = await users.doc(q).get();
      if (byId.exists) out[byId.id] = {'id': byId.id, ...byId.data()!};
      for (final e in {q.toLowerCase(), q}) {
        final s = await users.where('email', isEqualTo: e).limit(5).get();
        for (final d in s.docs) { out[d.id] = {'id': d.id, ...d.data()}; }
      }
      if (out.isEmpty) {
        final s = await users.orderBy('display_name').startAt([q]).endAt(['$q']).limit(8).get();
        for (final d in s.docs) { out[d.id] = {'id': d.id, ...d.data()}; }
      }
    } catch (e) { CrashLog.add('user search: $e'); }
    // من قاعدة الاشتراكات (مجاني)
    final ql = q.toLowerCase();
    for (final s in Subs.list.value.where((s) => s.email.contains(ql) || s.name.toLowerCase().contains(ql)).take(8)) {
      out.putIfAbsent(s.uid, () => {'id': s.uid, 'email': s.email, 'display_name': s.name});
    }
    setState(() { _results = out.values.toList(); _searching = false; });
    if (_results.isEmpty) UI.toast('لا يوجد مستخدم — يجب أن يسجّل في التطبيق أولاً', error: true);
  }

  Future<void> _activate() async {
    final u = _u;
    if (u == null) { UI.toast('اختر مستخدماً أولاً', error: true); return; }
    final days = int.tryParse(_days.text.trim()) ?? 0;
    if (days <= 0) { UI.toast('اكتب عدد الأيام', error: true); return; }
    final uid = '${u['id']}';
    final exp = DateTime.now().add(Duration(days: days));
    final sub = <String, dynamic>{
      'plan': _plan, 'expiry_date': Timestamp.fromDate(exp),
      'activated_at': FieldValue.serverTimestamp(), 'updated_at': FieldValue.serverTimestamp(),
      'activated_by': Store.by,
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      if (_agent.text.trim().isNotEmpty) 'agent': _agent.text.trim(),
    };
    if (_plan == 'premium') {
      if (_host.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.trim().isEmpty) {
        UI.toast('أكمل Host و Username و Password', error: true); return;
      }
      sub.addAll({'host': _host.text.trim(), 'server_host': _host.text.trim(), 'username': _user.text.trim(), 'password': _pass.text.trim()});
    } else if (_plan == 'trial') {
      final rc = (await FirebaseFirestore.instance.collection('app_config').doc('remote_config').get()).data() ?? {};
      sub.addAll({'host': '${rc['default_server_host'] ?? rc['server_host'] ?? ''}', 'username': '${rc['username'] ?? ''}', 'password': '${rc['password'] ?? ''}'});
    }
    if (!await UI.confirm('تأكيد التفعيل', '${Fmt.plan(_plan)} لمدة $days يوم\n${u['display_name'] ?? ''} ${u['email'] ?? ''}')) return;
    setState(() => _busy = true);
    try {
      final fs = FirebaseFirestore.instance;
      await fs.collection('users').doc(uid).set({'subscription': sub, 'status': 'active', 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      await fs.collection('orders').add({
        'uid': uid, 'email': u['email'] ?? '', 'display_name': u['display_name'] ?? '', 'plan': _plan,
        'duration_days': days, 'note': _note.text.trim(), 'agent': _agent.text.trim(), 'status': 'active',
        'activated_by': Store.by, 'request_id': widget.order?.id, 'created': FieldValue.serverTimestamp(),
        'expiry_date': Timestamp.fromDate(exp),
      });
      // مرآة في قاعدة الاشتراكات (مكان واحد لكل المشتركين)
      if (_plan == 'premium' && Supa.linked.value) {
        try {
          await Supa.call('admin_import_manual', {'p_rows': [{
            'uid': uid, 'email': u['email'] ?? '', 'display_name': u['display_name'] ?? '',
            'host': sub['host'], 'username': sub['username'], 'password': sub['password'],
            'expiry_date': exp.toUtc().toIso8601String(), 'agent': _agent.text.trim(), 'source': 'manual', 'tier': 'manual'}]});
        } catch (e) { CrashLog.add('mirror: $e'); }
      }
      if (_agent.text.trim().isNotEmpty) {
        try {
          final ag = await fs.collection('admins').where('agent_name', isEqualTo: _agent.text.trim()).limit(1).get();
          if (ag.docs.isNotEmpty) await ag.docs.first.reference.set({'target_count': FieldValue.increment(1)}, SetOptions(merge: true));
        } catch (_) {}
      }
      final o = widget.order;
      if (o != null) {
        await fs.collection(o.col).doc(o.id).update({
          'status': o.col == 'orders' ? 'active' : 'approved', 'resolved_by': Store.by, 'resolved_at': FieldValue.serverTimestamp(),
          'activated_by': Store.by, 'duration_days': days, 'expiry_date': Timestamp.fromDate(exp),
          'applied_plan': _plan, 'applied_days': days, 'applied_agent': _agent.text.trim(),
        });
      }
      if (_plan == 'premium') {
        unawaited(Engage.afterActivation(uid: uid, email: '${u['email'] ?? ''}', name: '${u['display_name'] ?? ''}',
            days: days, expiry: exp, paid: o != null || days >= 28));
      }
      BotLog.add('activate', 'تفعيل يدوي ${u['display_name'] ?? u['email'] ?? ''}', '${Fmt.plan(_plan)} · $days يوم${_plan == 'premium' ? ' · ${sub['username']}' : ''}');
      HapticFeedback.heavyImpact();
      UI.toast('تم تفعيل ${Fmt.plan(_plan)} — $days يوم');
      if (mounted) Navigator.pop(context);
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    return Scaffold(
      appBar: AppBar(title: const Text('تفعيل يدوي')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.order != null) ...[
          Banner2('طلب ${widget.order!.name} — ${widget.order!.planTitle} · ${widget.order!.method}', icon: Icons.receipt_long_rounded),
          const SizedBox(height: 12),
        ],
        if (u == null) ...[
          const Text('1) اختر المستخدم', style: K.h3),
          const SizedBox(height: 8),
          SearchBox(controller: _q, hint: 'البريد أو UID أو بداية الاسم', onSubmitted: (_) => _search()),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _searching ? null : _search, icon: const Icon(Icons.search_rounded), label: const Text('بحث')),
          if (_searching) const Loading(),
          for (final r in _results)
            Padding(padding: const EdgeInsets.only(top: 8), child: Box(
              onTap: () => _select('${r['id']}'),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Avatar('${r['display_name'] ?? r['email'] ?? '?'}', size: 38),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['display_name'] ?? '—'}', style: K.body.copyWith(fontWeight: FontWeight.w800)),
                  Text('${r['email'] ?? r['id']}', textDirection: TextDirection.ltr, style: K.tiny),
                ])),
                const Icon(Icons.chevron_left_rounded, color: K.t3),
              ]),
            )),
        ] else ...[
          Box(child: Row(children: [
            Avatar('${u['display_name'] ?? u['email'] ?? '?'}'),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${u['display_name'] ?? '—'}', style: K.h3),
              Text('${u['email'] ?? u['id']}', textDirection: TextDirection.ltr, style: K.tiny),
              Text('الحالي: ${Fmt.plan('${(u['subscription'] as Map?)?['plan'] ?? 'free'}')}', style: K.tiny),
            ])),
            if (widget.order == null && widget.uid == null)
              TextButton(onPressed: () => setState(() => _u = null), child: const Text('تغيير')),
          ])),
          const SizedBox(height: 16),
          const Text('2) نوع الاشتراك', style: K.h3),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'premium', label: Text('بريميوم'), icon: Icon(Icons.workspace_premium_rounded)),
              ButtonSegment(value: 'trial', label: Text('تجريبي'), icon: Icon(Icons.timer_rounded)),
              ButtonSegment(value: 'free', label: Text('مجاني'), icon: Icon(Icons.person_rounded)),
            ],
            selected: {_plan},
            onSelectionChanged: (s) => setState(() => _plan = s.first),
          ),
          const SizedBox(height: 14),
          InField(_days, 'عدد الأيام', number: true, icon: Icons.calendar_month_rounded),
          Wrap(spacing: 6, children: [
            for (final (d, t) in const [(30, 'شهر'), (90, '3 أشهر'), (180, '6 أشهر'), (365, 'سنة')])
              ActionChip(label: Text(t), onPressed: () => setState(() => _days.text = '$d')),
          ]),
          const SizedBox(height: 14),
          if (_plan == 'premium') ...[
            const Text('3) بيانات السيرفر', style: K.h3),
            const SizedBox(height: 8),
            InField(_host, 'Host', ltr: true, hint: 'http://server.com:8080', icon: Icons.dns_rounded),
            InField(_user, 'Username', ltr: true, icon: Icons.person_rounded),
            InField(_pass, 'Password', ltr: true, icon: Icons.key_rounded),
            OutlinedButton.icon(
              onPressed: () async {
                final l = await pickStockLine(title: 'تعبئة البيانات من حساب في المخزون');
                if (l == null) return;
                setState(() {
                  _host.text = l.host.isEmpty ? StockLines.currentHost : l.host;
                  _user.text = l.username;
                  _pass.text = l.password;
                });
                if (l.users >= l.cap) UI.toast('تنبيه: هذا الحساب ممتلئ (${l.users}/${l.cap}) — سيتجاوز السعة', error: true);
              },
              icon: const Icon(Icons.inventory_2_rounded), label: const Text('تعبئة من المخزون')),
            const SizedBox(height: 6),
            Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await AutoActivateSheet.open(uid: '${u['id']}', email: '${u['email'] ?? ''}', name: '${u['display_name'] ?? ''}',
                    days: int.tryParse(_days.text) ?? 30, order: widget.order);
              },
              icon: const Icon(Icons.auto_awesome_rounded), label: const Text('أو اختر حساباً تلقائياً من المخزون'))),
          ],
          InField(_note, 'ملاحظة (اختياري)', icon: Icons.sticky_note_2_rounded),
          InField(_agent, 'اسم الوكيل (اختياري)', icon: Icons.badge_rounded),
        ],
      ]),
      bottomNavigationBar: u == null ? null : BottomAction(
          child: BusyButton(label: 'تفعيل الآن', icon: Icons.bolt_rounded, busy: _busy, onPressed: _activate)),
    );
  }
}
