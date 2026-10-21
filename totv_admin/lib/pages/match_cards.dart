part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🎴 بطاقات المباريات — تعديل بطاقة أي مباراة اليوم/الغد
//  • صورة العرض: رفع من الهاتف أو اختيار من صور الإعلانات
//  • القناة الموصى بها: من قائمة قنوات السيرفر الحقيقية (أو رابط مباشر)
//    تظهر أولاً ومميّزة، وبقية القنوات الناقلة تحتها تلقائياً
//  • 📡 أعطال القنوات: كل قناة فشلت عند المستخدمين (آخر 24 ساعة)
//
//  المستند: app_config/match_overrides  ← m<رقم المباراة> = {...}
// ════════════════════════════════════════════════════════════════════
class MatchOverridesDb {
  static final doc = FirebaseFirestore.instance.collection('app_config').doc('match_overrides');

  static Future<void> put(int id, Map<String, dynamic> v) =>
      doc.set({'m$id': {...v, 'at': DateTime.now().toIso8601String()}}, SetOptions(merge: true));
  static Future<void> remove(int id) => doc.set({'m$id': FieldValue.delete()}, SetOptions(merge: true));

  /// حذف تعديلات المباريات القديمة (أقدم من 3 أيام) ⇐ المستند يبقى صغيراً
  static Future<void> prune(Map<String, dynamic> d, Set<int> liveIds) async {
    final cut = DateTime.now().subtract(const Duration(days: 3));
    final del = <String, dynamic>{};
    d.forEach((k, v) {
      if (!k.startsWith('m') || v is! Map) return;
      final id = int.tryParse(k.substring(1)) ?? 0;
      final at = DateTime.tryParse('${v['at'] ?? ''}');
      if (!liveIds.contains(id) && at != null && at.isBefore(cut)) del[k] = FieldValue.delete();
    });
    if (del.isNotEmpty) await doc.set(del, SetOptions(merge: true));
  }
}

/// قنوات السيرفر (player_api) — بحساب السيرفر الافتراضي من remote_config
class ServerChannels {
  static List<Map<String, dynamic>> list = [];
  static Map<String, String> cats = {};
  static DateTime? at;

  static Future<List<Map<String, dynamic>>> load({bool force = false}) async {
    if (!force && list.isNotEmpty && at != null && DateTime.now().difference(at!).inMinutes < 15) return list;
    final rc = (await FirebaseFirestore.instance.collection('app_config').doc('remote_config').get()).data() ?? {};
    String s(String k) => '${rc[k] ?? ''}'.trim();
    final host = (s('server_host').isNotEmpty ? s('server_host') : s('default_server_host')).replaceAll(RegExp(r'/+$'), '');
    final u = Uri.encodeComponent(s('username')), p = Uri.encodeComponent(s('password'));
    if (host.isEmpty || u.isEmpty) throw Exception('لا توجد بيانات السيرفر في remote_config');
    final base = '$host/player_api.php?username=$u&password=$p';
    final rs = await Future.wait([
      Net.req('GET', '$base&action=get_live_streams', timeout: const Duration(seconds: 40)),
      Net.req('GET', '$base&action=get_live_categories', timeout: const Duration(seconds: 20)),
    ]);
    if (!rs[0].ok || rs[0].body is! List) throw Exception('السيرفر لم يُعِد القنوات (${rs[0].code})');
    cats = {
      if (rs[1].body is List)
        for (final c in rs[1].body as List) '${(c as Map)['category_id']}': '${c['category_name'] ?? ''}',
    };
    list = (rs[0].body as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    at = DateTime.now();
    return list;
  }
}

class MatchCardsPage extends StatefulWidget {
  const MatchCardsPage({super.key});
  @override State<MatchCardsPage> createState() => _MatchCardsPageState();
}

class _MatchCardsPageState extends State<MatchCardsPage> with SingleTickerProviderStateMixin {
  late final TabController _tc = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _matches = [];
  Map<String, dynamic> _ov = {};
  String _feed = '', _err = '';
  bool _loading = true;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = MatchOverridesDb.doc.snapshots().listen((s) { if (mounted) setState(() => _ov = s.data() ?? {}); });
    _load();
  }

  @override
  void dispose() { _sub?.cancel(); _tc.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _err = ''; });
    try {
      final rc = await FirebaseFirestore.instance.collection('app_config').doc('remote_config').get();
      _feed = '${rc.data()?['sports_feed'] ?? ''}'.trim().replaceAll(RegExp(r'/+$'), '');
      if (_feed.isEmpty) throw Exception('رابط خلاصة المباريات غير مضبوط');
      final r = await Net.req('GET', '$_feed/matches.json?r=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
      if (!r.ok || r.body is! Map) throw Exception('تعذّر تحميل جدول المباريات (${r.code})');
      final j = Map<String, dynamic>.from(r.body as Map);
      final lg = j.m('leagues');
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _matches = j.l('matches').map((e) => Map<String, dynamic>.from(e as Map)).map((m) {
        m['_lg'] = lg.m('${m['lg']}').str('ar');
        return m;
      }).where((m) => m.i('ts') > now - 3 * 3600 && m.i('ts') < now + 2 * 86400).toList()
        ..sort((a, b) => a.i('ts').compareTo(b.i('ts')));
      unawaited(MatchOverridesDb.prune(_ov, _matches.map((m) => m.i('id')).toSet()));
    } catch (e) { _err = Fmt.err(e); }
    if (mounted) setState(() => _loading = false);
  }

  String _team(Map<String, dynamic> m, String s) => m.m(s).str('ar').isNotEmpty ? m.m(s).str('ar') : m.m(s).str('n');
  String _img(String rel) => rel.isEmpty ? '' : (rel.startsWith('http') ? rel : '$_feed/$rel');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('بطاقات المباريات'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      bottom: TabBar(controller: _tc, indicatorColor: K.gold, labelColor: K.gold, tabs: const [
        Tab(text: 'مباريات اليوم والغد'), Tab(text: '📡 أعطال القنوات'),
      ]),
    ),
    body: TabBarView(controller: _tc, children: [_matchesTab(), const _ReportsTab()]),
  );

  Widget _matchesTab() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: K.gold));
    if (_err.isNotEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err, style: K.sub, textAlign: TextAlign.center)));
    if (_matches.isEmpty) return const Center(child: Text('لا توجد مباريات اليوم أو غداً', style: K.sub));
    String day(DateTime d) {
      final n = DateTime.now();
      if (d.year == n.year && d.month == n.month && d.day == n.day) return 'اليوم';
      final t = n.add(const Duration(days: 1));
      if (d.year == t.year && d.month == t.month && d.day == t.day) return 'غداً';
      return Fmt.dateShort(d);
    }
    String? last;
    final out = <Widget>[
      const Banner2('اضغط أي مباراة لتغيير صورة العرض وتحديد القناة الموصى بها. '
          'المستخدم يرى القناة الموصى بها أولاً ⭐ ثم بقية القنوات الناقلة من السيرفر بروابط جديدة.',
          icon: Icons.touch_app_rounded),
      const SizedBox(height: 12),
    ];
    for (final m in _matches) {
      final k = DateTime.fromMillisecondsSinceEpoch(m.i('ts') * 1000);
      final d = day(k);
      if (d != last) { last = d; out.add(Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 8), child: Text(d, style: K.h3))); }
      final o = _ov['m${m.i('id')}'];
      final ov = o is Map ? Map<String, dynamic>.from(o) : <String, dynamic>{};
      final poster = '${ov['poster'] ?? ''}'.isNotEmpty ? '${ov['poster']}' : _img(m.str('poster'));
      final chName = '${ov['label'] ?? ''}'.isNotEmpty ? '${ov['label']}'
          : ('${ov['url'] ?? ''}'.isNotEmpty ? 'رابط مباشر' : '${ov['name'] ?? ''}');
      out.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: Box(
        padding: const EdgeInsets.all(10),
        border: ov.isNotEmpty ? K.gold.withOpacity(.5) : null,
        onTap: () async {
          await Nav.push(MatchCardEditor(match: m, current: ov, feed: _feed));
        },
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 92, height: 56,
            child: poster.isEmpty ? const ColoredBox(color: K.card2, child: Icon(Icons.image_rounded, color: K.t3))
                : Image.network(poster, fit: BoxFit.cover, cacheWidth: 300,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: K.card2, child: Icon(Icons.broken_image_rounded, color: K.t3))))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_team(m, 'h')} × ${_team(m, 'a')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: K.h3),
            Text('${Fmt.time(k)} · ${m.str('_lg')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: K.tiny),
            if (chName.isNotEmpty) Text('⭐ $chName', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: K.tiny.copyWith(color: K.gold, fontWeight: FontWeight.w700)),
          ])),
          Icon(ov.isEmpty ? Icons.edit_rounded : Icons.check_circle_rounded, color: ov.isEmpty ? K.t3 : K.gold),
        ]),
      )));
    }
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: out));
  }
}

// ── محرّر بطاقة مباراة ─────────────────────────────────────────────
class MatchCardEditor extends StatefulWidget {
  final Map<String, dynamic> match, current;
  final String feed;
  const MatchCardEditor({super.key, required this.match, required this.current, required this.feed});
  @override State<MatchCardEditor> createState() => _MatchCardEditorState();
}

class _MatchCardEditorState extends State<MatchCardEditor> {
  late final _poster = TextEditingController(text: '${widget.current['poster'] ?? ''}');
  late final _url = TextEditingController(text: '${widget.current['url'] ?? ''}');
  late final _label = TextEditingController(text: '${widget.current['label'] ?? ''}');
  late String _sid = '${widget.current['stream_id'] ?? ''}';
  late String _name = '${widget.current['name'] ?? ''}';
  bool _busy = false, _upl = false;

  Map<String, dynamic> get m => widget.match;
  int get id => m.i('id');
  String _team(String s) => m.m(s).str('ar').isNotEmpty ? m.m(s).str('ar') : m.m(s).str('n');

  @override
  void dispose() { _poster.dispose(); _url.dispose(); _label.dispose(); super.dispose(); }

  Future<void> _upload() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 86, maxWidth: 1600);
    if (img == null) return;
    setState(() => _upl = true);
    try { _poster.text = await LiveStudio.uploadPoster(await img.readAsBytes()); UI.toast('رُفعت الصورة ✅'); }
    catch (e) { UI.err(e); }
    if (mounted) setState(() => _upl = false);
  }

  Future<void> _fromPromos() async {
    if (!GhPromos.ready) { UI.toast('اضبط مفتاح GitHub من صفحة «الإعلانات» أولاً', error: true); return; }
    List<Map<String, dynamic>> files;
    try { files = await GhPromos.list(); } catch (e) { UI.err(e); return; }
    if (!mounted) return;
    final pick = await showModalBottomSheet<String>(context: context, backgroundColor: K.card, isScrollControlled: true,
      builder: (c) => SafeArea(child: SizedBox(height: MediaQuery.of(c).size.height * .7, child: GridView.count(
        crossAxisCount: 2, padding: const EdgeInsets.all(12), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 16 / 10,
        children: [
          for (final f in files) GestureDetector(
            onTap: () => Navigator.pop(c, f.str('download_url')),
            child: ClipRRect(borderRadius: BorderRadius.circular(10),
                child: Image.network(f.str('download_url'), fit: BoxFit.cover, cacheWidth: 400,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: K.card2)))),
        ],
      ))));
    if (pick != null && pick.isNotEmpty) setState(() => _poster.text = pick);
  }

  Future<void> _pickChannel() async {
    final ch = await Nav.push<Map<String, dynamic>>(const ChannelPickerPage());
    if (ch != null) setState(() { _sid = '${ch['stream_id'] ?? ''}'; _name = '${ch['name'] ?? ''}'; });
  }

  Future<void> _save() async {
    final p = _poster.text.trim(), u = _url.text.trim();
    if (p.isNotEmpty && !p.startsWith('https://')) { UI.toast('رابط الصورة يجب أن يبدأ بـ https://', error: true); return; }
    if (u.isNotEmpty && !u.startsWith('http')) { UI.toast('رابط التشغيل غير صحيح', error: true); return; }
    final v = <String, dynamic>{
      if (p.isNotEmpty) 'poster': p,
      if (_sid.isNotEmpty) 'stream_id': _sid,
      if (_name.isNotEmpty) 'name': _name,
      if (u.isNotEmpty) 'url': u,
      if (_label.text.trim().isNotEmpty) 'label': _label.text.trim(),
    };
    setState(() => _busy = true);
    try {
      if (v.isEmpty) { await MatchOverridesDb.remove(id); } else { await MatchOverridesDb.put(id, v); }
      BotLog.add('cards', '🎴 بطاقة مباراة', '${_team('h')} × ${_team('a')}');
      UI.toast('حُفظت البطاقة ✅ تتحدّث عند المستخدمين فوراً');
      if (mounted) Navigator.pop(context);
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reset() async {
    if (!await UI.confirm('إرجاع البطاقة للأصل؟', 'تُحذف الصورة والقناة المحدّدة لهذه المباراة.', danger: true, ok: 'إرجاع')) return;
    try { await MatchOverridesDb.remove(id); UI.toast('أُرجعت للأصل'); if (mounted) Navigator.pop(context); } catch (e) { UI.err(e); }
  }

  @override
  Widget build(BuildContext context) {
    final p = _poster.text.trim();
    final feedPoster = m.str('poster');
    final shown = p.isNotEmpty ? p : (feedPoster.isEmpty ? '' : (feedPoster.startsWith('http') ? feedPoster : '${widget.feed}/$feedPoster'));
    return Scaffold(
      appBar: AppBar(title: Text('${_team('h')} × ${_team('a')}'), actions: [
        if (widget.current.isNotEmpty) IconButton(tooltip: 'إرجاع للأصل', onPressed: _reset, icon: const Icon(Icons.restart_alt_rounded)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('صورة العرض', style: K.h3),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(aspectRatio: 16 / 9,
          child: shown.isEmpty ? const ColoredBox(color: K.card2, child: Center(child: Text('بلا صورة — يُعرض شعارا الفريقين', style: K.sub)))
              : Image.network(shown, fit: BoxFit.cover, cacheWidth: 900,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: K.card2, child: Center(child: Icon(Icons.broken_image_rounded, color: K.t3)))))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _upl ? null : _upload,
              icon: _upl ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_rounded),
              label: const Text('رفع من الهاتف'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: _fromPromos, icon: const Icon(Icons.photo_library_rounded), label: const Text('من الإعلانات'))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _poster, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'أو رابط صورة (اتركه فارغاً للصورة الأصلية)', hintText: 'https://')),
        const SizedBox(height: 22),
        const Text('القناة الموصى بها', style: K.h3),
        const SizedBox(height: 4),
        const Text('تظهر أولاً ⭐ عند ضغط «شاهد»، وتحتها بقية القنوات الناقلة تلقائياً. '
            'الرابط يُبنى من قائمة السيرفر لحظة الضغط ⇐ دائماً جديد.', style: K.tiny),
        const SizedBox(height: 10),
        Box(padding: const EdgeInsets.all(12), color: K.card2, onTap: _pickChannel, child: Row(children: [
          const Icon(Icons.live_tv_rounded, color: K.gold),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name.isEmpty ? 'اختر قناة من السيرفر' : _name, style: K.body.copyWith(fontWeight: FontWeight.w800),
                textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(_sid.isEmpty ? 'اضغط للاختيار من قائمة القنوات المباشرة' : 'رقم القناة $_sid', style: K.tiny),
          ])),
          if (_sid.isNotEmpty) IconButton(icon: const Icon(Icons.close_rounded, color: K.t3),
              onPressed: () => setState(() { _sid = ''; _name = ''; })),
          const Icon(Icons.chevron_left_rounded, color: K.t3),
        ])),
        const SizedBox(height: 10),
        TextField(controller: _label, decoration: const InputDecoration(labelText: 'اسم يظهر للمستخدم (اختياري)', hintText: 'مثال: القناة الأساسية HD')),
        const SizedBox(height: 10),
        TextField(controller: _url, textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'أو رابط تشغيل مباشر (اختياري — يتقدّم على القناة)', hintText: 'https://…/index.m3u8')),
        const SizedBox(height: 24),
        BusyButton(label: 'حفظ البطاقة', icon: Icons.save_rounded, busy: _busy, onPressed: _save),
      ]),
    );
  }
}

// ── اختيار قناة من قائمة السيرفر ───────────────────────────────────
class ChannelPickerPage extends StatefulWidget {
  const ChannelPickerPage({super.key});
  @override State<ChannelPickerPage> createState() => _ChannelPickerPageState();
}

class _ChannelPickerPageState extends State<ChannelPickerPage> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  String _err = '';
  bool _loading = true;
  Timer? _deb;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _deb?.cancel(); _q.dispose(); super.dispose(); }

  Future<void> _load({bool force = false}) async {
    setState(() { _loading = true; _err = ''; });
    try { _all = await ServerChannels.load(force: force); } catch (e) { _err = Fmt.err(e); }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = q.isEmpty ? _all.take(300).toList()
        : _all.where((c) => '${c['name'] ?? ''}'.toLowerCase().contains(q) || '${c['stream_id']}' == q).take(300).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('قنوات السيرفر'), actions: [
        IconButton(onPressed: () => _load(force: true), icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 6), child: SearchBox(controller: _q, hint: 'ابحث: bein, ssc, alkass…',
            onChanged: (_) { _deb?.cancel(); _deb = Timer(const Duration(milliseconds: 220), () { if (mounted) setState(() {}); }); })),
        if (!_loading && _err.isEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(alignment: Alignment.centerRight, child: Text('${Fmt.n(_all.length)} قناة · تظهر ${list.length}', style: K.tiny))),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator(color: K.gold))
          : _err.isNotEmpty ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err, style: K.sub, textAlign: TextAlign.center)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 30),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                final icon = '${c['stream_icon'] ?? ''}';
                return ListTile(
                  onTap: () => Navigator.pop(context, c),
                  leading: SizedBox(width: 48, height: 32, child: icon.startsWith('http')
                      ? Image.network(icon, fit: BoxFit.contain, cacheWidth: 120, errorBuilder: (_, __, ___) => const Icon(Icons.tv_rounded, color: K.t3))
                      : const Icon(Icons.tv_rounded, color: K.t3)),
                  title: Text('${c['name'] ?? ''}', textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: K.body),
                  subtitle: Text('${ServerChannels.cats['${c['category_id']}'] ?? ''} · #${c['stream_id']}', maxLines: 1, style: K.tiny),
                );
              }),
        ),
      ]),
    );
  }
}

// ── تبويب أعطال القنوات (آخر 24 ساعة) ─────────────────────────────
class _ReportsTab extends StatefulWidget {
  const _ReportsTab();
  @override State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  List<Map<String, dynamic>> _rows = [];
  String _err = '';
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _err = ''; });
    try {
      final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 24)));
      final s = await FirebaseFirestore.instance.collection('channel_reports')
          .where('at', isGreaterThan: since).orderBy('at', descending: true).limit(500).get();
      _rows = s.docs.map((d) => {'_id': d.id, ...d.data()}).toList();
    } catch (e) {
      _err = '${Fmt.err(e)}\n\nإن ظهر «permission-denied» أضف قاعدة channel_reports في Firestore.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _clear() async {
    if (!await UI.confirm('مسح كل التقارير؟', 'يُحذف ${_rows.length} تقرير.', danger: true, ok: 'مسح')) return;
    try {
      final b = FirebaseFirestore.instance.batch();
      for (final r in _rows.take(450)) { b.delete(FirebaseFirestore.instance.collection('channel_reports').doc('${r['_id']}')); }
      await b.commit();
      _load();
    } catch (e) { UI.err(e); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: K.gold));
    if (_err.isNotEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err, style: K.sub, textAlign: TextAlign.center)));
    // تجميع حسب القناة: الأكثر تعطّلاً أولاً
    final g = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) { g.putIfAbsent('${r['name'] ?? r['cid']}', () => []).add(r); }
    final keys = g.keys.toList()..sort((a, b) => g[b]!.length.compareTo(g[a]!.length));
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      Banner2(_rows.isEmpty ? 'لا توجد أعطال مسجّلة في آخر 24 ساعة ✅'
          : '${Fmt.n(_rows.length)} تعطّل في ${keys.length} قناة خلال 24 ساعة — كل تقرير = مستخدم فشلت عنده القناة بكل مصادرها.',
          icon: _rows.isEmpty ? Icons.check_circle_rounded : Icons.report_rounded, color: _rows.isEmpty ? K.grn : K.red,
          action: _rows.isEmpty ? null : TextButton(onPressed: _clear, child: const Text('مسح'))),
      const SizedBox(height: 12),
      for (final k in keys) Padding(padding: const EdgeInsets.only(bottom: 8), child: Box(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(width: 44, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(color: K.red.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
              child: Text('${g[k]!.length}', style: K.h3.copyWith(color: K.red))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: K.h3),
            Text('آخر سبب: ${g[k]!.first['reason'] ?? '—'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: K.tiny),
            Text('آخر تعطّل ${Fmt.ago(g[k]!.first['at'] is Timestamp ? (g[k]!.first['at'] as Timestamp).toDate() : null)}'
                ' · ${g[k]!.map((r) => r['uid']).toSet().length} مستخدم', style: K.tiny),
          ])),
        ]),
      )),
    ]));
  }
}
