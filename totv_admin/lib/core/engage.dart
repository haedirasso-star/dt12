part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  المحادثة · التوقعات · الدعوات · الرسائل التلقائية
//  كل الأوامر عبر دالة push (تتحقق من بريدك في ADMIN_EMAILS) — لا تحتاج
//  ربط قاعدة الاشتراكات، ولا مفاتيح سرية داخل التطبيق.
// ════════════════════════════════════════════════════════════════════
class Engage {
  static final unread = Live<int>(Prefs.p.getInt('chat_unread_admin') ?? 0);
  static final rev = Live<int>(0);       // رسالة جديدة وصلت (إشعار)
  static String openRoom = '';           // المحادثة المفتوحة الآن

  static Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> body = const {}]) async {
    final r = await PushApi.send({...body, 'action': action});
    if (r.ok && r.body is Map) return Map<String, dynamic>.from(r.body as Map);
    final e = r.body is Map ? '${(r.body as Map)['error'] ?? ''}' : '';
    if (r.code == 403) throw Exception('بريدك غير مضاف في ADMIN_EMAILS في أسرار دالة push');
    if (r.code == 404) throw Exception('دالة push غير منشورة — شغّل Deploy push من GitHub');
    if (e.isNotEmpty) throw Exception(e);
    throw Exception(PushApi.explain(r));
  }

  static void setUnread(int n) {
    unread.value = n;
    Prefs.p.setInt('chat_unread_admin', n);
  }

  /// إشعار رسالة جديدة من مستخدم
  static void onPush(String uid) {
    rev.value++;
    if (uid.isNotEmpty && uid == openRoom) return;
    setUnread(unread.value + 1);
  }

  // ── المحادثة ────────────────────────────────────────────────────
  static Future<List<ChatThread>> threads({String q = '', bool unreadOnly = false}) async {
    final r = await call('admin_threads', {'q': q, 'unread': unreadOnly, 'limit': 150});
    final l = r.l('threads').map((e) => ChatThread(Map<String, dynamic>.from(e as Map))).toList();
    if (q.isEmpty && !unreadOnly) {
      setUnread(l.fold<int>(0, (a, t) => a + t.unreadAdmin));
      await DiskCache.write('chat_threads', l.map((t) => t.r).toList());
    }
    return l;
  }

  static Future<List<ChatThread>> cachedThreads() async {
    final c = await DiskCache.read('chat_threads');
    if (c is! List) return [];
    return c.map((e) => ChatThread(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<(List<AdminMsg>, ChatThread?)> messages(String uid, {int before = 0}) async {
    final r = await call('admin_messages', {'uid': uid, if (before > 0) 'before': before});
    final th = r['thread'] is Map ? ChatThread(Map<String, dynamic>.from(r['thread'] as Map)) : null;
    return (r.l('messages').map((e) => AdminMsg(Map<String, dynamic>.from(e as Map))).toList(), th);
  }

  static Future<AdminMsg?> send(String uid, String text, {String email = '', String name = '', bool auto = false,
      String kind = 'text', String title = ''}) async {
    final r = await call('admin_send', {'uid': uid, 'text': text, 'email': email, 'name': name, 'auto': auto,
      'kind': kind, if (title.isNotEmpty) 'title': title});
    return r['message'] is Map ? AdminMsg(Map<String, dynamic>.from(r['message'] as Map)) : null;
  }

  static Future<int> sendMany(List<String> uids, String text, {String title = ''}) async {
    final r = await call('admin_send', {'uids': uids, 'text': text, if (title.isNotEmpty) 'title': title});
    return r.i('count');
  }

  /// رسالة تلقائية دون إيقاف العمل إن فشلت
  static Future<void> auto(String uid, String text, {String kind = 'auto', String title = '', String email = '', String name = ''}) async {
    if (uid.isEmpty || uid == 'guest') return;
    try { await send(uid, text, auto: true, kind: kind, title: title, email: email, name: name); }
    catch (e) { CrashLog.add('auto msg: $e'); }
  }

  static bool get autoActivateMsg => Prefs.p.getBool('auto_msg_activate') ?? true;
  static bool get autoExpiringMsg => Prefs.p.getBool('auto_msg_expiring') ?? true;
  static bool get autoComplaintMsg => Prefs.p.getBool('auto_msg_complaint') ?? true;

  /// بعد أي تفعيل ناجح: رسالة للمشترك + جائزة الدعوة إن وُجدت
  static Future<void> afterActivation({required String uid, String email = '', String name = '', required int days,
      DateTime? expiry, bool paid = true}) async {
    if (uid.isEmpty || uid == 'guest') return;
    if (autoActivateMsg) {
      await auto(uid,
          '✅ تم تفعيل اشتراكك لمدة $days ${days == 1 ? 'يوم' : 'يوماً'}${expiry != null ? '، ينتهي في ${Fmt.date(expiry)}' : ''}.\n'
          'مشاهدة ممتعة! إن واجهت أي مشكلة اكتب لنا هنا.',
          kind: 'auto', title: '✅ تم تفعيل اشتراكك', email: email, name: name);
    }
    if (!paid) return;
    try {
      final r = await call('ref_on_order', {'uid': uid});
      final ref = r['referral'];
      if (ref is! Map) return;
      final m = Map<String, dynamic>.from(ref);
      if (m.str('status') != 'subscribed') return;
      final who = m.str('referrer_name').isNotEmpty ? m.str('referrer_name') : m.str('referrer_email');
      BotLog.add('referral', '🎁 دعوة ناجحة: $who', '${name.isEmpty ? email : name} اشترك بكوده');
      if (!await UI.confirm('🎁 هذا المشترك جاء بدعوة',
          '${name.isEmpty ? email : name} اشترك بكود $who.\nمنح الداعي ${Rewards.refDays} يوماً الآن؟\n(يبقى في «الجوائز» إن أجّلت)', ok: 'منح الآن')) return;
      await Rewards.grantReferral(m);
    } catch (e) { CrashLog.add('ref on order: $e'); }
  }
}

class ChatThread {
  final Map<String, dynamic> r;
  ChatThread(this.r);
  String get uid => r.str('uid');
  String get email => r.str('email');
  String get name => r.str('name');
  String get label => name.isNotEmpty ? name : (email.isNotEmpty ? email : uid);
  String get last => r.str('last_text');
  String get lastFrom => r.str('last_from');
  DateTime? get at => r.d('last_at');
  int get unreadAdmin => r.i('unread_admin');
}

class AdminMsg {
  final Map<String, dynamic> r;
  AdminMsg(this.r);
  int get id => r.i('id');
  String get sender => r.str('sender');
  String get body => r.str('body');
  String get kind => r.str('kind');
  DateTime get at => r.d('created_at') ?? DateTime.now();
  bool get fromUser => sender == 'user';
}

// ════════════════════════════════════════════════════════════════════
//  الجوائز: يوم مجاني للتوقع الصحيح · 16 يوماً للدعوة الناجحة
// ════════════════════════════════════════════════════════════════════
class Rewards {
  static const winDays = 1;
  static const refDays = 16;

  /// إضافة أيام لمستخدم: تمديد إن كان مشتركاً، وإلا تفعيل من المخزون
  static Future<bool> grantDays({required String uid, String email = '', String name = '', required int days}) async {
    if (uid.isEmpty) return false;
    if (!Supa.linked.value) { UI.toast('اربط قاعدة الاشتراكات أولاً (المزيد ← ربط قاعدة الاشتراكات)', error: true); return false; }
    DateTime? before;
    try {
      final r = await Supa.call('admin_lookup', {'p_email': uid});
      if (r['subscription'] is Map) before = Map<String, dynamic>.from(r['subscription'] as Map).d('expiry_date');
    } catch (e) { CrashLog.add('grant lookup: $e'); }

    if (before != null && before.isAfter(DateTime.now())) {
      try {
        final r = await Supa.call('admin_extend', {'p_uid': uid, 'p_days': days});
        final exp = r.d('expiry');
        if (exp != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'subscription': {'expiry_date': Timestamp.fromDate(exp), 'updated_at': FieldValue.serverTimestamp()},
            'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
        BotLog.add('prize', '🎁 جائزة ${name.isEmpty ? email : name}', '+$days يوم · ينتهي ${Fmt.date(exp)}');
        unawaited(Subs.refresh().catchError((_) {}));
        return true;
      } catch (e) { UI.err(e); return false; }
    }
    // غير مشترك ⇐ تفعيل من المخزون بعدد أيام الجائزة
    await AutoActivateSheet.open(uid: uid, email: email, name: name, days: days, quiet: true);
    try {
      final r = await Supa.call('admin_lookup', {'p_email': uid});
      final after = r['subscription'] is Map ? Map<String, dynamic>.from(r['subscription'] as Map).d('expiry_date') : null;
      return after != null && after.isAfter(DateTime.now()) && (before == null || after.isAfter(before));
    } catch (_) { return false; }
  }

  static Future<bool> grantWin(Map<String, dynamic> w) async {
    final ok = await grantDays(uid: w.str('uid'), email: w.str('email'), name: w.str('name'), days: winDays);
    if (!ok) return false;
    try {
      await Engage.call('admin_reward_done', {'kind': 'win', 'uid': w.str('uid'), 'match_id': w.i('match_id'), 'days': winDays});
      UI.toast('أُضيف يوم مجاني لـ ${w.str('name').isEmpty ? w.str('email') : w.str('name')} ✅');
      return true;
    } catch (e) { UI.err(e); return false; }
  }

  static Future<bool> grantReferral(Map<String, dynamic> r) async {
    final ok = await grantDays(uid: r.str('referrer_uid'), email: r.str('referrer_email'), name: r.str('referrer_name'), days: refDays);
    if (!ok) return false;
    try {
      await Engage.call('admin_reward_done', {'kind': 'ref', 'uid': r.str('referrer_uid'), 'friend_uid': r.str('friend_uid'), 'days': refDays});
      UI.toast('أُضيف $refDays يوماً للداعي ✅');
      return true;
    } catch (e) { UI.err(e); return false; }
  }
}

// ════════════════════════════════════════════════════════════════════
//  شبكة أمان للطلبات: فحص خفيف كل 10 دقائق في الخلفية
//  (للطلبات التي لم يصل إشعارها — مثل مستخدمي النسخ القديمة من التطبيق)
// ════════════════════════════════════════════════════════════════════
class OrderWatch {
  static const alarmId = 7702;
  static const _k = 'orders_notified_v1';
  static bool get enabled => Prefs.p.getBool('order_watch') ?? true;

  static Future<void> mark(Iterable<String> ids) async {
    try {
      final s = Prefs.p.getStringList(_k) ?? [];
      var changed = false;
      for (final id in ids) {
        if (!s.contains(id)) { s.insert(0, id); changed = true; }
      }
      if (changed) await Prefs.p.setStringList(_k, s.take(400).toList());
    } catch (_) {}
  }

  static Future<void> schedule() async {
    try {
      await AndroidAlarmManager.initialize();
      if (!enabled) { await AndroidAlarmManager.cancel(alarmId); return; }
      await AndroidAlarmManager.periodic(const Duration(minutes: 10), alarmId, orderAlarmCallback,
          allowWhileIdle: true, wakeup: true, rescheduleOnReboot: true);
    } catch (e) { CrashLog.add('order watch schedule: $e'); }
  }

  /// يعيد عدد الطلبات الجديدة التي لم يُنبَّه عنها
  static Future<int> check() async {
    try { await Prefs.p.reload(); } catch (_) {}
    final rows = await FsRest.query('orders',
        select: ['order_id', 'name', 'plan_title', 'price', 'method', 'status', 'type'],
        whereEq: {'status': 'pending'}, limit: 30);
    final seen = (Prefs.p.getStringList(_k) ?? []).toSet();
    final fresh = rows.where((m) => !seen.contains('${m['_id']}')).toList();
    if (fresh.isEmpty) return 0;
    await AdminPush.ensureLocal();
    final f = fresh.first;
    await AdminPush.show(
      fresh.length == 1 ? '📥 لديك طلب اشتراك — يرجى التفعيل' : '📥 لديك ${fresh.length} طلبات اشتراك — يرجى التفعيل',
      [f.str('name'), f.str('plan_title'), if (f.str('price').isNotEmpty) '${f.str('price')} د.ع', f.str('method')]
          .where((x) => x.isNotEmpty).join(' • '),
      payload: 'orders');
    await mark(fresh.map((m) => '${m['_id']}'));
    return fresh.length;
  }
}

@pragma('vm:entry-point')
Future<void> orderAlarmCallback() async {
  try {
    DartPluginRegistrant.ensureInitialized();
    await Prefs.init();
    if (!OrderWatch.enabled) return;
    if (!Boot.ok) await Boot.firebase();
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null).timeout(const Duration(seconds: 12));
    }
    await OrderWatch.check();
  } catch (e) {
    try { CrashLog.add('order watch: $e'); } catch (_) {}
  }
}
