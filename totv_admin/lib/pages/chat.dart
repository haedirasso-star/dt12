part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  المحادثات مع المستخدمين — أبيض/أسود، واضحة ومرتبة
//  • قائمة المحادثات محفوظة على الهاتف وتتحدث عند فتحها أو عند وصول رسالة
//  • كل رسالة تصل المستخدم كإشعار فوري
//  • قوالب ردود جاهزة + رسائل تلقائية (التفعيل · قرب الانتهاء · الشكاوى)
// ════════════════════════════════════════════════════════════════════
const _cBg = Colors.black;
const _cPanel = Color(0xFF141416);
const _cStroke = Color(0xFF26262A);

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});
  @override State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final _q = TextEditingController();
  List<ChatThread> _list = [];
  bool _loading = true, _unreadOnly = false;
  String _err = '';
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    Engage.rev.addListener(_onPush);
    Engage.cachedThreads().then((c) { if (mounted && _list.isEmpty && c.isNotEmpty) setState(() => _list = c); });
    _load();
  }

  @override
  void dispose() { Engage.rev.removeListener(_onPush); _deb?.cancel(); _q.dispose(); super.dispose(); }

  void _onPush() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _err = ''; });
    try {
      final l = await Engage.threads(q: _q.text.trim(), unreadOnly: _unreadOnly);
      if (mounted) setState(() { _list = l; _err = ''; });
    } catch (e) {
      if (mounted) setState(() => _err = Fmt.err(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _newChat() async {
    final v = await UI.input('محادثة جديدة', hint: 'البريد أو UID', help: 'اكتب بريد المستخدم كما سجّل في التطبيق', ok: 'فتح');
    final q = (v ?? '').trim();
    if (q.isEmpty) return;
    try {
      final users = FirebaseFirestore.instance.collection('users');
      String uid = '', email = '', name = '';
      final byId = await users.doc(q).get();
      if (byId.exists) {
        uid = byId.id; email = '${byId.data()?['email'] ?? ''}'; name = '${byId.data()?['display_name'] ?? ''}';
      } else {
        final s = await users.where('email', isEqualTo: q.toLowerCase()).limit(1).get();
        if (s.docs.isNotEmpty) {
          uid = s.docs.first.id; email = '${s.docs.first.data()['email'] ?? ''}'; name = '${s.docs.first.data()['display_name'] ?? ''}';
        }
      }
      if (uid.isEmpty) { UI.toast('لا يوجد مستخدم بهذا البريد', error: true); return; }
      await Nav.push(ChatRoomPage(uid: uid, email: email, name: name));
      _load(silent: true);
    } catch (e) { UI.err(e); }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _list.fold<int>(0, (a, t) => a + t.unreadAdmin);
    return Scaffold(
      backgroundColor: _cBg,
      appBar: AppBar(
        backgroundColor: _cBg,
        title: const Text('المحادثات'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.white, foregroundColor: Colors.black,
        onPressed: _newChat,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('محادثة جديدة', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: Colors.black, backgroundColor: Colors.white,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 100), children: [
          SearchBox(controller: _q, hint: 'ابحث بالاسم أو البريد', onChanged: (_) {
            _deb?.cancel();
            _deb = Timer(const Duration(milliseconds: 500), () => _load(silent: true));
          }),
          const SizedBox(height: 10),
          Row(children: [
            _chip('الكل', !_unreadOnly, () { setState(() => _unreadOnly = false); _load(); }),
            const SizedBox(width: 8),
            _chip(unread > 0 ? 'غير مقروءة ($unread)' : 'غير مقروءة', _unreadOnly, () { setState(() => _unreadOnly = true); _load(); }),
            const Spacer(),
            IconButton(
              tooltip: 'الرسائل التلقائية',
              onPressed: () => Nav.push(const AutoMessagesPage()),
              icon: const Icon(Icons.auto_mode_rounded, color: Colors.white70)),
          ]),
          const SizedBox(height: 6),
          if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: ErrorBox(_err, onRetry: _load)),
          if (_loading && _list.isEmpty) const Padding(padding: EdgeInsets.only(top: 60), child: Loading(text: 'جاري تحميل المحادثات…')),
          if (!_loading && _list.isEmpty && _err.isEmpty)
            const EmptyView(icon: Icons.forum_outlined, title: 'لا محادثات بعد',
                sub: 'رسائل المستخدمين من «المزيد ← الرسائل» تظهر هنا مع إشعار فوري'),
          for (final t in _list) _tile(t),
        ]),
      ),
    );
  }

  Widget _chip(String l, bool on, VoidCallback f) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: f,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: on ? Colors.white : _cPanel, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? Colors.white : _cStroke)),
      child: Text(l, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: on ? Colors.black : Colors.white70)),
    ),
  );

  Widget _tile(ChatThread t) {
    final un = t.unreadAdmin;
    final prefix = t.lastFrom == 'user' ? '' : (t.lastFrom == 'auto' ? '🤖 ' : 'أنت: ');
    return InkWell(
      onTap: () async {
        await Nav.push(ChatRoomPage(uid: t.uid, email: t.email, name: t.name));
        _load(silent: true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _cStroke))),
        child: Row(children: [
          Avatar(t.label, size: 48),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15.5, fontWeight: un > 0 ? FontWeight.w900 : FontWeight.w700, color: Colors.white))),
              Text(_when(t.at), style: TextStyle(fontSize: 11.5, color: un > 0 ? Colors.white : Colors.white38,
                  fontWeight: un > 0 ? FontWeight.w800 : FontWeight.w500)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Expanded(child: Text('$prefix${t.last}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: un > 0 ? Colors.white : Colors.white54, height: 1.4))),
              if (un > 0) Container(
                margin: const EdgeInsetsDirectional.only(start: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Text('$un', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ]),
          ])),
        ]),
      ),
    );
  }

  static String _when(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    if (DateUtils.isSameDay(d, now)) return Fmt.time(d);
    if (now.difference(d).inDays < 7) return Fmt.weekday(d);
    return Fmt.dateShort(d);
  }
}

// ════════════════════════════════════════════════════════════════════
class ChatRoomPage extends StatefulWidget {
  final String uid, email, name;
  const ChatRoomPage({super.key, required this.uid, this.email = '', this.name = ''});
  @override State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  List<AdminMsg> _list = [];
  bool _loading = true, _sending = false, _more = true, _loadingMore = false;
  String _err = '', _email = '', _name = '';

  static const _defaults = [
    'مرحباً 👋 كيف يمكننا مساعدتك؟',
    '✅ تم تفعيل اشتراكك، مشاهدة ممتعة!',
    'جرّب: أغلق التطبيق تماماً ثم افتحه، وتأكد من اتصال الإنترنت.',
    'أرسل لنا صورة من المشكلة لنساعدك بسرعة.',
    '⏰ اشتراكك ينتهي قريباً — جدّد من «المزيد ← اشترك» حتى لا ينقطع البث.',
    '📩 تم استلام شكواك وجاري العمل عليها.',
    '✅ تم حل المشكلة. إن تكررت راسلنا هنا.',
  ];

  @override
  void initState() {
    super.initState();
    _email = widget.email; _name = widget.name;
    Engage.openRoom = widget.uid;
    Engage.rev.addListener(_onPush);
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    if (Engage.openRoom == widget.uid) Engage.openRoom = '';
    Engage.rev.removeListener(_onPush);
    _ctl.dispose(); _scroll.dispose();
    super.dispose();
  }

  void _onPush() => _load(silent: true);

  void _onScroll() {
    if (!_more || _loadingMore || _list.isEmpty) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _older();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _err = ''; });
    try {
      final (l, th) = await Engage.messages(widget.uid);
      if (!mounted) return;
      setState(() {
        _list = l; _more = l.length >= 50; _err = '';
        if (th != null) { if (_email.isEmpty) _email = th.email; if (_name.isEmpty) _name = th.name; }
      });
    } catch (e) { if (mounted && !silent) setState(() => _err = Fmt.err(e)); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _older() async {
    _loadingMore = true;
    try {
      final (l, _) = await Engage.messages(widget.uid, before: _list.last.id);
      if (mounted) setState(() { _list.addAll(l); _more = l.length >= 50; });
    } catch (_) {}
    _loadingMore = false;
  }

  Future<void> _send() async {
    final t = _ctl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final m = await Engage.send(widget.uid, t, email: _email, name: _name);
      HapticFeedback.selectionClick();
      _ctl.clear();
      if (mounted && m != null) setState(() => _list.insert(0, m));
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _sending = false);
  }

  List<String> get _templates => [...(Prefs.p.getStringList('chat_templates') ?? []), ..._defaults];

  Future<void> _pickTemplate() async {
    final name = _name.isEmpty ? '' : _name.split(' ').first;
    final v = await UI.pick<String>('ردود جاهزة', [
      for (final t in _templates) (t, t, null),
      ('__add', '＋ إضافة قالب جديد', Icons.add_rounded),
    ]);
    if (v == null) return;
    if (v == '__add') {
      final n = await UI.input('قالب جديد', multiline: true, hint: 'نص الرد الجاهز', ok: 'حفظ');
      if (n == null || n.trim().isEmpty) return;
      await Prefs.p.setStringList('chat_templates', [n.trim(), ...(Prefs.p.getStringList('chat_templates') ?? [])].take(20).toList());
      UI.toast('حُفظ القالب');
      return;
    }
    final txt = v.startsWith('مرحباً') && name.isNotEmpty ? v.replaceFirst('مرحباً', 'مرحباً $name') : v;
    _ctl.text = txt;
    _ctl.selection = TextSelection.collapsed(offset: txt.length);
  }

  @override
  Widget build(BuildContext context) {
    final label = _name.isNotEmpty ? _name : (_email.isNotEmpty ? _email : widget.uid);
    return Scaffold(
      backgroundColor: _cBg,
      appBar: AppBar(
        backgroundColor: _cBg,
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Nav.push(MemberPage(uid: widget.uid, email: _email)),
          child: Row(children: [
            Avatar(label, size: 38),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (_email.isNotEmpty && _name.isNotEmpty)
                Text(_email, maxLines: 1, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
            ])),
          ]),
        ),
        actions: [
          IconButton(tooltip: 'ملف المشترك', onPressed: () => Nav.push(MemberPage(uid: widget.uid, email: _email)),
              icon: const Icon(Icons.person_rounded)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: _cStroke)),
      ),
      body: Column(children: [
        Expanded(child: _body()),
        _composer(),
      ]),
    );
  }

  Widget _body() {
    if (_loading && _list.isEmpty) return const Loading();
    if (_err.isNotEmpty && _list.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: ErrorBox(_err, onRetry: _load));
    if (_list.isEmpty) {
      return const EmptyView(icon: Icons.chat_bubble_outline_rounded, title: 'لا رسائل بعد',
          sub: 'اكتب أول رسالة — تصل المستخدم كإشعار فوري');
    }
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      itemCount: _list.length,
      itemBuilder: (_, i) {
        final m = _list[i];
        final older = i + 1 < _list.length ? _list[i + 1] : null;
        final newDay = older == null || !DateUtils.isSameDay(older.at, m.at);
        return Column(children: [
          if (newDay) Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: _cPanel, borderRadius: BorderRadius.circular(10)),
              child: Text(Fmt.dayLabel(m.at), style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w700)),
            ),
          ),
          _bubble(m, older),
        ]);
      },
    );
  }

  Widget _bubble(AdminMsg m, AdminMsg? prev) {
    final me = !m.fromUser;       // رسائل الإدارة (والتلقائية) على جهة البداية
    final auto = m.sender == 'auto';
    final tight = prev != null && prev.sender == m.sender && m.at.difference(prev.at).inMinutes < 3;
    return Padding(
      padding: EdgeInsets.only(top: tight ? 3 : 10),
      child: Align(
        alignment: me ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 6),
            decoration: BoxDecoration(
              color: me ? (auto ? const Color(0xFF1F1F23) : Colors.white) : _cPanel,
              border: me && !auto ? null : Border.all(color: auto ? Colors.white24 : _cStroke),
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(16), topEnd: const Radius.circular(16),
                bottomStart: Radius.circular(me ? 4 : 16), bottomEnd: Radius.circular(me ? 16 : 4),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (auto) Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('🤖 تلقائية${_kindAr(m.kind)}', style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w700)),
              ),
              SelectableText(m.body, style: TextStyle(fontSize: 14.5, height: 1.55,
                  color: me && !auto ? Colors.black : Colors.white)),
              const SizedBox(height: 2),
              Align(alignment: AlignmentDirectional.centerEnd,
                child: Text(Fmt.time(m.at), textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 10.5, color: me && !auto ? Colors.black45 : Colors.white38))),
            ]),
          ),
        ),
      ),
    );
  }

  static String _kindAr(String k) => switch (k) {
        'prize' => ' · جائزة',
        'expiring' => ' · قرب الانتهاء',
        'complaint' => ' · شكوى',
        _ => '',
      };

  Widget _composer() => Container(
    padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
    decoration: const BoxDecoration(color: _cBg, border: Border(top: BorderSide(color: _cStroke))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      SizedBox(width: 44, height: 48, child: IconButton(
        tooltip: 'ردود جاهزة', onPressed: _pickTemplate,
        icon: const Icon(Icons.bolt_rounded, color: Colors.white70))),
      Expanded(child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: _cPanel, borderRadius: BorderRadius.circular(24), border: Border.all(color: _cStroke)),
        child: TextField(
          controller: _ctl, minLines: 1, maxLines: 6, maxLength: 1500,
          style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.white),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
            filled: false, counterText: '', isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 13),
            hintText: 'اكتب ردك…', hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
      )),
      const SizedBox(width: 6),
      SizedBox(width: 48, height: 48, child: Material(
        color: Colors.white, shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _sending ? null : _send,
          child: Center(child: _sending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black))
              : const Icon(Icons.send_rounded, color: Colors.black, size: 22)),
        ),
      )),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════
//  إعدادات الرسائل التلقائية
// ════════════════════════════════════════════════════════════════════
class AutoMessagesPage extends StatefulWidget {
  const AutoMessagesPage({super.key});
  @override State<AutoMessagesPage> createState() => _AutoMessagesPageState();
}

class _AutoMessagesPageState extends State<AutoMessagesPage> {
  bool _busy = false;

  Future<void> _set(String k, bool v) async { await Prefs.p.setBool(k, v); setState(() {}); }

  Future<void> _runExpiring() async {
    setState(() => _busy = true);
    try {
      final r = await Engage.call('admin_auto_expiring');
      await Prefs.p.setInt('auto_exp_at', DateTime.now().millisecondsSinceEpoch);
      final n = r.i('sent');
      if (n > 0) BotLog.add('auto', '✉️ تذكير $n مشترك', 'اشتراكاتهم تنتهي خلال 3 أيام');
      UI.toast(n == 0 ? 'لا يوجد مشتركون جدد ينتهون خلال 3 أيام' : 'أُرسل التذكير إلى $n مشترك ✅');
    } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final last = Prefs.p.getInt('auto_exp_at') ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل التلقائية')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Banner2('تصل كل رسالة تلقائية إلى «الرسائل» في تطبيق المستخدم مع إشعار فوري، ولا تتكرر للحدث نفسه.',
            icon: Icons.auto_mode_rounded),
        const SizedBox(height: 12),
        SwitchRow(title: 'عند التفعيل', sub: '«تم تفعيل اشتراكك لمدة … ينتهي في …»',
            icon: Icons.verified_rounded, value: Engage.autoActivateMsg, onChanged: (v) => _set('auto_msg_activate', v)),
        SwitchRow(title: 'قبل انتهاء الاشتراك بـ 3 أيام', sub: 'يرسلها البوت تلقائياً مرة واحدة لكل اشتراك (كل 6 ساعات يفحص)',
            icon: Icons.schedule_rounded, color: K.org, value: Engage.autoExpiringMsg, onChanged: (v) => _set('auto_msg_expiring', v)),
        SwitchRow(title: 'الشكاوى', sub: 'عند الرد على شكوى أو إغلاقها تصل المستخدم رسالة',
            icon: Icons.support_agent_rounded, color: K.blu, value: Engage.autoComplaintMsg, onChanged: (v) => _set('auto_msg_complaint', v)),
        const SizedBox(height: 16),
        BusyButton(label: 'أرسل تذكير قرب الانتهاء الآن', icon: Icons.send_rounded, busy: _busy, onPressed: _runExpiring),
        const SizedBox(height: 8),
        Text(last == 0 ? 'لم يُرسل بعد' : 'آخر فحص: ${Fmt.dt(DateTime.fromMillisecondsSinceEpoch(last))}',
            textAlign: TextAlign.center, style: K.tiny),
      ]),
    );
  }
}
