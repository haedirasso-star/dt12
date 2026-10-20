part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🧑‍💼 الوكلاء والتارجت
// ════════════════════════════════════════════════════════════════════
class AgentsPage extends StatelessWidget {
  const AgentsPage({super.key});

  static final _col = FirebaseFirestore.instance.collection('admins');

  Future<void> _add() async {
    final email = await UI.input('بريد الوكيل', hint: 'agent@totv.com', help: 'يجب إنشاء نفس البريد وكلمة المرور في Firebase Authentication');
    if (email == null || email.isEmpty) return;
    final name = await UI.input('اسم الوكيل', hint: 'مثال: كابتن عماد');
    if (name == null || name.isEmpty) return;
    try {
      await _col.doc(email.toLowerCase()).set({'email': email.toLowerCase(), 'agent_name': name, 'role': 'agent',
        'target_limit': 0, 'target_count': 0, 'downloads_count': 0, 'added_at': FieldValue.serverTimestamp(), 'added_by': Store.by},
        SetOptions(merge: true));
      UI.toast('أُضيف الوكيل');
    } catch (e) { UI.err(e); }
  }

  Future<void> _menu(String id, Map<String, dynamic> a) async {
    final x = await UI.pick<String>(a.str('agent_name'), [
      ('name', 'تعديل الاسم', Icons.edit_rounded),
      ('target', 'تعيين التارجت', Icons.flag_rounded),
      ('dec', 'خصم من المحقق', Icons.remove_circle_rounded),
      ('reset', 'تصفير المحقق', Icons.restart_alt_rounded),
      ('dl', 'عدد التحميلات المعروض', Icons.download_rounded),
      ('del', 'حذف الوكيل', Icons.delete_rounded),
    ]);
    try {
      switch (x) {
        case 'name':
          final v = await UI.input('اسم الوكيل', initial: a.str('agent_name'));
          if (v != null && v.isNotEmpty) await _col.doc(id).set({'agent_name': v, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          break;
        case 'target':
          final v = int.tryParse(await UI.input('التارجت المطلوب', number: true, initial: '${a.i('target_limit')}') ?? '');
          if (v != null && v >= 0) await _col.doc(id).set({'target_limit': v, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          break;
        case 'dec':
          final v = int.tryParse(await UI.input('كم تخصم؟', number: true, initial: '1') ?? '');
          if (v != null && v > 0) await _col.doc(id).set({'target_count': math.max(0, a.i('target_count') - v)}, SetOptions(merge: true));
          break;
        case 'reset':
          if (await UI.confirm('تصفير المحقق؟', 'يبدأ عداد جديد من الصفر.')) await _col.doc(id).set({'target_count': 0}, SetOptions(merge: true));
          break;
        case 'dl':
          final v = int.tryParse(await UI.input('عدد التحميلات المعروض للوكيل', number: true, initial: '${a.i('downloads_count')}') ?? '');
          if (v != null && v >= 0) await _col.doc(id).set({'downloads_count': v}, SetOptions(merge: true));
          break;
        case 'del':
          if (await UI.confirm('حذف الوكيل؟', a.str('agent_name'), danger: true, ok: 'حذف')) await _col.doc(id).delete();
          break;
      }
    } catch (e) { UI.err(e); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الوكلاء')),
    floatingActionButton: FloatingActionButton(backgroundColor: K.gold, foregroundColor: Colors.black, onPressed: _add, child: const Icon(Icons.person_add_rounded)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _col.where('role', isEqualTo: 'agent').snapshots(),
      builder: (_, s) {
        if (s.hasError) return Padding(padding: const EdgeInsets.all(16), child: ErrorBox(Fmt.err(s.error!)));
        if (!s.hasData) return const Loading();
        final docs = s.data!.docs;
        if (docs.isEmpty) return const EmptyView(icon: Icons.badge_rounded, title: 'لا يوجد وكلاء', sub: 'اضغط + لإضافة أول وكيل');
        final subs = Subs.list.value;
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final d in docs) () {
            final a = d.data();
            final name = a.str('agent_name');
            final activeNow = subs.where((x) => x.active && x.agent == name).length;
            final lim = a.i('target_limit'), cnt = a.i('target_count');
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Box(
              onTap: () => _menu(d.id, a),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Avatar(name.isEmpty ? d.id : name),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.isEmpty ? '—' : name, style: K.h3),
                    Text(d.id, textDirection: TextDirection.ltr, style: K.tiny),
                  ])),
                  Pill('$activeNow فعّال', color: K.grn),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Text('التارجت: $cnt / ${lim == 0 ? '—' : lim}', style: K.sub.copyWith(color: K.t1, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (lim > 0) Text('${(cnt * 100 / lim).clamp(0, 100).round()}%', style: K.sub.copyWith(color: K.gold)),
                ]),
                const SizedBox(height: 6),
                Meter(lim == 0 ? 0 : cnt / lim, color: cnt >= lim && lim > 0 ? K.grn : K.gold, height: 8),
              ]),
            ));
          }(),
        ]);
      },
    ),
  );
}

// ════════════════════════════════════════════════════════════════════
//  📮 الشكاوى
// ════════════════════════════════════════════════════════════════════
class ComplaintsPage extends StatefulWidget {
  const ComplaintsPage({super.key});
  @override State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  String _f = 'open';
  final _col = FirebaseFirestore.instance.collection('complaints');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الشكاوى')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _col.orderBy('created', descending: true).limit(150).snapshots(),
      builder: (_, s) {
        if (s.hasError) return Padding(padding: const EdgeInsets.all(16), child: ErrorBox(Fmt.err(s.error!)));
        if (!s.hasData) return const Loading();
        final all = s.data!.docs;
        final open = all.where((d) => d.data()['status'] != 'closed').length;
        final list = all.where((d) => _f == 'all' || (_f == 'open' ? d.data()['status'] != 'closed' : d.data()['status'] == 'closed')).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          Filters<String>(value: _f, onChanged: (v) => setState(() => _f = v), items: [
            ('open', 'مفتوحة', open), ('closed', 'مغلقة', all.length - open), ('all', 'الكل', all.length)]),
          const SizedBox(height: 12),
          if (list.isEmpty) const EmptyView(icon: Icons.mark_email_read_rounded, title: 'لا شكاوى هنا'),
          for (final d in list) () {
            final c = d.data();
            final closed = c['status'] == 'closed';
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Box(
              border: closed ? null : K.org.withOpacity(.35),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Pill(c.str('category').isEmpty ? 'عام' : c.str('category'), color: K.org),
                  const SizedBox(width: 6),
                  Text(c.str('ticket'), style: K.tiny),
                  const Spacer(),
                  Text(Fmt.ago(c.d('created')), style: K.tiny),
                ]),
                const SizedBox(height: 10),
                Text(c.str('body'), style: K.body),
                const SizedBox(height: 8),
                Text('${c.str('name')} · ${c.str('email').isEmpty ? 'ضيف' : c.str('email')}', style: K.tiny),
                if (c.str('reply').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Banner2('ردّك: ${c.str('reply')}', icon: Icons.reply_rounded, color: K.grn),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ActBtn(Icons.reply_rounded, 'رد', () async {
                    final v = await UI.input('الرد على الشكوى', multiline: true, initial: c.str('reply'));
                    if (v == null) return;
                    try {
                      await _col.doc(d.id).update({'reply': v, 'replied_at': FieldValue.serverTimestamp(), 'replied_by': Store.by});
                      UI.toast('حُفظ الرد');
                      if (Engage.autoComplaintMsg && v.trim().isNotEmpty) {
                        unawaited(Engage.auto(c.str('uid'), '📩 رد الإدارة على شكواك ${c.str('ticket')}:\n${v.trim()}',
                            kind: 'complaint', title: '📩 رد على شكواك', email: c.str('email'), name: c.str('name')));
                      }
                    }
                    catch (e) { UI.err(e); }
                  }, color: K.grn),
                  ActBtn(closed ? Icons.lock_open_rounded : Icons.check_rounded, closed ? 'إعادة فتح' : 'إغلاق', () async {
                    try {
                      await _col.doc(d.id).update({'status': closed ? 'open' : 'closed', 'closed_at': FieldValue.serverTimestamp()});
                      if (!closed && Engage.autoComplaintMsg) {
                        unawaited(Engage.auto(c.str('uid'), '✅ أُغلقت شكواك ${c.str('ticket')} بعد حلّها. إن استمرت المشكلة اكتب لنا هنا.',
                            kind: 'complaint', title: '✅ تم حل شكواك', email: c.str('email'), name: c.str('name')));
                      }
                    }
                    catch (e) { UI.err(e); }
                  }),
                  if (c.str('uid').isNotEmpty && c.str('uid') != 'guest')
                    ActBtn(Icons.forum_rounded, 'محادثة', () => Nav.push(ChatRoomPage(uid: c.str('uid'), email: c.str('email'), name: c.str('name')))),
                  if (c.str('uid').isNotEmpty && c.str('uid') != 'guest')
                    ActBtn(Icons.person_rounded, 'ملف المستخدم', () => Nav.push(MemberPage(uid: c.str('uid'), email: c.str('email')))),
                ]),
              ]),
            ));
          }(),
        ]);
      },
    ),
  );
}
