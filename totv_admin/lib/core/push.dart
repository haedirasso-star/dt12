part of '../main.dart';

/// سجل أخطاء صغير يظهر في «فحص النظام» — للتشخيص بدل التخمين
class CrashLog {
  static const _k = 'crash_log_v2';
  static void add(String e) {
    debugPrint('[error] $e');
    try {
      final l = Prefs.p.getStringList(_k) ?? [];
      final t = DateTime.now();
      l.insert(0, '${Fmt.two(t.day)}/${Fmt.two(t.month)} ${Fmt.time(t)}  ${e.length > 400 ? e.substring(0, 400) : e}');
      Prefs.p.setStringList(_k, l.take(20).toList());
    } catch (_) {}
  }
  static List<String> read() { try { return Prefs.p.getStringList(_k) ?? []; } catch (_) { return []; } }
  static Future<void> clear() async { try { await Prefs.p.remove(_k); } catch (_) {} }
}

// ════════════════════════════════════════════════════════════════════
//  الإشعارات: FCM (حين يكون التطبيق مغلقاً) + محلية (حين يكون مفتوحاً)
// ════════════════════════════════════════════════════════════════════
class AdminPush {
  static final _ln = FlutterLocalNotificationsPlugin();
  static String? token;
  static bool subscribed = false;
  static AuthorizationStatus? permission;
  static String error = '';
  static bool _started = false;
  static final ready = Completer<void>();
  static void Function()? onOpenOrders;
  static bool _pendingOpen = false;
  static const _kGuard = 'push_guard_v3';
  static bool safeMode = false;

  static const orders = AndroidNotificationChannel(
    'admin_orders', 'طلبات الاشتراك',
    description: 'إشعار فوري عند وصول طلب اشتراك جديد',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('cash'),
  );
  static const chat = AndroidNotificationChannel(
    'admin_chat', 'رسائل المستخدمين',
    description: 'رسالة جديدة من مستخدم في المحادثة',
    importance: Importance.high,
  );
  static void Function(String uid)? onOpenChat;
  static String? _pendingChat;
  static const general = AndroidNotificationChannel(
    'admin_general', 'تنبيهات الإدارة',
    description: 'تنبيهات عامة للمشرف',
    importance: Importance.high,
  );

  static bool _localReady = false;
  static void Function()? onOpenBot;

  /// الإشعارات المحلية فقط (تعمل أيضاً في خلفية البوت)
  static Future<void> ensureLocal() async {
    if (_localReady) return;
    try {
      await _ln.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload == 'orders') _open();
          if (r.payload == 'bot') { if (onOpenBot != null) { onOpenBot!(); } else { _pendingBot = true; } }
          final p = r.payload ?? '';
          if (p.startsWith('chat:')) _openChat(p.substring(5));
        },
      );
      final a = _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.createNotificationChannel(orders);
      await a?.createNotificationChannel(general);
      await a?.createNotificationChannel(chat);
      await a?.createNotificationChannel(ServerBot.channel);
      _localReady = true;
    } catch (e) { CrashLog.add('local notif: $e'); }
  }
  static bool _pendingBot = false;

  static Future<void> init({bool force = false}) async {
    if (_started && !force) return;
    _started = true;
    await ensureLocal();
    try {
      final l = await _ln.getNotificationAppLaunchDetails();
      final pl = l?.notificationResponse?.payload;
      if (l?.didNotificationLaunchApp == true && pl == 'orders') _pendingOpen = true;
      if (l?.didNotificationLaunchApp == true && pl == 'bot') _pendingBot = true;
      if (l?.didNotificationLaunchApp == true && (pl ?? '').startsWith('chat:')) _pendingChat = pl!.substring(5);
    } catch (e) { CrashLog.add('launch details: $e'); }

    // حارس: إن توقف التطبيق أثناء تهيئة FCM سابقاً ⇐ لا نعيدها تلقائياً
    if (!force && (Prefs.p.getBool(_kGuard) ?? false)) {
      safeMode = true;
      error = 'تهيئة الإشعارات توقفت في المرة السابقة — اضغط «إعادة تفعيل الإشعارات»';
      if (!ready.isCompleted) ready.complete();
      return;
    }
    await Prefs.p.setBool(_kGuard, true);
    try {
      final m = FirebaseMessaging.instance;
      final s = await m.requestPermission(alert: true, badge: true, sound: true);
      permission = s.authorizationStatus;
      token = await m.getToken().timeout(const Duration(seconds: 25));
      if (token != null) {
        await m.subscribeToTopic('admin_orders').timeout(const Duration(seconds: 20));
        await m.subscribeToTopic('admins').timeout(const Duration(seconds: 20));
        subscribed = true;
        error = '';
        safeMode = false;
      }
      // التطبيق مفتوح: إشعار الطلب يظهر من المستمع المباشر (Store) — هنا فقط غير الطلبات
      FirebaseMessaging.onMessage.listen((msg) {
        if (msg.data['type'] == 'order') return;
        final n = msg.notification;
        if (msg.data['type'] == 'chat') {
          final uid = '${msg.data['uid'] ?? ''}';
          Engage.onPush(uid);
          if (uid != Engage.openRoom && n != null) {
            show(n.title ?? 'رسالة جديدة', n.body ?? '', channel: chat, payload: 'chat:$uid');
          }
          return;
        }
        if (n != null) show(n.title ?? 'TOTV+', n.body ?? '', channel: general);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        if (msg.data['type'] == 'order') _open();
        if (msg.data['type'] == 'chat') { Engage.onPush('${msg.data['uid'] ?? ''}'); _openChat('${msg.data['uid'] ?? ''}'); }
      });
      final first = await m.getInitialMessage();
      if (first?.data['type'] == 'order') _pendingOpen = true;
      if (first?.data['type'] == 'chat') _pendingChat = '${first?.data['uid'] ?? ''}';
    } catch (e) {
      error = Fmt.err(e);
      CrashLog.add('push: $e');
    }
    await Prefs.p.setBool(_kGuard, false);
    if (!ready.isCompleted) ready.complete();
  }

  static Future<void> retry() async {
    await Prefs.p.setBool(_kGuard, false);
    safeMode = false;
    await init(force: true);
  }

  static Future<void> show(String title, String body, {AndroidNotificationChannel channel = orders, String? payload}) async {
    try {
      await _ln.show(DateTime.now().millisecondsSinceEpoch ~/ 1000 % 1000000, title, body,
        NotificationDetails(android: AndroidNotificationDetails(
          channel.id, channel.name,
          channelDescription: channel.description,
          importance: Importance.max, priority: Priority.max,
          icon: '@drawable/ic_notification',
          color: K.gold,
          sound: channel.sound,
          styleInformation: BigTextStyleInformation(body),
        )), payload: payload);
    } catch (e) { CrashLog.add('show: $e'); }
  }

  static void _open() { if (onOpenOrders != null) { onOpenOrders!(); } else { _pendingOpen = true; } }
  static void _openChat(String uid) { if (onOpenChat != null) { onOpenChat!(uid); } else { _pendingChat = uid; } }
  static void flush() {
    if (_pendingOpen) { _pendingOpen = false; onOpenOrders?.call(); }
    if (_pendingBot) { _pendingBot = false; onOpenBot?.call(); }
    final c = _pendingChat;
    if (c != null) { _pendingChat = null; onOpenChat?.call(c); }
  }
}

// ════════════════════════════════════════════════════════════════════
//  دالة الإرسال (Supabase Edge Function «push»)
// ════════════════════════════════════════════════════════════════════
class PushApi {
  static const fn = '${Supa.url}/functions/v1/push';
  static const icon = '$fn/icon.png';

  static Future<NetResult> send(Map<String, dynamic> body) async {
    final t = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (t == null) throw Exception('سجّل الدخول أولاً');
    return Net.req('POST', fn, headers: {'apikey': Supa.key}, body: {...body, 'idToken': t});
  }

  static Future<NetResult> health() => Net.req('GET', '$fn/health', headers: {'apikey': Supa.key},
      timeout: const Duration(seconds: 20));

  static String explain(NetResult r) {
    switch (r.code) {
      case 200: return 'تم الإرسال فوراً';
      case 403: return 'بريدك غير موجود في ADMIN_EMAILS في أسرار الدالة';
      case 401: return 'انتهت جلسة الدخول — أعد تسجيل الدخول';
      case 404: return 'دالة الإشعارات غير منشورة — افتح «فحص النظام»';
      case 500: return r.raw.contains('FCM_SERVICE_ACCOUNT') ? 'سرّ FCM_SERVICE_ACCOUNT غير مضبوط' : 'خطأ في الدالة';
      default: return 'خطأ ${r.code}';
    }
  }
}
