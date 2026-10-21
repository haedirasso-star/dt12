part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  البيانات المحفوظة على الهاتف + الطلبات المباشرة
// ════════════════════════════════════════════════════════════════════
class DiskCache {
  static Directory? _dir;
  static Future<File> _f(String name) async {
    _dir ??= await getApplicationSupportDirectory();
    return File('${_dir!.path}/cache_$name.json');
  }
  static Future<dynamic> read(String name) async {
    try { final f = await _f(name); if (!await f.exists()) return null; return jsonDecode(await f.readAsString()); }
    catch (_) { return null; }
  }
  static Future<void> write(String name, Object data) async {
    try { final f = await _f(name); await f.writeAsString(jsonEncode(data, toEncodable: Prefs._enc)); }
    catch (e) { CrashLog.add('cache $name: $e'); }
  }
  static Future<DateTime?> time(String name) async {
    try { final f = await _f(name); return await f.exists() ? await f.lastModified() : null; } catch (_) { return null; }
  }
  static Future<void> clearAll() async {
    try {
      _dir ??= await getApplicationSupportDirectory();
      for (final f in _dir!.listSync()) { if (f is File && f.path.contains('cache_')) await f.delete(); }
    } catch (_) {}
  }
}

const kPlanDays = {'monthly': 30, 'quarterly': 90, 'yearly': 365};

class AppOrder {
  final String id, src;
  final Map<String, dynamic> raw;
  AppOrder(this.id, this.src, this.raw);

  String get col => src == 'req' ? 'subscription_requests' : 'orders';
  String get uid => raw.str('uid');
  String get email => raw.str('email');
  String get name {
    for (final k in ['display_name', 'name', 'account_name']) { if (raw.str(k).isNotEmpty) return raw.str(k); }
    return email.isNotEmpty ? email : '—';
  }
  String get phone => raw.str('phone').isNotEmpty ? raw.str('phone') : raw.str('whatsapp');
  String get plan => raw.str('plan').isNotEmpty ? raw.str('plan') : raw.str('requested_plan');
  String get planTitle => raw.str('plan_title').isNotEmpty ? raw.str('plan_title') : Fmt.plan(plan);
  int get days {
    for (final k in ['days', 'requested_days', 'duration_days']) { final v = raw.i(k); if (v > 0) return v; }
    return kPlanDays[plan] ?? 30;
  }
  String get method {
    for (final k in ['method', 'payment_method', 'payment_type']) { if (raw.str(k).isNotEmpty) return raw.str(k); }
    return '';
  }
  int get amount {
    final p = raw.i('price_num');
    if (p > 0) return p;
    for (final k in ['price', 'amount', 'asia_amount']) { final v = raw.i(k); if (v > 0) return v; }
    return 0;
  }
  String get status {
    final s = raw.str('status');
    if (s == 'active' || s == 'approved') return 'approved';
    if (s == 'rejected') return 'rejected';
    return s.isEmpty ? 'pending' : s;
  }
  bool get pending => status == 'pending';
  DateTime? get created => raw.d('created') ?? raw.d('created_at');
  DateTime? get resolved => raw.d('resolved_at') ?? raw.d('rejected_at');
  bool get hasReceipt => raw.b('has_receipt') || receiptUrl.isNotEmpty || raw.str('receipt_b64').isNotEmpty;
  String get receiptUrl {
    for (final k in ['receipt_url', 'screenshot_url', 'proof_url', 'image_url', 'payment_proof']) {
      if (raw.str(k).startsWith('http')) return raw.str(k);
    }
    return '';
  }
  String get orderId => raw.str('order_id').isNotEmpty ? raw.str('order_id') : id;
  String get by => raw.str('activated_by').isNotEmpty ? raw.str('activated_by')
      : (raw.str('resolved_by').isNotEmpty ? raw.str('resolved_by') : raw.str('rejected_by'));
  /// طلب من التطبيق (وليس سجل تفعيل كتبه الأدمن)
  bool get fromApp => raw.containsKey('order_id') || raw.containsKey('method') || raw.containsKey('phone') || raw.containsKey('has_receipt');
}

class Store {
  // ── الطلبات المنتظرة: مستمع مباشر (قراءة فقط عند وصول طلب جديد) ──
  static final pending = Live<List<AppOrder>>([]);
  static final pendingReady = Live<bool>(false);
  static final history = Live<List<AppOrder>>([]);
  static DateTime? historyAt;
  static final Map<String, Uint8List?> receipts = {};
  static final List<StreamSubscription> _subs = [];
  static final Set<String> _seen = {};
  static final Map<String, bool> _first = {};
  static String role = 'admin';
  static String myEmail = '';
  static bool get isAdmin => role == 'admin';

  static Future<void> start() async {
    stop();
    myEmail = (FirebaseAuth.instance.currentUser?.email ?? '').toLowerCase();
    _first.clear();
    _seen.clear();
    // الدور: المشرف الأعلى أو admins/{email}.role
    if (!kSuperAdmins.contains(myEmail)) {
      try {
        final d = await FirebaseFirestore.instance.collection('admins').doc(myEmail).get();
        role = '${d.data()?['role'] ?? 'agent'}' == 'admin' ? 'admin' : 'agent';
      } catch (_) { role = 'agent'; }
    } else {
      role = 'admin';
    }
    // السجل المحفوظ يظهر فوراً
    final cached = Prefs.getList('orders_history_v1');
    if (cached != null) {
      history.value = cached.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return AppOrder('${m['_id']}', '${m['_src'] ?? 'order'}', m);
      }).toList();
    }
    _listen('orders', 'order');
    _listen('subscription_requests', 'req');
  }

  static final Map<String, List<AppOrder>> _parts = {'order': [], 'req': []};

  static void _listen(String col, String src) {
    final s = FirebaseFirestore.instance.collection(col).where('status', isEqualTo: 'pending')
        .limit(200).snapshots(includeMetadataChanges: false).listen((snap) {
      final list = <AppOrder>[];
      for (final d in snap.docs) {
        final m = Map<String, dynamic>.from(d.data());
        final o = AppOrder(d.id, src, m);
        if (src == 'order' && !o.fromApp) continue;
        final b64 = m.str('receipt_b64');
        if (b64.isNotEmpty && !receipts.containsKey(d.id)) {
          try { receipts[d.id] = base64Decode(b64); } catch (_) { receipts[d.id] = null; }
        }
        m.remove('receipt_b64');
        list.add(o);
      }
      _parts[src] = list;
      final all = [..._parts['order']!, ..._parts['req']!]
        ..sort((a, b) => (b.created ?? DateTime(2000)).compareTo(a.created ?? DateTime(2000)));
      // طلب جديد وصل الآن (ليس من التحميل الأول ولا من الكاش)
      if (_first[src] == false && !snap.metadata.isFromCache) {
        final fresh = all.where((o) => !_seen.contains(o.id)).toList();
        if (fresh.isNotEmpty) {
          HapticFeedback.heavyImpact();
          final o = fresh.first;
          AdminPush.show('📥 لديك طلب اشتراك — يرجى التفعيل',
              [o.name, o.planTitle, if (o.amount > 0) '${Fmt.n(o.amount)} د.ع', o.method].where((x) => x.isNotEmpty).join(' • '),
              payload: 'orders');
        }
      }
      for (final o in all) { _seen.add(o.id); }
      if (!snap.metadata.isFromCache) unawaited(OrderWatch.mark(all.map((o) => o.id)));
      if (!snap.metadata.isFromCache) _first[src] = false;
      pending.value = all;
      pendingReady.value = true;
    }, onError: (e) {
      CrashLog.add('orders listen $col: $e');
      pendingReady.value = true;
    });
    _subs.add(s);
  }

  static void stop() {
    for (final s in _subs) { s.cancel(); }
    _subs.clear();
  }

  /// سجل الطلبات (مقبولة/مرفوضة) — حقول خفيفة بلا صور، عند الطلب فقط
  static Future<void> loadHistory() async {
    const fields = ['order_id', 'uid', 'email', 'account_name', 'name', 'display_name', 'phone', 'plan', 'plan_title',
      'price', 'price_num', 'method', 'method_number', 'has_receipt', 'receipt_url', 'receipt_hash', 'status', 'created',
      'rejection_reason', 'resolved_by', 'rejected_by', 'duration_days', 'days', 'note', 'activated_by',
      'resolved_at', 'rejected_at', 'amount', 'asia_card_code'];
    final rows = await FsRest.query('orders', select: fields, orderBy: 'created', limit: 250);
    final out = <AppOrder>[];
    for (final m in rows) {
      final o = AppOrder('${m['_id']}', 'order', m);
      if (o.fromApp) out.add(o);
    }
    history.value = out;
    historyAt = DateTime.now();
    await Prefs.setJson('orders_history_v1', out.map((o) => {...o.raw, '_id': o.id, '_src': o.src}).toList());
  }

  /// صورة الإيصال (من الذاكرة، أو تُجلب مرة واحدة)
  static Future<Uint8List?> receipt(AppOrder o) async {
    if (receipts.containsKey(o.id)) return receipts[o.id];
    try {
      final f = await FsRest.getFields('${o.col}/${o.id}', ['receipt_b64']);
      final b = '${f['receipt_b64'] ?? ''}';
      receipts[o.id] = b.isEmpty ? null : base64Decode(b);
    } catch (_) { receipts[o.id] = null; }
    return receipts[o.id];
  }

  static String get by => FirebaseAuth.instance.currentUser?.email ?? 'admin';

  static Future<void> markDone(AppOrder o, {required int days, DateTime? expiry, String? username}) async {
    await FirebaseFirestore.instance.collection(o.col).doc(o.id).update({
      'status': o.col == 'orders' ? 'active' : 'approved',
      'activated_by': by, 'resolved_by': by,
      'resolved_at': FieldValue.serverTimestamp(), 'updated_at': FieldValue.serverTimestamp(),
      'duration_days': days,
      if (expiry != null) 'expiry_date': Timestamp.fromDate(expiry),
      if (username != null) 'line_username': username,
    });
  }

  static Future<void> reject(AppOrder o, String reason) async {
    await FirebaseFirestore.instance.collection(o.col).doc(o.id).update({
      'status': 'rejected', 'rejected_by': by, 'rejected_at': FieldValue.serverTimestamp(),
      'rejection_reason': reason, 'updated_at': FieldValue.serverTimestamp(),
    });
  }
}

// ════════════════════════════════════════════════════════════════════
//  المشتركون من قاعدة الاشتراكات (قراءة مجانية) — محفوظون على الهاتف
// ════════════════════════════════════════════════════════════════════
class Sub {
  final Map<String, dynamic> r;
  Sub(this.r);
  String get uid => r.str('uid');
  String get email => r.str('email').toLowerCase();
  String get name => r.str('display_name');
  String get host => r.str('host');
  String get username => r.str('username');
  String get password => r.str('password');
  String get code => r.str('code');
  String get tier => r.str('tier');
  String get source => r.str('source').isNotEmpty ? r.str('source') : (code.isNotEmpty ? 'code' : 'manual');
  String get agent => r.str('agent');
  DateTime? get expiry => r.d('expiry_date');
  DateTime? get firstAt => r.d('first_activated_at') ?? r.d('activated_at');
  int get renews => r.i('renew_count');
  int get tenure => r.i('tenure_days');
  bool get active => r['active'] == true || (expiry != null && expiry!.isAfter(DateTime.now()));
  int? get daysLeft => Fmt.daysLeft(expiry);
}

class Subs {
  static final list = Live<List<Sub>>([]);
  static DateTime? at;
  static final byUid = <String, Sub>{};
  static final byEmail = <String, Sub>{};

  static Future<void> loadCached() async {
    final c = await DiskCache.read('subs');
    if (c is List && list.value.isEmpty) {
      _set(c.map((e) => Sub(Map<String, dynamic>.from(e as Map))).toList());
      at = await DiskCache.time('subs');
    }
  }

  static void _set(List<Sub> l) {
    byUid.clear(); byEmail.clear();
    for (final s in l) {
      if (s.uid.isNotEmpty) byUid[s.uid] = s;
      if (s.email.isNotEmpty) byEmail[s.email] = s;
    }
    list.value = l;
  }

  static Future<void> refresh() async {
    var all = <Sub>[];
    var after = '';
    for (var i = 0; i < 20; i++) {
      final r = await Supa.call('admin_subs_page', {'p_after': after, 'p_limit': 5000});
      final page = r.l('subscribers');
      all.addAll(page.map((e) => Sub(Map<String, dynamic>.from(e as Map))));
      if (page.length < 5000) break;
      after = all.last.uid;
    }
    _set(all);
    at = DateTime.now();
    await DiskCache.write('subs', all.map((s) => s.r).toList());
  }

  static Sub? of(String uid, [String email = '']) => byUid[uid] ?? (email.isEmpty ? null : byEmail[email.toLowerCase()]);
}
