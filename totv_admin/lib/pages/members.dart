part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  👥 المشتركون — من قاعدة الاشتراكات (مجانية) + Firestore عند الحاجة فقط
// ════════════════════════════════════════════════════════════════════
class MembersPage extends StatefulWidget {
  const MembersPage({super.key});
  static final filter = Live<String>('active');
  @override State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();
  bool _busy = false;
  // فلاتر Firestore (تُقرأ عند الطلب فقط)
  List<Map<String, dynamic>> _fsRows = [];
  DocumentSnapshot? _cursor;
  bool _fsMore = false, _fsLoading = false;
  String _fsFor = '';
  List<Map<String, dynamic>> _found = [];
  bool _searching = false;

  static const _supaFilters = {'all', 'active', 'exp7', 'expired', 'code', 'manual'};

  @override bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    MembersPage.filter.addListener(_onFilter);
    Subs.loadCached().then((_) { if (Subs.list.value.isEmpty && Supa.linked.value) _refresh(); });
  }

  @override
  void dispose() { MembersPage.filter.removeListener(_onFilter); super.dispose(); }

  void _onFilter() {
    if (!mounted) return;
    setState(() {});
    if (!_supaFilters.contains(MembersPage.filter.value)) _loadFs(reset: true);
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await Subs.refresh();
      if (!_supaFilters.contains(MembersPage.filter.value)) await _loadFs(reset: true);
      HapticFeedback.lightImpact();
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  Query<Map<String, dynamic>> _fsQuery(String f) {
    final u = FirebaseFirestore.instance.collection('users');
    final day = DateTime.now();
    switch (f) {
      case 'today': return u.where('last_seen', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(day.year, day.month, day.day))).orderBy('last_seen', descending: true);
      case 'new': return u.orderBy('created_at', descending: true);
      case 'banned': return u.where('status', isEqualTo: 'banned');
      case 'trial': return u.where('subscription.plan', isEqualTo: 'trial');
      case 'free': return u.where('subscription.plan', isEqualTo: 'free');
      default: return u.orderBy('last_seen', descending: true);
    }
  }

  Future<void> _loadFs({bool reset = false}) async {
    final f = MembersPage.filter.value;
    if (_fsLoading) return;
    if (reset) { _fsRows = []; _cursor = null; }
    setState(() { _fsLoading = true; _fsFor = f; });
    try {
      var q = _fsQuery(f).limit(50);
      if (!reset && _cursor != null) q = q.startAfterDocument(_cursor!);
      final s = await q.get();
      _fsRows = [..._fsRows, ...s.docs.map((d) => {'id': d.id, ...d.data()})];
      _cursor = s.docs.isEmpty ? _cursor : s.docs.last;
      _fsMore = s.docs.length == 50;
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _fsLoading = false);
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.length < 3) { setState(() => _found = []); return; }
    setState(() => _searching = true);
    final out = <String, Map<String, dynamic>>{};
    final ql = q.toLowerCase();
    // 1) قاعدة الاشتراكات المحفوظة (مجاني وفوري)
    for (final s in Subs.list.value) {
      if ([s.email, s.name, s.uid, s.username, s.code].any((v) => v.toLowerCase().contains(ql))) {
        out[s.uid] = {'id': s.uid, 'email': s.email, 'display_name': s.name, '_sub': s};
        if (out.length > 40) break;
      }
    }
    // 2) Firestore: بريد مطابق أو UID (قراءات قليلة جداً)
    try {
      final users = FirebaseFirestore.instance.collection('users');
      final d = await users.doc(q).get();
      if (d.exists) out[d.id] = {'id': d.id, ...d.data()!};
      for (final e in {ql, q}) {
        final s = await users.where('email', isEqualTo: e).limit(3).get();
        for (final x in s.docs) { out[x.id] = {'id': x.id, ...x.data()}; }
      }
    } catch (_) {}
    if (mounted) setState(() { _found = out.values.toList(); _searching = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<String>(
      valueListenable: MembersPage.filter,
      builder: (_, f, __) => ValueListenableBuilder<List<Sub>>(
        valueListenable: Subs.list,
        builder: (_, subs, __) {
          final isSupa = _supaFilters.contains(f);
          final active = subs.where((s) => s.active).toList();
          final exp7 = active.where((s) => (s.daysLeft ?? 99) <= 7).length;
          List<Sub> rows = [];
          if (isSupa) {
            rows = subs.where((s) {
              switch (f) {
                case 'active': return s.active;
                case 'exp7': return s.active && (s.daysLeft ?? 99) <= 7;
                case 'expired': return !s.active;
                case 'code': return s.active && s.source == 'code';
                case 'manual': return s.active && s.source != 'code';
              }
              return true;
            }).toList()
              ..sort((a, b) => f == 'expired'
                  ? (b.expiry ?? DateTime(2000)).compareTo(a.expiry ?? DateTime(2000))
                  : (a.expiry ?? DateTime(2100)).compareTo(b.expiry ?? DateTime(2100)));
          }
          final searching = _q.text.trim().length >= 3;
          return RefreshIndicator(
            color: K.gold, backgroundColor: K.card, onRefresh: _refresh,
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: PageHeader('المشتركون',
                  sub: Subs.at == null ? 'من قاعدة الاشتراكات' : 'محفوظ · محدَّث ${Fmt.ago(Subs.at)}',
                  actions: [IconButton(onPressed: _busy ? null : _refresh, icon: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: K.gold))
                      : const Icon(Icons.refresh_rounded, size: 28))])),
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                KpiGrid(columns: 3, children: [
                  Kpi(label: 'فعّال', value: Fmt.n(active.length), icon: Icons.workspace_premium_rounded, color: K.grn,
                      onTap: () => MembersPage.filter.value = 'active'),
                  Kpi(label: 'ينتهي ≤7 أيام', value: Fmt.n(exp7), icon: Icons.timer_rounded, color: K.org,
                      onTap: () => MembersPage.filter.value = 'exp7'),
                  Kpi(label: 'منتهٍ', value: Fmt.n(subs.length - active.length), icon: Icons.history_toggle_off_rounded, color: K.red,
                      onTap: () => MembersPage.filter.value = 'expired'),
                ]),
                SearchBox(controller: _q, hint: 'بحث: بريد، اسم، UID، يوزر سيرفر، كود',
                    onChanged: (_) => setState(() {}), onSubmitted: (_) => _search()),
                if (searching) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton.icon(
                    onPressed: _searching ? null : _search, icon: const Icon(Icons.search_rounded), label: const Text('بحث'))),
                const SizedBox(height: 10),
                if (!searching) Filters<String>(value: f, onChanged: (v) => MembersPage.filter.value = v, items: [
                  ('active', 'فعّال', null), ('exp7', 'ينتهي قريباً', null), ('expired', 'منتهٍ', null),
                  ('code', 'عبر كود', null), ('manual', 'تفعيل أدمن', null), ('all', 'كل الاشتراكات', null),
                  ('today', 'نشط اليوم', null), ('new', 'الجدد', null), ('free', 'مجانيون', null),
                  ('trial', 'تجريبي', null), ('banned', 'محظورون', null),
                ]),
                const SizedBox(height: 8),
              ]))),
              if (searching) ...[
                if (_searching) const SliverToBoxAdapter(child: Loading())
                else if (_found.isEmpty) const SliverToBoxAdapter(child: EmptyView(icon: Icons.search_off_rounded, title: 'اضغط «بحث» للبحث', sub: 'يبحث في قاعدة الاشتراكات المحفوظة ثم Firestore'))
                else SliverList.builder(itemCount: _found.length, itemBuilder: (_, i) {
                  final m = _found[i];
                  final s = m['_sub'] as Sub? ?? Subs.of('${m['id']}', '${m['email'] ?? ''}');
                  return _tile('${m['id']}', '${m['display_name'] ?? ''}', '${m['email'] ?? ''}', s, m);
                }),
              ] else if (isSupa) ...[
                if (!Supa.linked.value) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Banner2('اربط قاعدة الاشتراكات لعرض المشتركين',
                    color: K.red, icon: Icons.link_off_rounded, action: TextButton(onPressed: linkSupabase, child: const Text('ربط')))))
                else if (rows.isEmpty) SliverToBoxAdapter(child: EmptyView(title: subs.isEmpty ? 'اسحب للأسفل لتحميل المشتركين' : 'لا أحد هنا'))
                else SliverList.builder(itemCount: rows.length, itemBuilder: (_, i) {
                  final s = rows[i];
                  return _tile(s.uid, s.name, s.email, s, null);
                }),
              ] else ...[
                if (_fsRows.isEmpty && _fsLoading) const SliverToBoxAdapter(child: Loading())
                else if (_fsRows.isEmpty) SliverToBoxAdapter(child: EmptyView(title: _fsFor == f ? 'لا أحد هنا' : 'جاري التحميل…'))
                else SliverList.builder(itemCount: _fsRows.length + (_fsMore ? 1 : 0), itemBuilder: (_, i) {
                  if (i == _fsRows.length) {
                    return Padding(padding: const EdgeInsets.all(16), child: OutlinedButton(
                        onPressed: _fsLoading ? null : () => _loadFs(), child: const Text('عرض 50 أخرى')));
                  }
                  final m = _fsRows[i];
                  return _tile('${m['id']}', '${m['display_name'] ?? ''}', '${m['email'] ?? ''}', Subs.of('${m['id']}', '${m['email'] ?? ''}'), m);
                }),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ]),
          );
        },
      ),
    );
  }

  Widget _tile(String uid, String name, String email, Sub? s, Map<String, dynamic>? fs) {
    final banned = fs?['status'] == 'banned';
    final fsSub = fs == null ? <String, dynamic>{} : Map<String, dynamic>.from((fs['subscription'] as Map?) ?? {});
    final d = s?.daysLeft;
    String label; Color c;
    if (banned) { label = 'محظور'; c = K.red; }
    else if (s != null && s.active) { label = '${d ?? '—'} يوم'; c = (d ?? 99) <= 3 ? K.red : ((d ?? 99) <= 7 ? K.org : K.grn); }
    else if (s != null) { label = 'منتهٍ'; c = K.t3; }
    else if (fsSub['plan'] == 'trial') { label = 'تجريبي'; c = K.cyn; }
    else if (fsSub['plan'] == 'premium') { label = 'بريميوم'; c = K.gold; }
    else { label = 'مجاني'; c = K.t3; }
    final fw = fs == null ? null : (fs['free_watch'] as Map?);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Box(
        padding: const EdgeInsets.all(12),
        onTap: () => Nav.push(MemberPage(uid: uid, email: email)),
        child: Row(children: [
          Avatar(name.isEmpty ? email : name, size: 42),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? (email.isEmpty ? uid : email) : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: K.body.copyWith(fontWeight: FontWeight.w800)),
            Text(email.isEmpty ? uid : email, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: K.tiny),
            if (s != null) Text('${Fmt.srcAr[s.source] ?? s.source}${s.username.isNotEmpty ? ' · ${s.username}' : ''}${s.renews > 0 ? ' · جدّد ${s.renews}' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: K.tiny.copyWith(color: K.t2)),
            if (fw != null && fw['used_ms'] != null)
              Text('شاهد مجاناً اليوم ${((fw['used_ms'] as num) / 60000).round()} د', style: K.tiny),
          ])),
          Pill(label, color: c),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  👤 ملف المشترك الكامل + كل الإجراءات
// ════════════════════════════════════════════════════════════════════
class MemberPage extends StatefulWidget {
  final String uid, email;
  const MemberPage({super.key, required this.uid, this.email = ''});
  @override State<MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends State<MemberPage> {
  Map<String, dynamic>? _u;     // Firestore
  Map<String, dynamic>? _sub;   // قاعدة الاشتراكات
  List<Map<String, dynamic>> _codes = [];
  bool _loading = true;
  String _uid = '';

  @override
  void initState() { super.initState(); _uid = widget.uid; _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = FirebaseFirestore.instance.collection('users');
    try {
      if (_uid.isNotEmpty) {
        final d = await users.doc(_uid).get();
        if (d.exists) _u = d.data();
      }
      if (_u == null && widget.email.isNotEmpty) {
        final s = await users.where('email', isEqualTo: widget.email.toLowerCase()).limit(1).get();
        if (s.docs.isNotEmpty) { _uid = s.docs.first.id; _u = s.docs.first.data(); }
      }
    } catch (e) { CrashLog.add('member fs: $e'); }
    if (Supa.linked.value) {
      try {
        final email = (widget.email.isNotEmpty ? widget.email : '${_u?['email'] ?? ''}').toLowerCase();
        var r = await Supa.call('admin_lookup', {'p_email': email.isNotEmpty ? email : _uid});
        if (r['subscription'] == null && _uid.isNotEmpty && email.isNotEmpty) r = await Supa.call('admin_lookup', {'p_email': _uid});
        if (r['subscription'] is Map) _sub = Map<String, dynamic>.from(r['subscription'] as Map);
        _codes = r.l('codes').map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (_uid.isEmpty && _sub != null) _uid = _sub!.str('uid');
      } catch (e) { CrashLog.add('lookup: $e'); }
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic> get _fs => Map<String, dynamic>.from((_u?['subscription'] as Map?) ?? {});
  String get _email => (widget.email.isNotEmpty ? widget.email : '${_u?['email'] ?? _sub?['email'] ?? ''}');
  String get _name => '${_u?['display_name'] ?? _sub?['display_name'] ?? ''}';
  String get _phone => '${_u?['phone'] ?? _u?['phone_number'] ?? ''}';

  Future<void> _extend() async {
    if (_sub == null) { UI.toast('ليس له اشتراك في قاعدة الاشتراكات — استخدم «تفعيل»', error: true); return; }
    final v = await UI.input('تمديد الاشتراك', number: true, initial: '30', help: 'عدد الأيام (رقم سالب للخصم)', ok: 'تمديد');
    final n = int.tryParse(v ?? '');
    if (n == null || n == 0) return;
    try {
      final r = await Supa.call('admin_extend', {'p_uid': _sub!.str('uid'), 'p_days': n});
      final exp = r.d('expiry');
      if (exp != null && _uid.isNotEmpty && _u != null) {
        await FirebaseFirestore.instance.collection('users').doc(_uid).set({
          'subscription': {'expiry_date': Timestamp.fromDate(exp), 'updated_at': FieldValue.serverTimestamp()},
          'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
      UI.toast('التاريخ الجديد: ${Fmt.date(exp)}');
      unawaited(Subs.refresh().catchError((_) {}));
      _load();
    } catch (e) { UI.err(e); }
  }

  Future<void> _suspend() async {
    if (!await UI.confirm('إيقاف الاشتراك؟', 'سيتوقف البث عند المستخدم فوراً.', danger: true, ok: 'إيقاف')) return;
    try {
      if (_uid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(_uid).update({
          'subscription.plan': 'free', 'subscription.host': FieldValue.delete(), 'subscription.username': FieldValue.delete(),
          'subscription.password': FieldValue.delete(), 'subscription.expiry_date': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp()});
      }
      if (Supa.linked.value && _uid.isNotEmpty) { try { await Supa.call('admin_revoke', {'p_uid': _uid}); } catch (e) { CrashLog.add('revoke: $e'); } }
      UI.toast('أُوقف الاشتراك');
      unawaited(Subs.refresh().catchError((_) {}));
      _load();
    } catch (e) { UI.err(e); }
  }

  /// نقل المشترك إلى حساب سيرفر آخر من المخزون (بدون تغيير تاريخ انتهائه)
  Future<void> _moveLine(DateTime? exp) async {
    if (_uid.isEmpty) return;
    final l = await pickStockLine(needUntil: exp, title: 'نقل ${_name.isEmpty ? _email : _name} إلى حساب آخر');
    if (l == null) return;
    final host = l.host.isEmpty ? StockLines.currentHost : l.host;
    if (host.isEmpty) { UI.toast('حدّد الهوست الحالي من صفحة المخزون', error: true); return; }
    if (!await UI.confirm('نقل إلى ${l.username}؟', 'الحساب عليه ${l.users}/${l.cap} مشترك${l.users >= l.cap ? ' (تجاوز السعة)' : ''}.\nيبقى تاريخ انتهاء اشتراكه كما هو.')) return;
    try {
      // القاعدة تحدّث البيانات فقط إن كان التاريخ الجديد أحدث — دقيقة واحدة تكفي (لا تُحسب تجديداً)
      final e = (exp ?? DateTime.now().add(const Duration(days: 30))).add(const Duration(minutes: 1));
      await Supa.call('admin_import_manual', {'p_rows': [{
        'uid': _uid, 'email': _email, 'display_name': _name, 'host': host, 'username': l.username, 'password': l.password,
        'expiry_date': e.toUtc().toIso8601String(), 'source': _sub?.str('source').isNotEmpty == true ? _sub!.str('source') : 'manual',
        'tier': _sub?.str('tier').isNotEmpty == true ? _sub!.str('tier') : 'manual'}]});
      await FirebaseFirestore.instance.collection('users').doc(_uid).set({'subscription': {
        'host': host, 'server_host': host, 'username': l.username, 'password': l.password, 'updated_at': FieldValue.serverTimestamp()},
        'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      BotLog.add('moved', 'نقل ${_name.isEmpty ? _email : _name}', 'إلى ${l.username} (يدوي)');
      StockLines.at = null;
      UI.toast('نُقل إلى ${l.username} ✅');
      unawaited(Subs.refresh().catchError((_) {}));
      _load();
    } catch (e) { UI.err(e); }
  }

  Future<void> _ban() async {
    final banned = _u?['status'] == 'banned';
    if (!await UI.confirm(banned ? 'رفع الحظر؟' : 'حظر المستخدم؟', banned ? 'سيعود للتطبيق.' : 'لن يستطيع استخدام التطبيق.', danger: !banned)) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({'status': banned ? 'active' : 'banned', 'updated_at': FieldValue.serverTimestamp()});
      UI.toast(banned ? 'رُفع الحظر' : 'تم الحظر');
      _load();
    } catch (e) { UI.err(e); }
  }

  Future<void> _resetFree() async {
    final t = DateTime.now();
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'free_watch.used_ms': 0, 'free_watch.date': '${t.year}-${Fmt.two(t.month)}-${Fmt.two(t.day)}', 'updated_at': FieldValue.serverTimestamp()});
      UI.toast('أُعيد ضبط الوقت المجاني');
      _load();
    } catch (e) { UI.err(e); }
  }

  @override
  Widget build(BuildContext context) {
    final f = _fs;
    final sExp = _sub?.d('expiry_date'), fExp = f.d('expiry_date');
    final exp = [sExp, fExp].whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final days = Fmt.daysLeft(exp);
    final banned = _u?['status'] == 'banned';
    final active = !banned && exp != null && exp.isAfter(DateTime.now());
    final host = _sub?.str('host').isNotEmpty == true ? _sub!.str('host') : (f.str('host').isNotEmpty ? f.str('host') : f.str('server_host'));
    final user = _sub?.str('username').isNotEmpty == true ? _sub!.str('username') : f.str('username');
    final pass = _sub?.str('password').isNotEmpty == true ? _sub!.str('password') : f.str('password');
    final mates = user.isEmpty ? <Sub>[] : Subs.list.value.where((s) => s.active && s.uid != _uid && s.username.toLowerCase() == user.toLowerCase()).toList();
    final firstAt = _sub?.d('first_activated_at') ?? _sub?.d('activated_at');
    final tenure = firstAt == null ? null : DateTime.now().difference(firstAt).inDays;
    final status = banned ? ('محظور', K.red) : active ? ('فعّال', K.grn) : (exp != null ? ('منتهٍ', K.t3) : (f['plan'] == 'trial' ? ('تجريبي', K.cyn) : ('مجاني', K.t3)));

    return Scaffold(
      appBar: AppBar(title: const Text('ملف المشترك'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading ? const Loading(text: 'جاري جمع كل بيانات المشترك…') : ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Avatar(_name.isEmpty ? _email : _name, size: 60),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name.isEmpty ? '—' : _name, style: K.h2),
            Text(_email.isEmpty ? _uid : _email, textDirection: TextDirection.ltr, style: K.sub),
          ])),
          Pill(status.$1, color: status.$2),
        ]),
        const SizedBox(height: 16),
        KpiGrid(columns: 4, children: [
          _mini(active && days != null ? '$days' : '—', 'يوم متبقٍ', K.gold),
          _mini(tenure == null ? '—' : '$tenure', 'يوم معنا', K.cyn),
          _mini('${_sub?.i('renew_count') ?? 0}', 'تجديد', K.grn),
          _mini('${_codes.length}', 'كود', K.blu),
        ]),
        if (sExp != null && fExp != null && sExp.difference(fExp).inDays.abs() > 2)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Banner2(
              'تعارض: Firestore ينتهي ${Fmt.dt(fExp)} وقاعدة الاشتراكات ${Fmt.dt(sExp)}', color: K.org, icon: Icons.sync_problem_rounded)),
        if (mates.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Box(
          onTap: () => Nav.push(LineWhoPage(user)),
          child: Row(children: [
            const Icon(Icons.groups_rounded, color: K.gold),
            const SizedBox(width: 10),
            Expanded(child: Text('معه على نفس يوزر السيرفر ${mates.length} مشترك — اضغط للسجل الكامل', style: K.sub.copyWith(color: K.t1))),
          ]))),
        const Section('📡 حساب البث (Xtream)', padding: EdgeInsets.fromLTRB(2, 4, 2, 8)),
        Box(child: user.isEmpty ? const Text('لا يوجد حساب', style: K.sub) : Column(children: [
          InfoRow('Host', host, copy: true, ltr: true),
          InfoRow('Username', user, copy: true, ltr: true, color: K.gold),
          InfoRow('Password', pass.isEmpty ? '(مخفي)' : pass, copy: pass.isNotEmpty, ltr: true),
          InfoRow('ينتهي', Fmt.dt(exp), color: active ? K.grn : K.red),
        ])),
        const Section('🗂 التفاصيل'),
        Box(child: Column(children: [
          if (_sub != null) ...[
            InfoRow('المصدر', Fmt.srcAr[_sub!.str('source')] ?? (_sub!.str('code').isNotEmpty ? 'كود' : 'يدوي')),
            InfoRow('الباقة', Fmt.plan(_sub!.str('tier'))),
            if (_sub!.str('code').isNotEmpty) InfoRow('الكود', _sub!.str('code'), copy: true, ltr: true),
            InfoRow('أول تفعيل', Fmt.dt(firstAt)),
            if (_sub!.str('platform').isNotEmpty) InfoRow('الجهاز', '${_sub!.str('platform')} ${_sub!.str('app_version')}'),
          ],
          if (_u != null) ...[
            InfoRow('الخطة (Firestore)', Fmt.plan(f.str('plan').isEmpty ? 'free' : f.str('plan'))),
            if (f.str('activated_by').isNotEmpty) InfoRow('فعّله', f.str('activated_by'), ltr: true),
            if (f.str('agent').isNotEmpty) InfoRow('الوكيل', f.str('agent')),
            if (_phone.isNotEmpty) InfoRow('الهاتف', _phone, copy: true, ltr: true),
            InfoRow('آخر ظهور', Fmt.ago(Fmt.toDate(_u!['last_seen']))),
            if ('${_u!['platform'] ?? ''}'.isNotEmpty) InfoRow('المنصّة', '${_u!['platform']} ${_u!['app_version'] ?? ''}'),
          ],
          InfoRow('UID', _uid, copy: true, ltr: true),
        ])),
        if (_codes.isNotEmpty) ...[
          const Section('🔑 الأكواد التي استخدمها'),
          for (final c in _codes) Padding(padding: const EdgeInsets.only(bottom: 8), child: Box(
            padding: const EdgeInsets.all(12), onTap: () => UI.copy(c.str('code')),
            child: Row(children: [
              Text(c.str('code'), style: K.mono.copyWith(color: K.gold)),
              const Spacer(),
              Text('${Fmt.plan(c.str('plan'))} · ${c.i('days')}ي · ${Fmt.dateShort(c.d('used_at'))}', style: K.tiny),
            ]))),
        ],
        const Section('⚙ الإجراءات'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_uid.isNotEmpty) ActBtn(Icons.auto_awesome_rounded, 'تفعيل/تجديد تلقائي', () async {
            await AutoActivateSheet.open(uid: _uid, email: _email, name: _name);
            _load();
          }, filled: true, color: K.gold),
          if (_sub != null) ActBtn(Icons.more_time_rounded, 'تمديد', _extend, color: K.grn),
          if (_uid.isNotEmpty && user.isNotEmpty) ActBtn(Icons.swap_horiz_rounded, 'نقل لحساب آخر', () => _moveLine(exp), color: K.blu),
          if (user.isNotEmpty) ActBtn(Icons.vpn_key_rounded, 'نسخ بيانات الحساب', () => UI.copy('$host\n$user\n$pass')),
          if (_uid.isNotEmpty) ActBtn(Icons.edit_rounded, 'تفعيل يدوي', () async { await Nav.push(ManualActivatePage(uid: _uid)); _load(); }),
          if (_uid.isNotEmpty) ActBtn(Icons.forum_rounded, 'محادثة', () => Nav.push(ChatRoomPage(uid: _uid, email: _email, name: _name)),
              filled: true, color: Colors.white),
          if (_phone.isNotEmpty) ActBtn(Icons.chat_rounded, 'واتساب', () => UI.whatsapp(_phone), color: K.grn),
          if (_uid.isNotEmpty && _u != null) ActBtn(Icons.restart_alt_rounded, 'إعادة الوقت المجاني', _resetFree),
          if (_uid.isNotEmpty && (active || user.isNotEmpty)) ActBtn(Icons.pause_circle_rounded, 'إيقاف الاشتراك', _suspend, color: K.org),
          if (_uid.isNotEmpty && _u != null) ActBtn(banned ? Icons.lock_open_rounded : Icons.block_rounded, banned ? 'رفع الحظر' : 'حظر', _ban, color: K.red),
        ]),
        const SizedBox(height: 30),
      ]),
    );
  }

  Widget _mini(String v, String l, Color c) => Box(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
    child: Column(children: [
      Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c)),
      const SizedBox(height: 2),
      Text(l, style: K.tiny, textAlign: TextAlign.center),
    ]),
  );
}
