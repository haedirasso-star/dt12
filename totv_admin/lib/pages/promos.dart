part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🖼 الإعلانات — رفع صور إعلانات المباريات والإعلانات العامة من الهاتف
//  • تُرفع مباشرة إلى مجلد promos في مستودع الرياضة على GitHub
//  • التطبيق يكتب اسم الملف الصحيح تلقائياً (موعد المباراة + رقمها)
//  • النشر خلال دقيقة إلى 5 دقائق، والتوزيع مجاني عبر GitHub Pages
//  مفتاح GitHub محفوظ على هذا الهاتف فقط (لا يدخل الكود)، وصلاحيته
//  مقصورة على مستودع الرياضة.
// ════════════════════════════════════════════════════════════════════
class GhPromos {
  static String get token => Prefs.p.getString('gh_token') ?? '';
  static String get repo => Prefs.p.getString('gh_repo') ?? '';
  static bool get ready => token.isNotEmpty && repo.contains('/');

  static Map<String, String> get _h => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  static String _url(String name) => 'https://api.github.com/repos/$repo/contents/promos${name.isEmpty ? '' : '/${Uri.encodeComponent(name)}'}';

  static String _err(NetResult r) {
    final m = r.body is Map ? '${(r.body as Map)['message'] ?? ''}' : '';
    if (r.code == 401) return 'مفتاح GitHub غير صحيح أو انتهت صلاحيته';
    if (r.code == 403) return 'المفتاح لا يملك صلاحية Contents: Read and write على المستودع';
    if (r.code == 404) return 'المستودع $repo غير موجود أو المفتاح لا يصل إليه';
    return m.isEmpty ? 'خطأ GitHub ${r.code}' : 'GitHub: $m';
  }

  /// يستنتج المستودع من رابط الخلاصة: https://USER.github.io/REPO
  static Future<String> guessRepo() async {
    try {
      final rc = await FirebaseFirestore.instance.collection('app_config').doc('remote_config').get();
      final u = Uri.tryParse('${rc.data()?['sports_feed'] ?? ''}'.trim());
      if (u == null || !u.host.endsWith('.github.io')) return '';
      final user = u.host.split('.').first;
      final seg = u.pathSegments.where((s) => s.isNotEmpty).toList();
      return seg.isEmpty ? '' : '$user/${seg.first}';
    } catch (_) { return ''; }
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final r = await Net.req('GET', _url(''), headers: _h);
    if (r.code == 404 && r.body is Map && '${(r.body as Map)['message']}'.contains('Not Found')) {
      // المجلد غير موجود بعد ⇐ قائمة فارغة (يُنشأ مع أول صورة)
      final repoCheck = await Net.req('GET', 'https://api.github.com/repos/$repo', headers: _h);
      if (repoCheck.ok) return [];
    }
    if (!r.ok || r.body is! List) throw Exception(_err(r));
    return (r.body as List).map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) => RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(m.str('name'))).toList()
      ..sort((a, b) => b.str('name').compareTo(a.str('name')));
  }

  static Future<void> upload(String name, Uint8List bytes) async {
    String? sha;
    final ex = await Net.req('GET', _url(name), headers: _h);
    if (ex.ok && ex.body is Map) sha = (ex.body as Map)['sha']?.toString();
    final r = await Net.req('PUT', _url(name), headers: _h, timeout: const Duration(seconds: 90), body: {
      'message': 'إعلان: $name (من تطبيق الإدارة)',
      'content': base64Encode(bytes),
      if (sha != null) 'sha': sha,
    });
    if (!r.ok) throw Exception(_err(r));
  }

  static Future<void> delete(Map<String, dynamic> f) async {
    final r = await Net.req('DELETE', _url(f.str('name')), headers: _h, body: {
      'message': 'حذف إعلان: ${f.str('name')}', 'sha': f.str('sha'),
    });
    if (!r.ok) throw Exception(_err(r));
  }

  /// توقيت بغداد ثابت (UTC+3، بلا توقيت صيفي)
  static DateTime baghdad(int ts) => DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).add(const Duration(hours: 3));
  static String matchName(Map<String, dynamic> m) {
    final b = baghdad(m.i('ts'));
    return '${b.year}-${Fmt.two(b.month)}-${Fmt.two(b.day)}_${Fmt.two(b.hour)}-${Fmt.two(b.minute)}_m${m.i('id')}.jpg';
  }

  /// يفهم اسم الملف لعرضه بوضوح
  static (String kind, String label, bool expired) describe(String name, Map<int, Map<String, dynamic>> matches) {
    final ad = RegExp(r'^ad(?:_until-(\d{4})-(\d{2})-(\d{2}))?', caseSensitive: false).firstMatch(name);
    if (ad != null) {
      if (ad.group(1) == null) return ('ad', 'إعلان عام — دائم', false);
      final end = DateTime(int.parse(ad.group(1)!), int.parse(ad.group(2)!), int.parse(ad.group(3)!), 23, 59);
      return ('ad', 'إعلان عام — حتى ${Fmt.dateShort(end)}', end.isBefore(DateTime.now()));
    }
    final mt = RegExp(r'^(\d{4})-(\d{2})-(\d{2})_(\d{1,2})-(\d{2})(?:_(.+))?\.').firstMatch(name);
    if (mt == null) return ('bad', '⚠️ اسم غير صحيح — لن يظهر', true);
    final utc = DateTime.utc(int.parse(mt.group(1)!), int.parse(mt.group(2)!), int.parse(mt.group(3)!),
        int.parse(mt.group(4)!), int.parse(mt.group(5)!)).subtract(const Duration(hours: 3));
    final local = utc.toLocal();
    final id = int.tryParse(RegExp(r'^m(\d+)$').firstMatch(mt.group(6) ?? '')?.group(1) ?? '') ?? 0;
    final m = matches[id];
    String team(Map<String, dynamic> x, String s) => x.m(s).str('ar').isNotEmpty ? x.m(s).str('ar') : x.m(s).str('n');
    final title = m != null ? '${team(m, 'h')} × ${team(m, 'a')}'
        : ((mt.group(6) ?? '').replaceAll(RegExp(r'[-_]+'), ' ').trim());
    return ('match', '${title.isEmpty ? 'مباراة' : title} · ${Fmt.dt(local)}',
        local.isBefore(DateTime.now().subtract(const Duration(hours: 2))));
  }
}

class PromosPage extends StatefulWidget {
  const PromosPage({super.key});
  @override State<PromosPage> createState() => _PromosPageState();
}

class _PromosPageState extends State<PromosPage> {
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _matches = [];
  String _feed = '', _err = '';
  bool _loading = true, _busy = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _err = ''; });
    try {
      if (GhPromos.repo.isEmpty) {
        final g = await GhPromos.guessRepo();
        if (g.isNotEmpty) await Prefs.p.setString('gh_repo', g);
      }
      final rc = await FirebaseFirestore.instance.collection('app_config').doc('remote_config').get();
      _feed = '${rc.data()?['sports_feed'] ?? ''}'.trim().replaceAll(RegExp(r'/+$'), '');
      if (_feed.isNotEmpty) {
        final r = await Net.req('GET', '$_feed/matches.json?r=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
        if (r.ok && r.body is Map) {
          final j = Map<String, dynamic>.from(r.body as Map);
          final lg = j.m('leagues');
          _matches = j.l('matches').map((e) => Map<String, dynamic>.from(e as Map)).map((m) {
            m['_lg'] = lg.m('${m['lg']}').str('ar');
            return m;
          }).toList()..sort((a, b) => a.i('ts').compareTo(b.i('ts')));
        }
      }
      if (GhPromos.ready) _files = await GhPromos.list();
    } catch (e) { _err = Fmt.err(e); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _settings() async {
    final repo = await UI.input('مستودع الرياضة', initial: GhPromos.repo, hint: 'USER/totv-sports',
        help: 'اسم المستودع الذي فيه مجلد promos (يُستنتج تلقائياً من رابط الخلاصة).', ok: 'التالي');
    if (repo == null) return;
    final tok = await UI.input('مفتاح GitHub', hint: 'github_pat_…',
        help: 'GitHub ← Settings ← Developer settings ← Fine-grained tokens ← Generate:\n'
            '• Repository access: Only select repositories ← مستودع الرياضة فقط\n'
            '• Permissions ← Contents: Read and write\n'
            'يُحفظ على هذا الهاتف فقط. اتركه فارغاً لإبقاء المفتاح الحالي.', ok: 'حفظ');
    if (tok == null) return;
    await Prefs.p.setString('gh_repo', repo.trim().replaceAll(RegExp(r'^https?://github.com/'), '').replaceAll(RegExp(r'/+$'), ''));
    if (tok.trim().isNotEmpty) await Prefs.p.setString('gh_token', tok.trim());
    UI.toast('حُفظ ✅');
    _load();
  }

  Future<Uint8List?> _pickImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 86, maxWidth: 1920);
    if (img == null) return null;
    final b = await img.readAsBytes();
    if (b.length > 4 * 1024 * 1024) { UI.toast('الصورة كبيرة جداً — اختر صورة أصغر', error: true); return null; }
    return b;
  }

  Future<void> _addMatch() async {
    if (!GhPromos.ready) { await _settings(); if (!GhPromos.ready) return; }
    final now = DateTime.now();
    final up = _matches.where((m) {
      final k = DateTime.fromMillisecondsSinceEpoch(m.i('ts') * 1000);
      return k.isAfter(now.subtract(const Duration(minutes: 30)));
    }).toList();
    if (up.isEmpty) { UI.toast('لا مباريات قادمة في الجدول', error: true); return; }
    final have = _files.map((f) => f.str('name')).toSet();
    String team(Map<String, dynamic> x, String s) => x.m(s).str('ar').isNotEmpty ? x.m(s).str('ar') : x.m(s).str('n');
    final m = await UI.pick<Map<String, dynamic>>('اختر المباراة', [
      for (final m in up.take(60)) (m,
        '${have.contains(GhPromos.matchName(m)) ? '✅ ' : ''}${team(m, 'h')} × ${team(m, 'a')} — '
            '${Fmt.dayLabel(DateTime.fromMillisecondsSinceEpoch(m.i('ts') * 1000))} '
            '${Fmt.time(DateTime.fromMillisecondsSinceEpoch(m.i('ts') * 1000))} · ${m.str('_lg')}',
        Icons.sports_soccer_rounded),
    ]);
    if (m == null) return;
    final b = await _pickImage();
    if (b == null) return;
    await _upload(GhPromos.matchName(m), b, '${team(m, 'h')} × ${team(m, 'a')}');
  }

  Future<void> _addAd() async {
    if (!GhPromos.ready) { await _settings(); if (!GhPromos.ready) return; }
    final dur = await UI.pick<int>('مدة الإعلان العام', [
      (0, 'دائم — حتى أحذفه', Icons.all_inclusive_rounded),
      (7, 'أسبوع', Icons.date_range_rounded),
      (30, 'شهر', Icons.calendar_month_rounded),
      (-1, 'حتى تاريخ أحدده', Icons.event_rounded),
    ]);
    if (dur == null) return;
    DateTime? end;
    if (dur > 0) end = DateTime.now().add(Duration(days: dur));
    if (dur == -1) {
      final c = Nav.ctx;
      if (c == null) return;
      end = await showDatePicker(context: c, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDate: DateTime.now().add(const Duration(days: 7)));
      if (end == null) return;
    }
    final b = await _pickImage();
    if (b == null) return;
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final name = end == null ? 'ad_$stamp.jpg' : 'ad_until-${end.year}-${Fmt.two(end.month)}-${Fmt.two(end.day)}_$stamp.jpg';
    await _upload(name, b, 'إعلان عام');
  }

  Future<void> _upload(String name, Uint8List b, String label) async {
    setState(() => _busy = true);
    try {
      await GhPromos.upload(name, b);
      BotLog.add('promo', '🖼 إعلان جديد: $label', name);
      UI.toast('رُفع ✅ يظهر في التطبيق خلال دقائق');
      _files = await GhPromos.list();
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(Map<String, dynamic> f) async {
    if (!await UI.confirm('حذف الإعلان؟', 'يختفي من التطبيق خلال دقائق.', danger: true, ok: 'حذف')) return;
    setState(() => _busy = true);
    try {
      await GhPromos.delete(f);
      UI.toast('حُذف');
      _files.remove(f);
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final m in _matches) m.i('id'): m};
    return Scaffold(
      appBar: AppBar(title: const Text('الإعلانات'), actions: [
        IconButton(tooltip: 'الإعداد', onPressed: _settings, icon: const Icon(Icons.key_rounded)),
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: _loading ? const Loading(text: 'جاري قراءة الإعلانات…') : RefreshIndicator(
        color: K.gold, onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(color: K.gold)),
          if (!GhPromos.ready)
            Banner2('للرفع من الهاتف: أنشئ مفتاح GitHub (Fine-grained) لمستودع الرياضة فقط بصلاحية Contents: Read and write، ثم ضعه هنا.',
                icon: Icons.key_rounded, color: K.org,
                action: TextButton(onPressed: _settings, child: const Text('إعداد')))
          else
            Banner2('المستودع: ${GhPromos.repo} · الصور تُنشر خلال دقائق، وتظهر كاملة بلا قص في الرئيسية وصفحة الرياضة.',
                icon: Icons.cloud_done_rounded, color: K.grn),
          if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: ErrorBox(_err, onRetry: _load)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: BusyButton(label: 'إعلان مباراة', icon: Icons.sports_soccer_rounded, busy: _busy, onPressed: _addMatch)),
            const SizedBox(width: 10),
            Expanded(child: BusyButton(label: 'إعلان عام', icon: Icons.campaign_rounded, busy: _busy, onPressed: _addAd, color: K.blu)),
          ]),
          const SizedBox(height: 6),
          const Text('أفضل مقاس: أفقي 16:9 (مثل 1920×1080). اجعل الوجوه والكتابة في المنتصف.', style: K.tiny, textAlign: TextAlign.center),
          Section('الإعلانات الحالية (${_files.length})'),
          if (_files.isEmpty) const EmptyView(icon: Icons.image_outlined, title: 'لا إعلانات بعد'),
          for (final f in _files) () {
            final (kind, label, expired) = GhPromos.describe(f.str('name'), byId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Box(
                padding: EdgeInsets.zero,
                border: expired ? K.red.withOpacity(.35) : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: AspectRatio(aspectRatio: 16 / 9, child: ColoredBox(
                      color: Colors.black,
                      child: f.str('download_url').isEmpty ? const SizedBox()
                          : Image.network(f.str('download_url'), fit: BoxFit.contain, cacheWidth: 720,
                              headers: GhPromos.token.isEmpty ? null : {'Authorization': 'Bearer ${GhPromos.token}'},
                              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, color: K.t3))),
                    )),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    child: Row(children: [
                      Icon(kind == 'ad' ? Icons.campaign_rounded : (kind == 'bad' ? Icons.error_rounded : Icons.sports_soccer_rounded),
                          color: kind == 'bad' ? K.red : (kind == 'ad' ? K.blu : K.grn), size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: K.h3.copyWith(fontSize: 14)),
                        Text(expired ? 'انتهى — لم يعد يظهر، يمكنك حذفه' : f.str('name'),
                            style: K.tiny.copyWith(color: expired ? K.red : K.t3), textDirection: TextDirection.ltr),
                      ])),
                      IconButton(onPressed: _busy ? null : () => _delete(f), icon: const Icon(Icons.delete_outline_rounded, color: K.red)),
                    ]),
                  ),
                ]),
              ),
            );
          }(),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}
