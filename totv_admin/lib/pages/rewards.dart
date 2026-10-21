part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🏆 الجوائز: التوقعات والدعوات
//  • النتائج: اكتب نتيجة المباراة بعد نهايتها ⇐ يُحدَّد الفائزون وتصلهم رسالة
//  • الفائزون: النتيجة الدقيقة = يوم مجاني (تمديد أو تفعيل من المخزون)
//  • الدعوات: صديق اشترك بكود الدعوة ⇐ 16 يوماً للداعي
// ════════════════════════════════════════════════════════════════════
class RewardsPage extends StatefulWidget {
  final int initialTab;
  const RewardsPage({super.key, this.initialTab = 0});
  @override State<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends State<RewardsPage> {
  Map<String, dynamic> _d = {};
  List<Map<String, dynamic>> _feedMatches = [];
  bool _loading = true;
  String _err = '';
  final Set<String> _busy = {};

  List<Map<String, dynamic>> _rows(String k) => _d.l(k).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    DiskCache.read('rewards').then((c) { if (mounted && c is Map && _d.isEmpty) setState(() => _d = Map<String, dynamic>.from(c)); });
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = ''; });
    try {
      final r = await Engage.call('admin_rewards');
      _d = r;
      await DiskCache.write('rewards', r);
    } catch (e) { _err = Fmt.err(e); }
    try { _feedMatches = await _loadFeed(); } catch (e) { CrashLog.add('rewards feed: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  Future<List<Map<String, dynamic>>> _loadFeed() async {
    final rc = await FirebaseFirestore.instance.collection('app_config').doc('remote_config').get();
    final feed = '${rc.data()?['sports_feed'] ?? ''}'.trim().replaceAll(RegExp(r'/+$'), '');
    if (feed.isEmpty) return [];
    final r = await Net.req('GET', '$feed/matches.json?r=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
    if (!r.ok || r.body is! Map) return [];
    final j = Map<String, dynamic>.from(r.body as Map);
    final lg = j.m('leagues');
    return j.l('matches').map((e) => Map<String, dynamic>.from(e as Map)).map((m) {
      m['_lg'] = lg.m('${m['lg']}').str('ar');
      return m;
    }).toList();
  }

  String _team(Map<String, dynamic> m, String side) {
    final t = m.m(side);
    return t.str('ar').isNotEmpty ? t.str('ar') : t.str('n');
  }

  @override
  Widget build(BuildContext context) {
    final st = _d.m('stats');
    final winners = _rows('winners'), refs = _rows('referrals'), results = _rows('results');
    final pendingWin = winners.where((w) => !w.b('rewarded')).length;
    final pendingRef = refs.where((r) => r.str('status') == 'subscribed').length;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الجوائز والتوقعات'),
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
          bottom: TabBar(
            indicatorColor: K.gold, labelColor: K.t1, unselectedLabelColor: K.t3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            tabs: [
              const Tab(text: 'النتائج'),
              Tab(text: pendingWin > 0 ? 'الفائزون ($pendingWin)' : 'الفائزون'),
              Tab(text: pendingRef > 0 ? 'الدعوات ($pendingRef)' : 'الدعوات'),
            ],
          ),
        ),
        body: Column(children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2, color: K.gold, backgroundColor: Colors.transparent),
          if (_err.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: ErrorBox(_err, onRetry: _load)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: KpiGrid(columns: 4, children: [
              _mini('${st.i('predictions')}', 'توقع', K.blu),
              _mini('${st.i('players')}', 'مشارك', K.cyn),
              _mini('${st.i('won')}', 'فائز', K.gold),
              _mini('${st.i('ref_subs')}', 'دعوة ناجحة', K.grn),
            ]),
          ),
          Expanded(child: TabBarView(children: [
            _resultsTab(results),
            _winnersTab(winners),
            _refsTab(refs),
          ])),
        ]),
      ),
    );
  }

  Widget _mini(String v, String l, Color c) => Box(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Column(children: [
      Text(v, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: c)),
      Text(l, style: K.tiny, textAlign: TextAlign.center),
    ]),
  );

  // ── النتائج ──────────────────────────────────────────────────────
  Widget _resultsTab(List<Map<String, dynamic>> results) {
    final done = {for (final r in results) r.i('match_id')};
    final now = DateTime.now();
    final toSettle = _feedMatches.where((m) {
      final k = DateTime.fromMillisecondsSinceEpoch(m.i('ts') * 1000);
      final off = const {'PST', 'CANC', 'ABD', 'AWD', 'WO'}.contains(m.str('st'));
      return !off && !done.contains(m.i('id')) && k.isBefore(now.subtract(const Duration(minutes: 100)));
    }).toList()..sort((a, b) => b.i('ts').compareTo(a.i('ts')));
    return RefreshIndicator(
      color: K.gold, onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Banner2('بعد نهاية المباراة اكتب النتيجة النهائية ⇐ يُحدَّد أصحاب التوقع الدقيق وتصلهم رسالة «فزت بيوم مجاني» ثم امنحهم الجائزة من «الفائزون».',
            icon: Icons.info_outline_rounded),
        const SizedBox(height: 10),
        if (toSettle.isEmpty)
          const EmptyView(icon: Icons.sports_score_rounded, title: 'لا مباريات منتهية بانتظار النتيجة',
              sub: 'تظهر هنا المباريات بعد انتهائها (من جدول المباريات)')
        else ...[
          const Section('بانتظار النتيجة', padding: EdgeInsets.fromLTRB(2, 4, 2, 8)),
          for (final m in toSettle.take(40)) _settleCard(m),
        ],
        if (results.isNotEmpty) ...[
          const Section('نتائج مُعلنة'),
          for (final r in results) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Box(padding: const EdgeInsets.all(12), child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r.str('home_name')}  ${r.i('home_goals')} - ${r.i('away_goals')}  ${r.str('away_name')}', style: K.h3),
                Text('${r.str('league')} · ${Fmt.dt(r.d('kickoff'))}', style: K.tiny),
              ])),
              Pill('${r.i('winners')}/${r.i('total')} فائز', color: r.i('winners') > 0 ? K.gold : K.t3),
              IconButton(
                tooltip: 'تعديل النتيجة',
                onPressed: () => _settle({'id': r.i('match_id'), 'ts': (r.d('kickoff')?.millisecondsSinceEpoch ?? 0) ~/ 1000,
                  'h': {'ar': r.str('home_name')}, 'a': {'ar': r.str('away_name')}, '_lg': r.str('league'),
                  'gh': r.i('home_goals'), 'ga': r.i('away_goals')}),
                icon: const Icon(Icons.edit_rounded, size: 20, color: K.t2)),
            ])),
          ),
        ],
      ]),
    );
  }

  Widget _settleCard(Map<String, dynamic> m) {
    final k = DateTime.fromMillisecondsSinceEpoch(m.i('ts') * 1000);
    final hasScore = m['gh'] != null && m['ga'] != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Box(
        padding: const EdgeInsets.all(12),
        onTap: () => _settle(m),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_team(m, 'h')} × ${_team(m, 'a')}', style: K.h3),
            Text('${m.str('_lg')} · ${Fmt.dt(k)}${hasScore ? ' · النتيجة من الجدول: ${m.i('gh')}-${m.i('ga')}' : ''}', style: K.tiny),
          ])),
          const SizedBox(width: 8),
          ActBtn(Icons.scoreboard_rounded, 'النتيجة', () => _settle(m), color: K.gold),
        ]),
      ),
    );
  }

  Future<void> _settle(Map<String, dynamic> m) async {
    final res = await UI.sheet<(int, int)>(_ScoreSheet(
      home: _team(m, 'h'), away: _team(m, 'a'),
      h: m['gh'] == null ? 0 : m.i('gh'), a: m['ga'] == null ? 0 : m.i('ga'),
    ), initial: .55);
    if (res == null) return;
    try {
      final r = await Engage.call('admin_settle', {
        'match_id': m.i('id'), 'h': res.$1, 'a': res.$2,
        'home_name': _team(m, 'h'), 'away_name': _team(m, 'a'), 'league': m.str('_lg'), 'ts': m.i('ts'),
        // تعديل نتيجة معلنة سابقاً: بلا رسائل مكررة للفائزين
        'notify': !_rows('results').any((r) => r.i('match_id') == m.i('id')),
      });
      BotLog.add('prize', '🏁 نتيجة ${_team(m, 'h')} ${res.$1}-${res.$2} ${_team(m, 'a')}',
          '${r.i('winners')} فائز من ${r.i('total')} توقع');
      UI.toast(r.i('winners') == 0 ? 'لا يوجد توقع صحيح (${r.i('total')} توقع)' : '🎉 ${r.i('winners')} فائز — وصلتهم رسالة');
      _load();
    } catch (e) { UI.err(e); }
  }

  // ── الفائزون ────────────────────────────────────────────────────
  Widget _winnersTab(List<Map<String, dynamic>> winners) {
    final pending = winners.where((w) => !w.b('rewarded')).toList();
    final subscribedPending = pending.where((w) => w.b('subscribed')).toList();
    return RefreshIndicator(
      color: K.gold, onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (subscribedPending.length > 1) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: BusyButton(
            label: 'منح يوم لكل المشتركين الفائزين (${subscribedPending.length})',
            icon: Icons.card_giftcard_rounded, busy: _busy.contains('all'),
            onPressed: () async {
              if (!await UI.confirm('منح الجميع؟', 'يُمدَّد اشتراك ${subscribedPending.length} فائز يوماً واحداً.')) return;
              setState(() => _busy.add('all'));
              var n = 0;
              for (final w in subscribedPending) { if (await Rewards.grantWin(w)) n++; }
              setState(() => _busy.remove('all'));
              UI.toast('مُنح $n فائز ✅');
              _load();
            }),
        ),
        if (winners.isEmpty)
          const EmptyView(icon: Icons.emoji_events_outlined, title: 'لا فائزين بعد', sub: 'أعلن نتائج المباريات من تبويب «النتائج»'),
        for (final w in winners) _winnerCard(w),
      ]),
    );
  }

  Widget _winnerCard(Map<String, dynamic> w) {
    final key = 'w:${w.i('match_id')}:${w.str('uid')}';
    final done = w.b('rewarded');
    final who = w.str('name').isNotEmpty ? w.str('name') : w.str('email');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Box(
        padding: const EdgeInsets.all(12),
        border: done ? null : K.gold.withOpacity(.35),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(who, size: 40),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(who.isEmpty ? w.str('uid') : who, style: K.h3),
              Text('${w.str('home_name')} ${w.i('home_goals')} - ${w.i('away_goals')} ${w.str('away_name')}', style: K.sub),
            ])),
            Pill(done ? 'مُنح' : (w.b('subscribed') ? 'مشترك' : 'غير مشترك'),
                color: done ? K.grn : (w.b('subscribed') ? K.blu : K.t3)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (!done) ActBtn(Icons.card_giftcard_rounded, _busy.contains(key) ? 'جاري…' : 'منح يوم مجاني', _busy.contains(key) ? null : () async {
              setState(() => _busy.add(key));
              await Rewards.grantWin(w);
              if (mounted) setState(() => _busy.remove(key));
              _load();
            }, filled: true, color: K.gold),
            ActBtn(Icons.chat_rounded, 'محادثة', () => Nav.push(ChatRoomPage(uid: w.str('uid'), email: w.str('email'), name: w.str('name')))),
            ActBtn(Icons.person_rounded, 'الملف', () => Nav.push(MemberPage(uid: w.str('uid'), email: w.str('email')))),
          ]),
        ]),
      ),
    );
  }

  // ── الدعوات ─────────────────────────────────────────────────────
  Widget _refsTab(List<Map<String, dynamic>> refs) => RefreshIndicator(
    color: K.gold, onRefresh: _load,
    child: ListView(padding: const EdgeInsets.all(16), children: [
      const Banner2('عند قبول طلب اشتراك لصديق مدعوّ يسألك التطبيق مباشرة عن منح الداعي 16 يوماً. ما أجّلته يبقى هنا.',
          icon: Icons.info_outline_rounded),
      const SizedBox(height: 10),
      if (refs.isEmpty) const EmptyView(icon: Icons.group_add_outlined, title: 'لا دعوات بعد'),
      for (final r in refs) () {
        final key = 'r:${r.str('friend_uid')}';
        final status = r.str('status');
        final (label, color) = switch (status) {
          'subscribed' => ('اشترك — بانتظار الجائزة', K.gold),
          'rewarded' => ('مُنحت الجائزة', K.grn),
          _ => ('سجّل بالكود — لم يشترك بعد', K.t3),
        };
        final referrer = r.str('referrer_name').isNotEmpty ? r.str('referrer_name') : r.str('referrer_email');
        final friend = r.str('friend_name').isNotEmpty ? r.str('friend_name') : r.str('friend_email');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Box(
            padding: const EdgeInsets.all(12),
            border: status == 'subscribed' ? K.gold.withOpacity(.35) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('الداعي: $referrer', style: K.h3),
                  Text('الصديق: $friend · الكود ${r.str('code')}', style: K.sub),
                  Text(Fmt.dt(r.d('created_at')), style: K.tiny),
                ])),
                Pill(label, color: color),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (status == 'subscribed') ActBtn(Icons.card_giftcard_rounded,
                    _busy.contains(key) ? 'جاري…' : 'منح ${Rewards.refDays} يوماً للداعي', _busy.contains(key) ? null : () async {
                  setState(() => _busy.add(key));
                  await Rewards.grantReferral(r);
                  if (mounted) setState(() => _busy.remove(key));
                  _load();
                }, filled: true, color: K.gold),
                ActBtn(Icons.chat_rounded, 'محادثة الداعي', () => Nav.push(ChatRoomPage(uid: r.str('referrer_uid'),
                    email: r.str('referrer_email'), name: r.str('referrer_name')))),
                ActBtn(Icons.person_rounded, 'ملف الصديق', () => Nav.push(MemberPage(uid: r.str('friend_uid'), email: r.str('friend_email')))),
              ]),
            ]),
          ),
        );
      }(),
    ]),
  );
}

/// إدخال النتيجة النهائية
class _ScoreSheet extends StatefulWidget {
  final String home, away;
  final int h, a;
  const _ScoreSheet({required this.home, required this.away, required this.h, required this.a});
  @override State<_ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends State<_ScoreSheet> {
  late int _h = widget.h, _a = widget.a;

  Widget _side(String name, int v, ValueChanged<int> on) => Expanded(child: Column(children: [
    Text(name, maxLines: 2, textAlign: TextAlign.center, style: K.h3),
    const SizedBox(height: 10),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton.filledTonal(onPressed: () => on(v + 1), icon: const Icon(Icons.add_rounded)),
      SizedBox(width: 56, child: Text('$v', textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: K.t1))),
      IconButton.filledTonal(onPressed: v > 0 ? () => on(v - 1) : null, icon: const Icon(Icons.remove_rounded)),
    ]),
  ]));

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('النتيجة النهائية', textAlign: TextAlign.center, style: K.h2),
      const SizedBox(height: 4),
      const Text('بعد الوقت الأصلي والإضافي (بدون ركلات الترجيح)', textAlign: TextAlign.center, style: K.tiny),
      const SizedBox(height: 20),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _side(widget.home, _h, (v) => setState(() => _h = v)),
        const Padding(padding: EdgeInsets.only(top: 40), child: Text(':', style: TextStyle(fontSize: 30, color: K.t3))),
        _side(widget.away, _a, (v) => setState(() => _a = v)),
      ]),
      const SizedBox(height: 24),
      BusyButton(label: 'إعلان النتيجة وتحديد الفائزين', icon: Icons.emoji_events_rounded,
          onPressed: () async => Navigator.pop(context, (_h, _a))),
    ]),
  );
}
