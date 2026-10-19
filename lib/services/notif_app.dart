part of '../main.dart';

// ════════════════════════════════════════════════════════════════
//  NOTIFICATIONS SERVICE — v1 Clean
// ════════════════════════════════════════════════════════════════
class NotifService {
  /// ★ طلب إذن الإشعارات — مطلوب على Android 13+ (API 33)
  static Future<void> requestNotifPermission() async {
    if (!Plat.isAndroid) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt >= 33) {
        final plugin = FlutterLocalNotificationsPlugin();
        await plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    } catch (e) { debugPrint('[notif] permission: $e'); }
  }

  static bool _inited = false;
  static final _ln = FlutterLocalNotificationsPlugin();
  static const _chId   = 'totv_main';
  static const _chName = 'TOTV+ Notifications';
  static const _chOrders = 'totv_orders';
  static const _chMatch  = 'totv_matches';   // ★ صافرة الحكم عند انطلاق المباريات

  static Future<void> init() async {
    if (_inited) return;
    try {
      if (!kIsWeb) {
        // ★ طلب إذن الإشعارات على Android 13+
        await requestNotifPermission();
        // ★ إصلاح: '@mipmap/launcher_icon' غير موجود في المشروع ⇐ كانت التهيئة تفشل
        //   فيتوقف كل ما بعدها (ومنه الاشتراك في إشعارات المباريات)
        const android = AndroidInitializationSettings('@drawable/ic_notification');
        const ios     = DarwinInitializationSettings();
        await _ln.initialize(const InitializationSettings(android: android, iOS: ios));
        await _ln
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(const AndroidNotificationChannel(
              _chId, _chName,
              importance: Importance.high,
              playSound: true,
            ));
        // ★ قناة الطلبات — بصوت مخصّص (كاش/طلب) للإشعار مثل واتساب
        await _ln
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(const AndroidNotificationChannel(
              _chOrders, 'طلبات الاشتراك',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('cash'),
            ));
        // ★ قناة المباريات — صوت صافرة الحكم (res/raw/whistle.wav)
        await _ln
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(const AndroidNotificationChannel(
              _chMatch, 'انطلاق المباريات',
              description: 'إشعار بصافرة البداية عند انطلاق المباريات',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('whistle'),
            ));
      }
    } catch (e) { debugPrint('[notif_app] local: $e'); }
    // ★ FCM في كتلة مستقلة: فشل الإشعارات المحلية لا يمنع الاشتراك في المواضيع
    try {
      final m = FirebaseMessaging.instance;
      await m.requestPermission(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n == null) return;
        if (msg.data['type'] == 'match') { showMatch(n.title ?? 'TOTV+', n.body ?? ''); return; }
        show(n.title ?? 'TOTV+', n.body ?? '');
      });
      await m.subscribeToTopic('all_users');
      // ★ إشعارات انطلاق المباريات (قابلة للإيقاف من «المزيد»)
      if (await MatchNotifPref.get()) await m.subscribeToTopic('matches');
      // الضغط على إشعار مباراة يفتح قسم «رياضة»
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        if (msg.data['type'] == 'match') ShellNav.go(3);
      });
      try {
        final first = await m.getInitialMessage();
        if (first?.data['type'] == 'match') ShellNav.go(3);
      } catch (_) {}
      // المشرفون يشتركون في topic admins لتلقّي إشعار كل طلب جديد
      try {
        final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim().toLowerCase();
        if (email == 'haedirasso@gmail.com' || email == 'admin@totv.com' || email.endsWith('@totv.com')) {
          await m.subscribeToTopic('admins');
        }
      } catch (_) {}
      final token = await m.getToken();
      final user  = FirebaseAuth.instance.currentUser;
      if (token != null && user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'fcm_token':         token,
          'last_token_update': FieldValue.serverTimestamp(),
          'platform':          Plat.name,
        }, SetOptions(merge: true));
      }
      _inited = true;
    } catch (e) { debugPrint('[notif_app] $e'); }
  }

  static Future<String?> getToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  static void show(String title, String body, {String? payload}) {
    if (kIsWeb) { debugPrint('📲 $title — $body'); return; }
    Sound.hapticNotif();
    try {
      _ln.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title, body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _chId, _chName,
            importance: Importance.high,
            priority:   Priority.high,
            icon: '@drawable/ic_notification',
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) { debugPrint('[notif_app] $e'); }
  }

  // ★ إشعار انطلاق مباراة والتطبيق مفتوح — بصوت الصافرة
  static void showMatch(String title, String body) {
    if (kIsWeb) return;
    Sound.hapticNotif();
    try {
      _ln.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title, body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _chMatch, 'انطلاق المباريات',
            importance: Importance.max,
            priority:   Priority.max,
            icon: '@drawable/ic_notification',
            sound: RawResourceAndroidNotificationSound('whistle'),
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(sound: 'whistle.wav'),
        ),
      );
    } catch (e) { debugPrint('[notif_app] match: $e'); }
  }

  // ★ إشعار طلب اشتراك جديد (للأدمن) — بصوت الكاش
  static void showOrder(String title, String body) {
    if (kIsWeb) { debugPrint('📲 $title — $body'); return; }
    Sound.hapticNotif();
    try {
      _ln.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title, body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _chOrders, 'طلبات الاشتراك',
            importance: Importance.max,
            priority:   Priority.max,
            icon: '@drawable/ic_notification',
            sound: RawResourceAndroidNotificationSound('cash'),
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(sound: 'cash.wav'),
        ),
      );
    } catch (e) { debugPrint('[notif_app] order: $e'); }
  }

  static Future<void> subscribeToTopic(String t) async {
    try { await FirebaseMessaging.instance.subscribeToTopic(t); } catch (e) { debugPrint('[notif_app] $e'); }
  }
}

// ════════════════════════════════════════════════════════════════
//  مراقب طلبات الأدمن — إشعار فوري بصوت عند وصول طلب جديد
//  (يعمل ما دام تطبيق الأدمن مفتوحاً/بالخلفية — بلا حاجة لدوال سحابية)
// ════════════════════════════════════════════════════════════════
class AdminOrderWatcher {
  static StreamSubscription? _sub;
  static bool _first = true;

  static void start() {
    final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim().toLowerCase();
    final isAdmin = email == 'haedirasso@gmail.com' || email == 'admin@totv.com' || email.endsWith('@totv.com');
    if (!isAdmin) return;
    _sub?.cancel();
    _first = true;
    _sub = FirebaseFirestore.instance.collection('orders')
        .orderBy('created', descending: true)
        .limit(8)
        .snapshots()
        .listen((snap) {
      if (_first) { _first = false; return; }
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final m = ch.doc.data() ?? {};
          if ((m['status'] ?? 'pending').toString() != 'pending') continue;
          final name = (m['name'] ?? 'مستخدم').toString();
          final plan = (m['plan_title'] ?? m['plan'] ?? '').toString();
          final price = (m['price'] ?? '').toString();
          NotifService.showOrder('🔔 طلب اشتراك جديد',
              '$name — باقة $plan${price.isNotEmpty ? ' ($price)' : ''}');
        }
      }
    }, onError: (e) => debugPrint('[AdminOrderWatcher] $e'));
  }

  static void stop() { _sub?.cancel(); _sub = null; }
}

// ════════════════════════════════════════════════════════════════
//  GATE PAGES — Maintenance / Lock
// ════════════════════════════════════════════════════════════════
class _LockPage extends StatelessWidget {
  final String msg;
  const _LockPage(this.msg);
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lock_clock_rounded, color: C.gold, size: 80),
        const SizedBox(height: 20),
        Text('التطبيق مغلق مؤقتاً',
            style: T.cairo(s: FS.lg, w: FontWeight.w800),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(msg.isNotEmpty ? msg : 'يرجى المحاولة لاحقاً',
            style: T.body(c: C.grey), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => launchUrl(Uri.parse(RC.telegram),
              mode: LaunchMode.externalApplication),
          child: Text('تواصل معنا', style: T.caption(c: C.gold)),
        ),
      ]),
    )),
  );
}

class _MaintenancePage extends StatelessWidget {
  final String msg;
  const _MaintenancePage(this.msg);
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: C.gold, strokeWidth: 2),
        const SizedBox(height: 30),
        Text('خاضع للصيانة', style: T.cairo(s: FS.lg, w: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          msg.isNotEmpty ? msg : 'نعمل على تحسين التطبيق، سنعود قريباً',
          style: T.body(c: C.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => launchUrl(Uri.parse(RC.telegram),
              mode: LaunchMode.externalApplication),
          child: Text('تابعنا على تيليجرام', style: T.caption(c: C.gold)),
        ),
      ]),
    )),
  );
}


/// تفضيل إشعارات «صافرة البداية» (مفعّل افتراضياً)
class MatchNotifPref {
  static const _k = 'notif_matches_v1';
  static Future<bool> get() async {
    try { return (await SPref.i).getBool(_k) ?? true; } catch (_) { return true; }
  }
  static Future<void> set(bool on) async {
    try { await (await SPref.i).setBool(_k, on); } catch (_) {}
    try {
      if (on) { await FirebaseMessaging.instance.subscribeToTopic('matches'); }
      else    { await FirebaseMessaging.instance.unsubscribeFromTopic('matches'); }
    } catch (e) { debugPrint('[notif] matches topic: $e'); }
  }
}


/// ★ إشعار فوري لتطبيق الإدارة عند إرسال طلب اشتراك
///   عبر Supabase Edge Function «push» (تتحقق من توكن Firebase للمستخدم).
///   لا مفاتيح سرية هنا — مفتاح Firebase في Secrets الدالة فقط.
class AdminOrderPush {
  static Future<void> send({required String orderId, required String name,
      required String plan, required String price, required String method}) async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null || !kSupaReady) return;
      final token = await u.getIdToken();
      await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
      )).post('$kSupaUrl/functions/v1/push',
        data: {
          'action': 'order', 'idToken': token, 'order_id': orderId,
          'name': name, 'plan': plan, 'price': price, 'method': method,
        },
        options: Options(headers: {'apikey': kSupaPublicKey}, contentType: 'application/json'),
      );
    } catch (e) { debugPrint('[admin push] $e'); }
  }
}
