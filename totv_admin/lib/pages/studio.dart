part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🎬 استوديو البث — إدارة قناة TOTV Live
//  ──────────────────────────────────────────────────────────────────
//  • ابدأ / أنهِ البث بضغطة، مع إشعار «🔴 بدأ البث» لكل المستخدمين
//  • أظهر / أخفِ القناة في التطبيق فوراً
//  • اسم القناة، العنوان، الوصف، البوستر (رفع من الهاتف)
//  • رابط البث الرئيسي + احتياطي — يعمل في مشغّل التطبيق مباشرة
//  • فحص صحّة البث كل 10 ثوانٍ (يعمل؟ يتقدّم؟ كم مقطعاً؟)
//  • إعدادات OBS / Larix جاهزة للنسخ (محفوظة على هذا الهاتف فقط)
//
//  المستند: app_config/live_channel
// ════════════════════════════════════════════════════════════════════
class LiveStudio {
  static final doc = FirebaseFirestore.instance.collection('app_config').doc('live_channel');

  static Future<void> save(Map<String, dynamic> m) =>
      doc.set({...m, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  /// رفع البوستر إلى مستودع الرياضة (نفس مفتاح GitHub الخاص بالإعلانات)
  static Future<String> uploadPoster(Uint8List bytes) async {
    if (!GhPromos.ready) throw Exception('اضبط مفتاح GitHub أولاً من صفحة «الإعلانات»');
    final name = 'poster_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final url = 'https://api.github.com/repos/${GhPromos.repo}/contents/live/$name';
    final r = await Net.req('PUT', url, headers: GhPromos._h, timeout: const Duration(seconds: 90), body: {
      'message': 'بوستر البث: $name (من تطبيق الإدارة)',
      'content': base64Encode(bytes),
    });
    if (!r.ok) throw Exception(GhPromos._err(r));
    return 'https://raw.githubusercontent.com/${GhPromos.repo}/HEAD/live/$name';
  }
}

/// نتيجة فحص رابط البث
class StreamHealth {
  final int level;        // 2 يعمل · 1 تحذير · 0 لا يعمل · -1 غير معروف
  final String title, detail;
  final int seq;
  const StreamHealth(this.level, this.title, this.detail, [this.seq = -1]);

  static Future<StreamHealth> check(String url, {int lastSeq = -1}) async {
    if (!url.startsWith('http')) return const StreamHealth(0, 'لا يوجد رابط', 'أضف رابط البث أولاً');
    if (!url.toLowerCase().contains('.m3u8')) {
      return const StreamHealth(-1, 'لا يمكن فحص هذا النوع', 'الفحص لروابط m3u8 فقط — جرّب التشغيل من التطبيق');
    }
    final sw = Stopwatch()..start();
    try {
      var r = await Net.req('GET', url, timeout: const Duration(seconds: 10));
      if (!r.ok) {
        return StreamHealth(0, 'الرابط لا يستجيب (${r.code})',
            r.code == 404 ? 'لا يوجد بث على هذا المسار — هل بدأت البث من OBS؟' : 'تحقّق من السيرفر والرابط');
      }
      var body = r.raw;
      if (!body.trimLeft().startsWith('#EXTM3U')) return const StreamHealth(0, 'ليس ملف بث صالحاً', 'الرابط لا يعيد قائمة m3u8');
      var variants = 0;
      if (body.contains('#EXT-X-STREAM-INF')) {
        // قائمة رئيسية ⇐ نفحص أول جودة
        final lines = body.split('\n').map((l) => l.trim()).toList();
        variants = lines.where((l) => l.startsWith('#EXT-X-STREAM-INF')).length;
        final first = lines.firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
        if (first.isEmpty) return const StreamHealth(0, 'القائمة فارغة', 'لا توجد جودات داخل الرابط');
        final sub = Uri.parse(url).resolve(first).toString();
        r = await Net.req('GET', sub, timeout: const Duration(seconds: 10));
        if (!r.ok) return StreamHealth(0, 'الجودة لا تستجيب (${r.code})', 'السيرفر يعمل لكن البث متوقف');
        body = r.raw;
      }
      final ms = sw.elapsedMilliseconds;
      final segs = '#EXTINF'.allMatches(body).length;
      final td = int.tryParse(RegExp(r'#EXT-X-TARGETDURATION:(\d+)').firstMatch(body)?.group(1) ?? '') ?? 0;
      final seq = int.tryParse(RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)').firstMatch(body)?.group(1) ?? '') ?? -1;
      final ended = body.contains('#EXT-X-ENDLIST');
      final info = [
        if (variants > 0) '$variants جودة',
        '$segs مقطع',
        if (td > 0) 'مقطع $td ث',
        'استجابة $ms ms',
      ].join(' · ');
      if (segs == 0) return StreamHealth(1, 'البث لم يبدأ بعد', 'الرابط موجود بلا مقاطع — ابدأ البث من OBS', seq);
      if (ended) return StreamHealth(1, 'ملف مسجّل (ليس مباشراً)', info, seq);
      if (lastSeq >= 0 && seq >= 0 && seq == lastSeq) {
        return StreamHealth(1, 'البث متجمّد', 'لا مقاطع جديدة منذ الفحص السابق — تحقّق من OBS والإنترنت · $info', seq);
      }
      return StreamHealth(ms > 2500 ? 1 : 2, ms > 2500 ? 'يعمل لكن السيرفر بطيء' : 'البث يعمل بشكل ممتاز', info, seq);
    } catch (e) {
      return StreamHealth(0, 'تعذّر الوصول', Fmt.err(e));
    }
  }
}

class StudioPage extends StatefulWidget {
  const StudioPage({super.key});
  @override State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _name = TextEditingController(), _title = TextEditingController(), _sub = TextEditingController();
  final _poster = TextEditingController(), _url = TextEditingController(), _backup = TextEditingController();
  // إعدادات OBS — محلية على هذا الهاتف فقط (لا تُرفع لأي مكان)
  final _host = TextEditingController(), _path = TextEditingController(), _user = TextEditingController(), _pass = TextEditingController();

  StreamSubscription? _sub0;
  Map<String, dynamic> _d = {};
  bool _loading = true, _busy = false, _notify = true, _dirty = false, _upl = false;
  StreamHealth? _health;
  Timer? _tick;
  bool _checking = false;

  bool get _visible => _d['visible'] == true;
  bool get _onAir => _d['on_air'] == true;

  @override
  void initState() {
    super.initState();
    _host.text = Prefs.p.getString('studio_host') ?? '';
    _path.text = Prefs.p.getString('studio_path') ?? 'game';
    _user.text = Prefs.p.getString('studio_user') ?? 'totv';
    _pass.text = Prefs.p.getString('studio_pass') ?? '';
    _sub0 = LiveStudio.doc.snapshots().listen((s) {
      final d = s.data() ?? {};
      final first = _loading;
      setState(() { _d = d; _loading = false; });
      if (first || !_dirty) _fill(d);
    }, onError: (e) { UI.err(e); if (mounted) setState(() => _loading = false); });
    _tick = Timer.periodic(const Duration(seconds: 10), (_) { if (_onAir || _url.text.isNotEmpty) _check(); });
    Future.delayed(const Duration(milliseconds: 800), _check);
  }

  void _fill(Map<String, dynamic> d) {
    String s(String k) => '${d[k] ?? ''}';
    _name.text = s('name').isEmpty ? 'TOTV Live' : s('name');
    _title.text = s('title'); _sub.text = s('subtitle'); _poster.text = s('poster');
    _url.text = s('url'); _backup.text = s('backup_url');
    _dirty = false;
  }

  @override
  void dispose() {
    _sub0?.cancel(); _tick?.cancel();
    for (final c in [_name, _title, _sub, _poster, _url, _backup, _host, _path, _user, _pass]) { c.dispose(); }
    super.dispose();
  }

  Map<String, dynamic> get _fields => {
    'name': _name.text.trim().isEmpty ? 'TOTV Live' : _name.text.trim(),
    'title': _title.text.trim(), 'subtitle': _sub.text.trim(),
    'poster': _poster.text.trim(), 'url': _url.text.trim(), 'backup_url': _backup.text.trim(),
  };

  String? _validate() {
    final u = _url.text.trim(), b = _backup.text.trim(), p = _poster.text.trim();
    if (u.isEmpty) return 'أضف رابط البث';
    if (!u.startsWith('http')) return 'رابط البث يجب أن يبدأ بـ http:// أو https://';
    if (b.isNotEmpty && !b.startsWith('http')) return 'الرابط الاحتياطي غير صحيح';
    if (p.isNotEmpty && !p.startsWith('https://')) return 'رابط البوستر يجب أن يبدأ بـ https://';
    return null;
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    final h = await StreamHealth.check(_url.text.trim(), lastSeq: _health?.seq ?? -1);
    _checking = false;
    if (mounted) setState(() => _health = h);
  }

  Future<void> _saveInfo() async {
    final e = _validate(); if (e != null && _url.text.trim().isNotEmpty) { UI.toast(e, error: true); return; }
    setState(() => _busy = true);
    try { await LiveStudio.save(_fields); _dirty = false; UI.toast('حُفظت معلومات القناة ✅'); } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _goLive() async {
    final e = _validate(); if (e != null) { UI.toast(e, error: true); return; }
    await _check();
    final h = _health;
    if (h != null && h.level == 0 &&
        !await UI.confirm('البث لا يعمل الآن', '${h.title}\n${h.detail}\n\nهل تريد البدء على أي حال؟', ok: 'ابدأ رغم ذلك', danger: true)) return;
    if (!await UI.confirm('🔴 بدء البث المباشر؟',
        'ستظهر القناة لكل المستخدمين بعلامة «مباشر»${_notify ? '\nوسيُرسل إشعار لكل المستخدمين' : ''}.', ok: 'ابدأ البث')) return;
    setState(() => _busy = true);
    try {
      await LiveStudio.save({..._fields, 'visible': true, 'on_air': true, 'started_at': FieldValue.serverTimestamp()});
      _dirty = false;
      if (_notify) {
        final name = _name.text.trim().isEmpty ? 'TOTV Live' : _name.text.trim();
        final t = _title.text.trim();
        final r = await PushApi.send({
          'action': 'broadcast', 'topic': 'all_users', 'kind': 'live',
          'title': '🔴 بدأ البث الآن على $name',
          'body': t.isEmpty ? 'البث المباشر يعمل الآن — اضغط للمشاهدة' : '$t — اضغط للمشاهدة الآن',
          'image': _poster.text.trim(),
        });
        UI.toast(r.ok ? 'البث يعمل 🔴 وأُرسل الإشعار' : 'البث يعمل 🔴 لكن الإشعار فشل: ${PushApi.explain(r)}', error: !r.ok);
      } else {
        UI.toast('البث يعمل الآن 🔴');
      }
      HapticFeedback.heavyImpact();
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _endLive() async {
    final hide = await showModalBottomSheet<bool>(context: context, backgroundColor: K.card,
      builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('إنهاء البث', style: K.h2),
        const SizedBox(height: 14),
        ListTile(leading: const Icon(Icons.pause_circle_rounded, color: K.org), title: const Text('إيقاف البث وإبقاء القناة ظاهرة'),
            subtitle: const Text('تظهر «البث متوقف» — مناسب إن ستعود قريباً', style: K.tiny), onTap: () => Navigator.pop(c, false)),
        ListTile(leading: const Icon(Icons.visibility_off_rounded, color: K.red), title: const Text('إيقاف البث وإخفاء القناة'),
            subtitle: const Text('تختفي القناة من التطبيق كلياً', style: K.tiny), onTap: () => Navigator.pop(c, true)),
      ]))));
    if (hide == null) return;
    setState(() => _busy = true);
    try { await LiveStudio.save({'on_air': false, if (hide) 'visible': false}); UI.toast(hide ? 'انتهى البث وأُخفيت القناة' : 'انتهى البث'); }
    catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleVisible(bool v) async {
    try { await LiveStudio.save({..._fields, 'visible': v}); UI.toast(v ? 'القناة ظاهرة للمستخدمين' : 'القناة مخفية'); }
    catch (e) { UI.err(e); }
  }

  Future<void> _pickPoster() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (img == null) return;
    setState(() => _upl = true);
    try {
      final url = await LiveStudio.uploadPoster(await img.readAsBytes());
      _poster.text = url; _dirty = true;
      await LiveStudio.save({'poster': url});
      _dirty = false;
      UI.toast('رُفع البوستر ✅');
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _upl = false);
  }

  void _saveObs() {
    Prefs.p.setString('studio_host', _host.text.trim());
    Prefs.p.setString('studio_path', _path.text.trim());
    Prefs.p.setString('studio_user', _user.text.trim());
    Prefs.p.setString('studio_pass', _pass.text);
    setState(() {});
  }

  String get _h => _host.text.trim().replaceAll(RegExp(r'^\w+://'), '').replaceAll(RegExp(r'/+$'), '');
  String get _p => _path.text.trim().isEmpty ? 'game' : _path.text.trim();
  String get _auth => _user.text.trim().isEmpty ? '' : '?user=${Uri.encodeComponent(_user.text.trim())}&pass=${Uri.encodeComponent(_pass.text)}';

  void _copy(String v, String what) { Clipboard.setData(ClipboardData(text: v)); UI.toast('نُسخ $what'); }

  // ───────────────────────────── الواجهة ─────────────────────────────
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('استوديو البث'), actions: [
      IconButton(tooltip: 'فحص الآن', onPressed: _check, icon: const Icon(Icons.monitor_heart_rounded)),
    ]),
    body: _loading ? const Center(child: CircularProgressIndicator(color: K.gold)) : ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        _statusCard(),
        const SizedBox(height: 12),
        _healthCard(),
        const SizedBox(height: 18),
        const Text('معلومات القناة', style: K.h3),
        const SizedBox(height: 10),
        _posterBox(),
        const SizedBox(height: 12),
        _field(_name, 'اسم القناة', hint: 'TOTV Live'),
        _field(_title, 'عنوان البث الحالي', hint: 'مثال: بطولة ببجي — النهائي'),
        _field(_sub, 'وصف قصير (اختياري)', hint: 'مثال: مع التعليق العربي'),
        const SizedBox(height: 8),
        const Text('رابط البث', style: K.h3),
        const SizedBox(height: 4),
        const Text('يقبل m3u8 و mp4 و ts وأي رابط مباشر — يعمل في مشغّل التطبيق نفسه. '
            'الاحتياطي يُستخدم تلقائياً إن تعطّل الرئيسي.', style: K.tiny),
        const SizedBox(height: 8),
        _field(_url, 'الرابط الرئيسي', hint: 'https://live.totv.app/game/index.m3u8', ltr: true,
            suffix: _h.isEmpty ? null : IconButton(tooltip: 'رابط سيرفري', icon: const Icon(Icons.auto_fix_high_rounded, color: K.gold),
                onPressed: () { _url.text = 'https://$_h/$_p/index.m3u8'; _dirty = true; _check(); setState(() {}); })),
        _field(_backup, 'رابط احتياطي (اختياري)', hint: 'https://…', ltr: true),
        const SizedBox(height: 4),
        BusyButton(label: 'حفظ المعلومات', icon: Icons.save_rounded, busy: _busy, onPressed: _saveInfo),
        const SizedBox(height: 22),
        _obsCard(),
      ],
    ),
  );

  Widget _statusCard() {
    final started = _d['started_at'] is Timestamp ? (_d['started_at'] as Timestamp).toDate() : null;
    return Box(
      gradient: _onAir ? const LinearGradient(colors: [Color(0xFF3A0B0B), Color(0xFF14141B)],
          begin: Alignment.topRight, end: Alignment.bottomLeft) : null,
      border: _onAir ? K.red.withOpacity(.5) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(
              color: _onAir ? K.red : K.t3, shape: BoxShape.circle,
              boxShadow: _onAir ? [BoxShadow(color: K.red.withOpacity(.7), blurRadius: 10)] : null)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_onAir ? 'على الهواء الآن' : 'البث متوقف', style: K.h2),
            Text(_onAir ? 'بدأ ${Fmt.ago(started)}' : (_visible ? 'القناة ظاهرة بعلامة «البث متوقف»' : 'القناة مخفية عن المستخدمين'),
                style: K.sub),
          ])),
        ]),
        const SizedBox(height: 14),
        if (!_onAir) ...[
          SizedBox(height: 54, child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: K.red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: _busy ? null : _goLive,
            icon: const Icon(Icons.sensors_rounded),
            label: const Text('ابدأ البث المباشر', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          )),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: _notify, onChanged: (v) => setState(() => _notify = v ?? true),
            contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: K.gold,
            title: const Text('أرسل إشعار «🔴 بدأ البث» لكل المستخدمين', style: K.body),
          ),
        ] else
          SizedBox(height: 50, child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: K.t1, side: const BorderSide(color: K.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: _busy ? null : _endLive,
            icon: const Icon(Icons.stop_circle_rounded, color: K.red),
            label: const Text('إنهاء البث', style: TextStyle(fontWeight: FontWeight.w800)),
          )),
        const Divider(height: 22),
        SwitchRow(
          title: 'القناة ظاهرة في التطبيق',
          sub: 'في الرئيسية وقسم الرياضة — أخفِها متى شئت',
          icon: Icons.live_tv_rounded, color: K.gold,
          value: _visible, onChanged: _toggleVisible,
        ),
      ]),
    );
  }

  Widget _healthCard() {
    final h = _health;
    final c = h == null ? K.t3 : [K.red, K.org, K.grn][h.level < 0 ? 0 : (h.level > 2 ? 2 : h.level)];
    final icon = h == null ? Icons.hourglass_top_rounded
        : h.level == 2 ? Icons.check_circle_rounded : h.level == 1 ? Icons.warning_amber_rounded
        : h.level == 0 ? Icons.error_rounded : Icons.help_rounded;
    return Box(
      padding: const EdgeInsets.all(14),
      color: c.withOpacity(.08), border: c.withOpacity(.35),
      child: Row(children: [
        Icon(icon, color: h?.level == -1 ? K.t2 : c),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(h?.title ?? 'جارٍ فحص البث…', style: K.h3),
          if (h != null) Text(h.detail, style: K.tiny.copyWith(color: K.t2)),
        ])),
        if (_checking) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: K.gold)),
      ]),
    );
  }

  Widget _posterBox() {
    final p = _poster.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(aspectRatio: 16 / 8, child: Stack(fit: StackFit.expand, children: [
          if (p.startsWith('https://'))
            Image.network(p, fit: BoxFit.cover, cacheWidth: 900,
                errorBuilder: (_, __, ___) => const ColoredBox(color: K.card2, child: Center(child: Icon(Icons.broken_image_rounded, color: K.t3))))
          else
            const ColoredBox(color: K.card2, child: Center(child: Text('لا يوجد بوستر — يُفضّل 1600×800', style: K.sub))),
          Positioned(left: 10, bottom: 10, child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: K.gold),
            onPressed: _upl ? null : _pickPoster,
            icon: _upl ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: K.gold))
                : const Icon(Icons.add_photo_alternate_rounded),
            label: Text(_upl ? 'جارٍ الرفع…' : (p.isEmpty ? 'رفع بوستر' : 'تغيير البوستر')),
          )),
        ])),
      ),
      const SizedBox(height: 8),
      _field(_poster, 'أو رابط بوستر مباشر', hint: 'https://…', ltr: true),
    ]);
  }

  Widget _obsCard() {
    final ready = _h.isNotEmpty;
    final server = 'rtmp://$_h:1935';
    final key = '$_p$_auth';
    final full = '$server/$_p$_auth';
    final watch = 'https://$_h/$_p/index.m3u8';
    Widget row(String label, String v, {bool secret = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Box(padding: const EdgeInsets.fromLTRB(12, 8, 4, 8), color: K.card2, child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: K.tiny),
          Text(secret ? v.replaceAll(RegExp(r'pass=[^&]*'), 'pass=••••••') : v, style: K.mono,
              textDirection: TextDirection.ltr, maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        IconButton(icon: const Icon(Icons.copy_rounded, size: 20, color: K.gold), onPressed: () => _copy(v, label)),
      ])),
    );
    return Box(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(children: [Icon(Icons.videocam_rounded, color: K.gold), SizedBox(width: 8), Text('إعدادات البث من جهازك', style: K.h3)]),
      const SizedBox(height: 4),
      const Text('تُحفظ على هذا الهاتف فقط. ضع بيانات سيرفر MediaMTX مرة واحدة ثم انسخ الإعدادات.', style: K.tiny),
      const SizedBox(height: 10),
      _field(_host, 'عنوان السيرفر', hint: 'live.totv.app', ltr: true, onChanged: (_) => _saveObs()),
      Row(children: [
        Expanded(child: _field(_path, 'اسم المسار', hint: 'game', ltr: true, onChanged: (_) => _saveObs())),
        const SizedBox(width: 8),
        Expanded(child: _field(_user, 'مستخدم البث', hint: 'totv', ltr: true, onChanged: (_) => _saveObs())),
      ]),
      _field(_pass, 'كلمة مرور البث', ltr: true, obscure: true, onChanged: (_) => _saveObs()),
      if (ready) ...[
        const SizedBox(height: 6),
        const Text('OBS (الكمبيوتر) ← الإعدادات ← البث ← Custom', style: K.sub),
        const SizedBox(height: 6),
        row('Server', server),
        row('Stream Key', key, secret: true),
        const SizedBox(height: 4),
        const Text('Larix Broadcaster (الهاتف) ← Connections ← رابط واحد', style: K.sub),
        const SizedBox(height: 6),
        row('URL', full, secret: true),
        const SizedBox(height: 4),
        const Text('رابط المشاهدة (يوضع تلقائياً بزر ✨ بجانب الرابط الرئيسي)', style: K.sub),
        const SizedBox(height: 6),
        row('HLS', watch),
        const SizedBox(height: 6),
        const Banner2('إعدادات OBS الموصى بها: CBR · 3000 Kbps · Keyframe 2 ث · 1280×720 · AAC 128 — '
            'وسرعة رفع الإنترنت عندك ضعف سرعة البث على الأقل.', icon: Icons.tips_and_updates_rounded),
      ],
    ]));
  }

  Widget _field(TextEditingController c, String label, {String? hint, bool ltr = false, bool obscure = false,
      Widget? suffix, ValueChanged<String>? onChanged}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c, obscureText: obscure,
      textDirection: ltr ? TextDirection.ltr : null,
      onChanged: onChanged ?? (_) { _dirty = true; },
      decoration: InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix),
    ),
  );
}
