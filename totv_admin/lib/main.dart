// ════════════════════════════════════════════════════════════════════
//  TOTV+ Admin — تطبيق الإدارة v2
//
//  • واجهة تطبيق أصلية: شريط علوي + شريط تنقّل سفلي + قائمة «المزيد»
//    + شاشة بدء — وصفحات الإدارة (v6.2) كلها بميزاتها داخلها.
//  • بلا تكبير/تصغير، وحجم الخط ثابت مهما كان حجم خط الهاتف.
//  • أسرع فتح: مكتبات Firebase وChart.js والخطوط مخزّنة داخل التطبيق
//    (لا تُحمَّل من الإنترنت)، وبيانات الجلسة والكاش محفوظة على الجهاز.
//  • إشعار فوري عند كل طلب اشتراك (صوت الكاش) + عدّاد الطلبات.
//    يعمل حتى بدون google-services.json الخاص بتطبيق الإدارة.
//  • زر «إشعار فوري» لكل المستخدمين + صفحة «فحص الإشعارات».
// ════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const kGold = Color(0xFFF5A623);
const kBg   = Color(0xFF09090E);
const kBar  = Color(0xFF0F0F15);
const kCard = Color(0xFF16161D);
const kRed  = Color(0xFFE50914);

// Supabase (مفاتيح عامة — نفس الموجودة في صفحة الأدمن)
const kSupaUrl = 'https://hlmaksidfqdarwunedqj.supabase.co';
const kSupaKey = 'sb_publishable_-lEvqrjoQgkXJdN4lZExxw_1cycMoEj';
const kPushFn  = '$kSupaUrl/functions/v1/push';

// إعداد Firebase مدمج (مشروع totvq-8e439) — يُستخدم إن لم يوجد google-services.json
// هذه مفاتيح عامة بطبيعتها (موجودة في أي تطبيق Firebase) وليست أسراراً.
const _kFbAndroid = FirebaseOptions(
  apiKey: 'AIzaSyBR9NjEZHm9RhngSfYNMmphaH_gDLTApTY',
  appId: '1:214530463737:android:c6447caa773d03b1164f28',
  messagingSenderId: '214530463737',
  projectId: 'totvq-8e439',
  storageBucket: 'totvq-8e439.firebasestorage.app',
);

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) { CrashLog.add('flutter: ${d.exceptionAsString()}'); };
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: kBar,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    // الخادم المحلي يبدأ فوراً لتسريع الفتح — الإشعارات تبدأ بعد ظهور الصفحة
    unawaited(LocalSite.start());
    runApp(const AdminApp());
  }, (e, st) => CrashLog.add('$e'));
}

/// سجل أخطاء صغير يظهر في «فحص الإشعارات» (للتشخيص)
class CrashLog {
  static const _k = 'crash_log_v1';
  static Future<void> add(String e) async {
    debugPrint('[error] $e');
    try {
      final p = await SharedPreferences.getInstance();
      final l = p.getStringList(_k) ?? [];
      l.insert(0, '${DateTime.now().toIso8601String().substring(5, 19)}  ${e.length > 300 ? e.substring(0, 300) : e}');
      await p.setStringList(_k, l.take(15).toList());
    } catch (_) {}
  }
  static Future<List<String>> read() async {
    try { return (await SharedPreferences.getInstance()).getStringList(_k) ?? []; } catch (_) { return []; }
  }
  static Future<void> clear() async {
    try { await (await SharedPreferences.getInstance()).remove(_k); } catch (_) {}
  }
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TOTV+ إدارة',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kBg,
      colorScheme: const ColorScheme.dark(primary: kGold, secondary: kGold, surface: kCard),
      appBarTheme: const AppBarTheme(backgroundColor: kBar, surfaceTintColor: Colors.transparent, elevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: kBar,
        indicatorColor: kGold.withOpacity(0.18),
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w700,
          color: s.contains(WidgetState.selected) ? kGold : Colors.white60)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? kGold : Colors.white60, size: 25)),
      ),
    ),
    // حجم خط ثابت: لا يتأثر بإعداد خط الهاتف (يمنع تخريب التصميم)
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
    home: const AdminShell(),
  );
}

// ════════════════════════════════════════════════════════════════════
//  إشعارات الإدارة — طلبات الاشتراك الجديدة
// ════════════════════════════════════════════════════════════════════
class AdminPush {
  static bool enabled = false;          // يستقبل إشعارات FCM
  static String mode = '—';             // مصدر إعداد Firebase
  static String error = '';
  static String? token;
  static bool subscribed = false;
  static AuthorizationStatus? permission;
  static DateTime _lastFcmOrder = DateTime.fromMillisecondsSinceEpoch(0);
  static final Completer<void> ready = Completer<void>();

  static final _ln = FlutterLocalNotificationsPlugin();
  static void Function(bool opened)? onOrder;
  static bool _pendingOpen = false;

  static const orders = AndroidNotificationChannel(
    'admin_orders', 'طلبات الاشتراك',
    description: 'إشعار فوري عند وصول طلب اشتراك جديد',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('cash'),
  );

  static bool _started = false;
  static bool safeMode = false;     // تهيئة FCM تسببت بتوقف سابق ⇐ معطّلة مؤقتاً
  static const _kGuard = 'push_init_guard_v2';

  static Future<void> init({bool force = false}) async {
    if (_started) return;
    _started = true;
    SharedPreferences? prefs;
    try { prefs = await SharedPreferences.getInstance(); } catch (_) {}

    try {
      // 1) الإشعارات المحلية والقناة (آمنة دائماً)
      await _ln.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
        onDidReceiveNotificationResponse: (_) => _open(),
      );
      final android = _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(orders);
      final launch = await _ln.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) _pendingOpen = true;
    } catch (e) { CrashLog.add('local notif: $e'); }

    // حارس: إن بقيت العلامة من تشغيل سابق ⇐ التطبيق توقف أثناء FCM
    if (!force && (prefs?.getBool(_kGuard) ?? false)) {
      safeMode = true;
      error = 'تهيئة الإشعارات توقفت في المرة السابقة — عُطّلت مؤقتاً. اضغط «إعادة تفعيل الإشعارات».';
      _done();
      return;
    }
    await prefs?.setBool(_kGuard, true);

    try {
      // 2) Firebase: ملف google-services.json إن وُجد، وإلا الإعداد المدمج
      try {
        await Firebase.initializeApp();
        mode = 'google-services.json';
      } catch (_) {
        await Firebase.initializeApp(options: _kFbAndroid);
        mode = 'إعداد مدمج';
      }
      // 3) FCM
      final m = FirebaseMessaging.instance;
      final s = await m.requestPermission(alert: true, badge: true, sound: true);
      permission = s.authorizationStatus;
      token = await _getToken();
      if (token != null) {
        await m.subscribeToTopic('admin_orders').timeout(const Duration(seconds: 20));
        await m.subscribeToTopic('admins').timeout(const Duration(seconds: 20));
        subscribed = true;
        enabled = true;
        error = '';
      }
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (msg.data['type'] == 'order') _lastFcmOrder = DateTime.now();
        if (n != null) show(n.title ?? 'TOTV+', n.body ?? '');
        if (msg.data['type'] == 'order') onOrder?.call(false);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((msg) { if (msg.data['type'] == 'order') _open(); });
      final first = await m.getInitialMessage();
      if (first?.data['type'] == 'order') _pendingOpen = true;
    } catch (e) {
      error = 'FCM: $e';
      CrashLog.add('push: $e');
    }
    await prefs?.setBool(_kGuard, false);   // وصلنا هنا ⇐ لا توقف
    _done();
  }

  /// إعادة المحاولة يدوياً من صفحة الفحص
  static Future<void> retry() async {
    try { (await SharedPreferences.getInstance()).setBool(_kGuard, false); } catch (_) {}
    safeMode = false;
    _started = false;
    await init(force: true);
  }

  static void _done() { if (!ready.isCompleted) ready.complete(); }

  static Future<String?> _getToken() async {
    try {
      return await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 20));
    } catch (e) { error = 'FCM token: $e'; return null; }
  }

  static Future<void> show(String title, String body) async {
    try {
      await _ln.show(DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000, title, body,
        NotificationDetails(android: AndroidNotificationDetails(
          orders.id, orders.name,
          importance: Importance.max, priority: Priority.max,
          icon: '@drawable/ic_notification',
          sound: const RawResourceAndroidNotificationSound('cash'),
          color: kGold,
          styleInformation: BigTextStyleInformation(body),
        )));
    } catch (e) { debugPrint('[show] $e'); }
  }

  /// احتياط: إن زاد عدد الطلبات ولم يصل إشعار FCM خلال دقيقة ⇐ إشعار محلي
  static void localOrderAlert(int added, int total) {
    if (DateTime.now().difference(_lastFcmOrder).inSeconds < 60) return;
    show('📥 لديك طلب اشتراك — يرجى التفعيل',
        added == 1 ? 'وصل طلب جديد • المنتظرة الآن: $total' : 'وصلت $added طلبات جديدة • المنتظرة الآن: $total');
  }

  static void _open() { if (onOrder != null) { onOrder!(true); } else { _pendingOpen = true; } }
  static void flushPending() { if (_pendingOpen) { _pendingOpen = false; onOrder?.call(true); } }
}

// ════════════════════════════════════════════════════════════════════
//  خادم محلي — يقدّم صفحة الإدارة + المكتبات والخطوط من داخل التطبيق
// ════════════════════════════════════════════════════════════════════
class LocalSite {
  static HttpServer? _server;
  static Uint8List? _html;
  static final Map<String, Uint8List> _files = {};
  static Completer<String>? _starting;

  static const _types = {
    'js': 'application/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'woff2': 'font/woff2',
    'png': 'image/png',
  };

  // يُحقن في <head>: وضع التطبيق — لا تكبير، لا قائمة جانبية، لمس أصلي
  static const _appCss = '''
<style id="inapp-css">
html.inapp .sb,html.inapp .sb-overlay,html.inapp .hamburger,html.inapp .hdr{display:none!important}
html.inapp .main{margin-right:0!important}
html.inapp .body{padding:12px 12px 28px!important}
html.inapp.qs .hdr{display:flex!important;position:sticky;top:0;padding:8px 10px!important;gap:0}
html.inapp.qs .hdr>.row,html.inapp.qs .hdr-actions{display:none!important}
html.inapp.qs .quick-search{display:block!important;max-width:none!important;flex:1}
html.inapp.qs .quick-search input{font-size:15px;padding:11px 14px 11px 34px}
html.inapp body{-webkit-tap-highlight-color:transparent;overscroll-behavior-y:none;-webkit-user-select:none;user-select:none;touch-action:manipulation;-webkit-touch-callout:none}
html.inapp input,html.inapp textarea,html.inapp select,html.inapp [contenteditable],html.inapp .mono,html.inapp code,html.inapp pre{-webkit-user-select:text;user-select:text}
html.inapp input,html.inapp textarea,html.inapp select{font-size:16px!important}
html.inapp ::-webkit-scrollbar{width:0;height:0}
html.inapp .btn,html.inapp .filter-btn,html.inapp .rq-chip.click,html.inapp .card[onclick]{transition:transform .08s}
html.inapp .btn:active,html.inapp .filter-btn:active,html.inapp .rq-chip.click:active{transform:scale(.96)}
html.inapp .page.on{animation:inappIn .18s ease-out}
@keyframes inappIn{from{opacity:.4;transform:translateY(6px)}to{opacity:1;transform:none}}
</style>''';

  static Future<String> start() {
    if (_starting != null) return _starting!.future;
    final c = _starting = Completer<String>();
    () async {
      try {
        var html = await rootBundle.loadString('assets/admin/index.html');
        html = html
          .replaceFirst('<html lang="ar" dir="rtl">', '<html lang="ar" dir="rtl" class="inapp">')
          .replaceFirst('content="width=device-width,initial-scale=1"',
              'content="width=device-width,initial-scale=1,maximum-scale=1,minimum-scale=1,user-scalable=no,viewport-fit=cover"')
          .replaceAll(RegExp(r'<link href="https://fonts\.googleapis\.com/css2[^"]*" rel="stylesheet">'),
              '<link href="/fonts/fonts.css" rel="stylesheet">')
          .replaceAll('https://www.gstatic.com/firebasejs/10.12.0/', '/lib/')
          .replaceAll('https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js', '/lib/chart.umd.min.js')
          .replaceFirst('</head>', '$_appCss\n<script>window.__TOTV_APP__=1;</script>\n</head>');
        _html = Uint8List.fromList(utf8.encode(html));

        for (final p in const [
          'lib/firebase-app-compat.js', 'lib/firebase-firestore-compat.js', 'lib/firebase-auth-compat.js',
          'lib/chart.umd.min.js', 'fonts/fonts.css',
          'fonts/plex-ar-300.woff2', 'fonts/plex-ar-400.woff2', 'fonts/plex-ar-500.woff2',
          'fonts/plex-ar-600.woff2', 'fonts/plex-ar-700.woff2',
          'fonts/plex-la-300.woff2', 'fonts/plex-la-400.woff2', 'fonts/plex-la-500.woff2',
          'fonts/plex-la-600.woff2', 'fonts/plex-la-700.woff2',
          'fonts/jbm-400.woff2', 'fonts/jbm-600.woff2', 'fonts/jbm-700.woff2',
        ]) {
          try {
            final d = await rootBundle.load('assets/$p');
            _files['/$p'] = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
          } catch (e) { debugPrint('[site] missing $p'); }
        }

        // منفذ ثابت حتى يبقى تسجيل الدخول والإعدادات محفوظة بين التشغيلات
        for (final port in [8787, 8788, 8789, 8790]) {
          try { _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true); break; }
          catch (_) {}
        }
        _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        _server!.listen(_handle);
        c.complete('http://localhost:${_server!.port}/');
      } catch (e) {
        c.completeError(e);
      }
    }();
    return c.future;
  }

  static void _handle(HttpRequest req) {
    final res = req.response;
    final path = req.uri.path;
    if (path == '/' || path == '/index.html') {
      res.headers.contentType = ContentType.html;
      res.headers.set('Cache-Control', 'no-cache');
      res.add(_html!);
    } else if (_files.containsKey(path)) {
      final ext = path.split('.').last;
      res.headers.set('Content-Type', _types[ext] ?? 'application/octet-stream');
      res.headers.set('Cache-Control', 'public, max-age=31536000, immutable');
      res.headers.set('Access-Control-Allow-Origin', '*');
      res.add(_files[path]!);
    } else if (path == '/robots.txt') {
      res.headers.contentType = ContentType.text;
      res.write('User-agent: *\nDisallow: /\n');
    } else {
      res.statusCode = HttpStatus.notFound;
    }
    res.close();
  }
}

// ════════════════════════════════════════════════════════════════════
//  الأقسام — التنقّل الأصلي
// ════════════════════════════════════════════════════════════════════
class Sec {
  final String id, title;
  final IconData icon;
  const Sec(this.id, this.title, this.icon);
}

const _tabs = [
  Sec('dash', 'الرئيسية', Icons.space_dashboard_rounded),
  Sec('requests', 'الطلبات', Icons.receipt_long_rounded),
  Sec('lines', 'التفعيل', Icons.bolt_rounded),
  Sec('members', 'المستخدمون', Icons.people_alt_rounded),
];

const _groups = <(String, List<Sec>)>[
  ('العمل اليومي', [
    Sec('lines', 'التفعيل والمخزون', Icons.bolt_rounded),
    Sec('requests', 'طلبات الاشتراك', Icons.receipt_long_rounded),
    Sec('codes', 'أكواد التفعيل', Icons.key_rounded),
    Sec('activate', 'تفعيل يدوي', Icons.edit_note_rounded),
  ]),
  ('المشتركون', [
    Sec('members', 'كل المستخدمين', Icons.people_alt_rounded),
    Sec('free', 'التجربة المجانية', Icons.timer_outlined),
    Sec('banned', 'المحظورون', Icons.block_rounded),
  ]),
  ('الأرقام', [
    Sec('control', 'مركز السيطرة', Icons.tune_rounded),
    Sec('dash', 'لوحة الإحصائيات', Icons.space_dashboard_rounded),
  ]),
  ('الوكلاء', [
    Sec('agents', 'الوكلاء والمسوّقون', Icons.badge_rounded),
    Sec('credit', 'رصيد التفعيل', Icons.account_balance_wallet_rounded),
  ]),
  ('التطبيق والإعدادات', [
    Sec('servers', 'السيرفرات', Icons.dns_rounded),
    Sec('remote', 'تحكم عن بعد', Icons.settings_remote_rounded),
    Sec('version', 'الإصدارات', Icons.rocket_launch_rounded),
    Sec('notif', 'إشعارات الصفحة', Icons.notifications_rounded),
    Sec('rules', 'Firestore Rules', Icons.shield_rounded),
    Sec('config', 'الإعدادات', Icons.settings_rounded),
  ]),
];

// ════════════════════════════════════════════════════════════════════
//  الشاشة الرئيسية
// ════════════════════════════════════════════════════════════════════
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> with WidgetsBindingObserver {
  WebViewController? _c;
  String _base = '';
  bool _error = false, _splash = true, _app = false, _login = false, _agent = false, _search = false;
  String _cur = 'dash', _title = 'لوحة التحكم';
  int _pending = 0, _progress = 0;
  int? _knownPending;
  final Map<int, Completer<String?>> _tokenWaiters = {};
  int _tokenSeq = 0;
  DateTime _lastBack = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _splashGuard;

  // يُحقن بعد كل تحميل: جسر التطبيق (حالة الصفحة، النسخ، التنزيل، التوكن)
  static const _bridgeJs = r'''
(function(){
  if (window.__totvNative) return; window.__totvNative = true;
  function post(o){ try{ TotvNative.postMessage(JSON.stringify(o)); }catch(e){} }
  // النسخ
  var cb = { writeText: function(t){ post({t:'copy', v:String(t)}); return Promise.resolve(); },
             readText: function(){ return Promise.resolve(''); } };
  try { Object.defineProperty(navigator, 'clipboard', { value: cb, configurable: true }); }
  catch(e){ try { navigator.clipboard.writeText = cb.writeText; } catch(_){} }
  // تنزيل الملفات (CSV…) عبر التطبيق
  var _rev = URL.revokeObjectURL.bind(URL);
  URL.revokeObjectURL = function(u){ setTimeout(function(){ _rev(u); }, 60000); };
  function grab(a){
    var href = a.href || '', name = a.download || 'totv_file';
    if (!/^(blob|data):/.test(href)) return false;
    fetch(href).then(function(r){ return r.blob(); }).then(function(b){
      var fr = new FileReader();
      fr.onload = function(){ post({t:'download', name:name, data:fr.result}); };
      fr.readAsDataURL(b);
    }).catch(function(e){ post({t:'toast', v:'تعذّر تجهيز الملف'}); });
    return true;
  }
  var _click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function(){
    if (this.hasAttribute('download') && grab(this)) return;
    return _click.apply(this, arguments);
  };
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[download]') : null;
    if (a && grab(a)) e.preventDefault();
  }, true);
  // حالة الصفحة ⇐ الواجهة الأصلية (العنوان، القسم، الدخول، عدد الطلبات)
  var last = '', t0 = Date.now();
  function st(){
    var A = document.getElementById('APP'), L = document.getElementById('LS');
    var app = !!A && A.style.display === 'block';
    // مهلة قصيرة حتى يتحقق Firebase من الجلسة المحفوظة (لا تظهر شاشة الدخول لحظياً)
    var login = !app && !!L && getComputedStyle(L).display !== 'none' && Date.now() - t0 > 1800;
    var role = '', cur = '';
    try { role = USER_ROLE || ''; } catch(e){}
    try { cur = CUR || ''; } catch(e){}
    var t = ((document.getElementById('hdr-title')||{}).textContent || '').trim();
    var n = ((document.getElementById('nb-req')||{}).textContent || '0').trim();
    var k = [app, login, role, cur, t, n].join('|');
    if (k !== last) { last = k; post({t:'state', app:app, login:login, role:role, cur:cur, title:t, req:n}); }
  }
  try {
    var _nav = window.nav;
    if (typeof _nav === 'function') {
      window.nav = function(){ var r = _nav.apply(this, arguments); try{ window.scrollTo(0,0); }catch(e){} setTimeout(st, 0); return r; };
    }
  } catch(e){}
  setInterval(st, 500); st();
  // طلبات جديدة: حدّث العدّاد كل 30 ثانية حتى لو لم تكن في صفحة الطلبات
  setInterval(function(){ try{ if (typeof refreshReqBadge === 'function') refreshReqBadge(); }catch(e){} }, 30000);
})();
''';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AdminPush.onOrder = (opened) { if (opened) { _go('requests'); } else { _reloadOrders(); } };
    _splashGuard = Timer(const Duration(seconds: 8), () { if (mounted) setState(() => _splash = false); });
    _init();
    // الإشعارات بعد أن تظهر الواجهة (لا تؤخّر الفتح ولا توقفه)
    Future.delayed(const Duration(seconds: 4), () => AdminPush.init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _splashGuard?.cancel();
    AdminPush.onOrder = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // عند العودة للتطبيق: حدّث عدّاد الطلبات فوراً
    if (s == AppLifecycleState.resumed) _js("try{ if(typeof refreshReqBadge==='function') refreshReqBadge(); }catch(e){}");
  }

  Future<void> _js(String code) async { try { await _c?.runJavaScript(code); } catch (_) {} }

  // ── التنقّل ───────────────────────────────────────────────────────
  void _go(String p) {
    HapticFeedback.selectionClick();
    if (_search) _toggleSearch(false);
    setState(() => _cur = p);
    if (p == 'requests') {
      _js("try{ nav('requests'); var b=document.querySelector('[data-rf=pending]'); "
          "if(b && typeof setReqFilter==='function') setReqFilter(b,'pending'); }catch(e){}");
    } else {
      _js("try{ nav(${jsonEncode(p)}); }catch(e){}");
    }
  }

  Future<void> _reloadOrders() async {
    await _js("try{ if(typeof refreshReqBadge==='function') refreshReqBadge(); "
        "if(typeof CUR!=='undefined' && CUR==='requests') loadRequests(); }catch(e){}");
  }

  void _toggleSearch(bool on) {
    setState(() => _search = on);
    _js(on
        ? "document.documentElement.classList.add('qs'); window.scrollTo(0,0); setTimeout(function(){var i=document.getElementById('qs-input'); if(i){i.focus();}},80);"
        : "document.documentElement.classList.remove('qs'); var i=document.getElementById('qs-input'); if(i){i.value='';i.blur();} var d=document.getElementById('qs-drop'); if(d)d.classList.remove('show');");
  }

  /// توكن Firebase للمشرف المسجّل في الصفحة (لإثبات هويته عند الإرسال)
  Future<String?> idToken() async {
    final c = _c;
    if (c == null) return null;
    final id = ++_tokenSeq;
    final done = Completer<String?>();
    _tokenWaiters[id] = done;
    await _js('''
      (function(){
        function send(v){ TotvNative.postMessage(JSON.stringify({t:'idtoken', id:$id, v:v||''})); }
        try {
          var u = firebase.auth().currentUser;
          if (!u) { send(''); return; }
          u.getIdToken().then(send).catch(function(){ send(''); });
        } catch(e) { send(''); }
      })();
    ''');
    final t = await done.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    _tokenWaiters.remove(id);
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<void> _init() async {
    try {
      _base = await LocalSite.start();
    } catch (e) {
      CrashLog.add('local site: $e');
      if (mounted) setState(() { _error = true; _splash = false; });
      return;
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kBg)
      ..enableZoom(false)
      ..addJavaScriptChannel('TotvNative', onMessageReceived: (m) => _onBridge(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) { if (mounted) setState(() => _progress = p); },
        onPageStarted: (_) { if (mounted) setState(() => _error = false); },
        onPageFinished: (_) async {
          await _js(_bridgeJs);
          Future.delayed(const Duration(milliseconds: 1500), () { if (mounted && _splash) setState(() => _splash = false); });
          if (_search) _toggleSearch(true);
          Future.delayed(const Duration(seconds: 3), AdminPush.flushPending);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true) CrashLog.add('web: ${e.errorCode} ${e.description} ${e.url ?? ''}');
          if (e.isForMainFrame == true && mounted) setState(() { _error = true; _splash = false; });
        },
        onNavigationRequest: (req) {
          final u = req.url;
          if (u.startsWith(_base) || u.startsWith('about:') || u.startsWith('blob:') || u.startsWith('data:')) {
            return NavigationDecision.navigate;
          }
          // روابط خارجية (واتساب، تلجرام، هاتف، صور…) تُفتح خارج التطبيق
          launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
      ))
      ..setOnJavaScriptAlertDialog((r) => _alert(r.message))
      ..setOnJavaScriptConfirmDialog((r) => _confirm(r.message))
      ..setOnJavaScriptTextInputDialog((r) => _prompt(r.message, r.defaultText ?? ''));

    if (c.platform is AndroidWebViewController) {
      final a = c.platform as AndroidWebViewController;
      await a.setMediaPlaybackRequiresUserGesture(false);
      await a.setOnShowFileSelector(_pickFiles);
      try { await a.setTextZoom(100); } catch (_) {}   // تجاهل حجم خط النظام
    }
    await c.loadRequest(Uri.parse(_base));
    if (mounted) setState(() => _c = c);
  }

  // ── الجسر بين الصفحة والتطبيق ─────────────────────────────────────
  Future<void> _onBridge(String raw) async {
    try {
      final m = jsonDecode(raw) as Map;
      switch (m['t']) {
        case 'state':
          final app = m['app'] == true, login = m['login'] == true;
          final n = int.tryParse('${m['req']}'.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          // احتياط الإشعار: زاد عدد الطلبات المنتظرة
          if (app && _knownPending != null && n > _knownPending!) {
            AdminPush.localOrderAlert(n - _knownPending!, n);
            if (_cur == 'requests') _reloadOrders();
          }
          if (app) _knownPending = n;
          final wasApp = _app;
          setState(() {
            _app = app; _login = login;
            _agent = '${m['role']}' == 'agent';
            if ('${m['cur']}'.isNotEmpty) _cur = '${m['cur']}';
            final t = '${m['title']}';
            if (t.isNotEmpty) _title = t;
            _pending = n;
            if (app || login) _splash = false;
          });
          if (app && !wasApp) AdminPush.flushPending();
          break;
        case 'copy':
          await Clipboard.setData(ClipboardData(text: '${m['v'] ?? ''}'));
          HapticFeedback.lightImpact();
          _toast('📋 تم النسخ');
          break;
        case 'toast':
          _toast('${m['v'] ?? ''}');
          break;
        case 'download':
          await _saveAndShare('${m['name']}', '${m['data']}');
          break;
        case 'idtoken':
          _tokenWaiters[(m['id'] as num?)?.toInt() ?? -1]?.complete('${m['v'] ?? ''}');
          break;
      }
    } catch (e) { debugPrint('[bridge] $e'); }
  }

  Future<void> _saveAndShare(String name, String dataUrl) async {
    final i = dataUrl.indexOf(',');
    if (i < 0) return;
    final bytes = base64Decode(dataUrl.substring(i + 1));
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^\w\-.]+'), '_');
    final f = File('${dir.path}/$safe');
    await f.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(f.path)], text: safe);
  }

  Future<List<String>> _pickFiles(FileSelectorParams p) async {
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800);
      if (img == null) return [];
      return [Uri.file(img.path).toString()];
    } catch (_) { return []; }
  }

  // ── نوافذ JavaScript بشكل أصلي ────────────────────────────────────
  Future<void> _alert(String msg) => showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: kCard,
      content: Text(msg, style: const TextStyle(fontSize: 15, height: 1.6)),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
    ),
  );

  Future<bool> _confirm(String msg) async => await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: kCard,
      content: Text(msg, style: const TextStyle(fontSize: 15, height: 1.6)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
      ],
    ),
  ) ?? false;

  Future<String> _prompt(String msg, String def) async {
    final ctrl = TextEditingController(text: def);
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kCard,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg, style: const TextStyle(fontSize: 15, height: 1.6)),
          const SizedBox(height: 10),
          TextField(controller: ctrl, autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('موافق')),
        ],
      ),
    );
    return r ?? '';
  }

  void _toast(String msg) {
    if (!mounted || msg.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kCard,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        duration: const Duration(seconds: 2),
      ));
  }

  // ── التحديث ──────────────────────────────────────────────────────
  Future<void> _refresh({bool hard = false}) async {
    final c = _c;
    if (c == null) return;
    HapticFeedback.mediumImpact();
    if (!hard) {
      // تحديث بيانات القسم الحالي فقط — سريع وبلا إعادة تحميل
      await _js('''
        try { if (typeof cacheClear === 'function') cacheClear(); } catch(e) {}
        try { Object.keys(localStorage).filter(function(k){ return k.indexOf('totv_cache_') === 0; })
                .forEach(function(k){ localStorage.removeItem(k); }); } catch(e) {}
        try { nav(CUR); } catch(e) {}
      ''');
      _toast('⟳ تم تحديث البيانات');
      return;
    }
    await _js('''
      try { Object.keys(localStorage).filter(function(k){ return k.indexOf('totv_cache_') === 0; })
              .forEach(function(k){ localStorage.removeItem(k); }); } catch(e) {}
    ''');
    await c.clearCache();
    await c.reload();
    _toast('⟳ تحديث كامل للصفحات والبيانات');
  }

  Future<void> _onBack() async {
    if (_search) { _toggleSearch(false); return; }
    if (_app && !_agent && _cur != 'dash') { _go('dash'); return; }
    final now = DateTime.now();
    if (now.difference(_lastBack).inSeconds < 2) { SystemNavigator.pop(); return; }
    _lastBack = now;
    _toast('اضغط رجوع مرة أخرى للخروج');
  }

  // ── قائمة «المزيد» ────────────────────────────────────────────────
  void _more() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: kBar,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.78, maxChildSize: 0.94, minChildSize: 0.4,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: [
          Row(children: [
            Expanded(child: _quick(Icons.campaign_rounded, 'إشعار فوري', () { Navigator.pop(ctx); _openNotify(); })),
            const SizedBox(width: 10),
            Expanded(child: _quick(Icons.health_and_safety_rounded, 'فحص الإشعارات', () { Navigator.pop(ctx); _openCheck(); })),
          ]),
          for (final (g, items) in _groups) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Text(g, style: const TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w800))),
            GridView.count(
              crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.08,
              children: [
                for (final s in items)
                  _tile(s, selected: _cur == s.id, badge: s.id == 'requests' ? _pending : 0,
                      onTap: () { Navigator.pop(ctx); _go(s.id); }),
              ],
            ),
          ],
          const SizedBox(height: 18),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            tileColor: kCard,
            leading: const Icon(Icons.restart_alt_rounded, color: kGold),
            title: const Text('تحديث كامل', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('يعيد تحميل الصفحات والبيانات', style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () { Navigator.pop(ctx); _refresh(hard: true); },
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            tileColor: kCard,
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.redAccent)),
            onTap: () async {
              Navigator.pop(ctx);
              if (await _confirm('تسجيل الخروج من لوحة الإدارة؟')) _js('try{ doLogout(); }catch(e){}');
            },
          ),
        ]),
      ),
    );
  }

  Widget _quick(IconData i, String t, VoidCallback onTap) => Material(
    color: kGold.withOpacity(0.12),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(children: [
          Icon(i, color: kGold, size: 28),
          const SizedBox(height: 6),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      ),
    ),
  );

  Widget _tile(Sec s, {required bool selected, required int badge, required VoidCallback onTap}) => Material(
    color: selected ? kGold.withOpacity(0.14) : kCard,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Badge(
          isLabelVisible: badge > 0, label: Text('$badge'), backgroundColor: kRed,
          child: Icon(s.icon, size: 27, color: selected ? kGold : Colors.white),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(s.title, textAlign: TextAlign.center, maxLines: 2,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? kGold : Colors.white70)),
        ),
      ]),
    ),
  );

  void _openNotify() => Navigator.push(context, _route(NotifyPage(getToken: idToken)));
  void _openCheck() => Navigator.push(context, _route(PushCheckPage(getToken: idToken)));

  // ── البناء ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final showBars = _app && !_splash;
    final tabIdx = _tabs.indexWhere((t) => t.id == _cur);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) { if (!did) _onBack(); },
      child: Scaffold(
        backgroundColor: kBg,
        appBar: showBars ? _appBar() : null,
        // ★ StackFit.expand: الصفحة تملأ الشاشة دائماً (بدونه تنكمش إلى صفر بعد اختفاء شاشة البدء)
        body: Stack(fit: StackFit.expand, children: [
          // قبل الدخول: الصفحة تحت شريط الحالة مباشرة
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: showBars ? 0 : MediaQuery.of(context).padding.top),
              child: _c == null ? const ColoredBox(color: kBg) : WebViewWidget(controller: _c!),
            ),
          ),
          if (showBars && _progress < 100)
            Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(
                value: _progress / 100, minHeight: 2, color: kGold, backgroundColor: Colors.transparent)),
          if (_error) Positioned.fill(child: _errorView()),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_splash,
              child: AnimatedOpacity(
                opacity: _splash ? 1 : 0,
                duration: const Duration(milliseconds: 350),
                child: const _Splash(),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: showBars && !_agent
            ? NavigationBar(
                selectedIndex: tabIdx < 0 ? 4 : tabIdx,
                onDestinationSelected: (i) => i == 4 ? _more() : _go(_tabs[i].id),
                destinations: [
                  for (final t in _tabs)
                    NavigationDestination(
                      icon: t.id == 'requests'
                          ? Badge(isLabelVisible: _pending > 0, label: Text('$_pending'),
                              backgroundColor: kRed, child: Icon(t.icon))
                          : Icon(t.icon),
                      label: t.title,
                    ),
                  const NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'المزيد'),
                ],
              )
            : null,
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    if (_search) {
      return AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 4,
        title: const Text('بحث شامل', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        leading: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: () => _toggleSearch(false)),
      );
    }
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('TOTV+', textDirection: TextDirection.ltr,
              style: TextStyle(color: kGold, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(4)),
            child: Text(_agent ? 'AGENT' : 'ADMIN',
                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ]),
        Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      ]),
      actions: [
        if (!_agent)
          IconButton(tooltip: 'بحث', icon: const Icon(Icons.search_rounded, size: 26),
              onPressed: () => _toggleSearch(true)),
        if (!_agent)
          IconButton(tooltip: 'إشعار فوري', icon: const Icon(Icons.campaign_rounded, color: kGold, size: 26),
              onPressed: _openNotify),
        GestureDetector(
          onLongPress: () => _refresh(hard: true),
          child: IconButton(tooltip: 'تحديث (اضغط مطولاً للتحديث الكامل)',
              icon: const Icon(Icons.refresh_rounded, size: 26), onPressed: () => _refresh()),
        ),
        if (_agent)
          IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              onPressed: () async { if (await _confirm('تسجيل الخروج؟')) _js('try{ doLogout(); }catch(e){}'); }),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _errorView() => Container(
    color: kBg,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(30),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_rounded, size: 54, color: Colors.white38),
      const SizedBox(height: 12),
      const Text('تعذّر التحميل — تحقّق من الإنترنت', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: () => _refresh(hard: true),
          icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة')),
    ]),
  );
}

PageRoute<T> _route<T>(Widget w) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 260),
  reverseTransitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (_, __, ___) => w,
  transitionsBuilder: (_, a, __, child) => SlideTransition(
    position: Tween(begin: const Offset(-0.12, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
    child: FadeTransition(opacity: a, child: child),
  ),
);

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Container(
    color: kBg,
    alignment: Alignment.center,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 92, height: 92, alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kGold.withOpacity(0.35)),
            boxShadow: [BoxShadow(color: kGold.withOpacity(0.15), blurRadius: 40)]),
        child: const Text('T', style: TextStyle(color: kGold, fontSize: 54, fontWeight: FontWeight.w900)),
      ),
      const SizedBox(height: 18),
      const Text('TOTV+ ADMIN', textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 4, color: Colors.white)),
      const SizedBox(height: 24),
      const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: kGold)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════
//  إرسال عبر دالة push (Supabase)
// ════════════════════════════════════════════════════════════════════
class PushApi {
  static Future<(int, String)> post(Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.postUrl(Uri.parse(kPushFn));
      req.headers
        ..set('apikey', kSupaKey)
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 25));
      final txt = await res.transform(utf8.decoder).join();
      return (res.statusCode, txt);
    } finally { client.close(); }
  }

  static Future<(int, Map<String, dynamic>?)> health() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(Uri.parse('$kPushFn/health'));
      req.headers.set('apikey', kSupaKey);
      final res = await req.close().timeout(const Duration(seconds: 20));
      final txt = await res.transform(utf8.decoder).join();
      Map<String, dynamic>? j;
      try { j = jsonDecode(txt) as Map<String, dynamic>; } catch (_) {}
      return (res.statusCode, j);
    } catch (_) {
      return (0, null);
    } finally { client.close(); }
  }

  static String explain(int code, String txt) {
    switch (code) {
      case 200: return '✅ تم الإرسال فوراً';
      case 403: return 'بريدك غير موجود في ADMIN_EMAILS — أضفه في أسرار الدالة';
      case 401: return 'انتهت جلسة الدخول — حدّث وسجّل الدخول من جديد';
      case 404: return 'دالة push غير منشورة في Supabase — افتح «فحص الإشعارات» للخطوات';
      case 500: return txt.contains('FCM_SERVICE_ACCOUNT')
          ? 'سرّ FCM_SERVICE_ACCOUNT غير مضبوط في الدالة'
          : 'خطأ في الدالة: ${txt.length > 120 ? txt.substring(0, 120) : txt}';
      case 0: return 'لا يوجد اتصال بالإنترنت';
      default: return 'خطأ $code: ${txt.length > 120 ? txt.substring(0, 120) : txt}';
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  إشعار فوري لكل المستخدمين — يظهر كأنه من تطبيق TOTV+
// ════════════════════════════════════════════════════════════════════
class NotifyPage extends StatefulWidget {
  final Future<String?> Function() getToken;
  const NotifyPage({super.key, required this.getToken});
  @override State<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends State<NotifyPage> {
  static const _kHist = 'notify_history_v1';
  static const _icon = '$kPushFn/icon.png';

  final _title = TextEditingController();
  final _body  = TextEditingController();
  final _image = TextEditingController();
  String _topic = 'all_users';
  bool _busy = false;
  List<Map<String, dynamic>> _hist = [];

  static const _topics = {
    'all_users': 'جميع المستخدمين',
    'matches': 'من فعّل إشعارات المباريات',
    'admins': 'تجربة — المشرفين فقط',
  };

  static const _templates = [
    ('🔥 عرض لفترة محدودة', 'اشترك الآن واحصل على أفضل سعر — العرض ينتهي قريباً'),
    ('🎬 محتوى جديد', 'أضفنا أفلاماً ومسلسلات جديدة — شاهدها الآن على TOTV+'),
    ('⚽ مباراة الليلة', 'لا تفوّت مباراة الليلة — تابعها مباشرة على TOTV+'),
    ('🛠️ تحديث مهم', 'حدّث التطبيق للحصول على أفضل تجربة مشاهدة'),
  ];

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _body.addListener(() => setState(() {}));
    _image.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kHist);
      if (raw != null) _hist = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final t = _title.text.trim(), b = _body.text.trim(), img = _image.text.trim();
    if (t.isEmpty || b.isEmpty) { _snack('اكتب العنوان ونص الإشعار'); return; }
    if (img.isNotEmpty && !img.startsWith('https://')) { _snack('رابط الصورة يجب أن يبدأ بـ https://'); return; }
    if (_topic == 'all_users') {
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('إرسال لجميع المستخدمين؟'),
        content: Text('«$t»\n$b', style: const TextStyle(height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إرسال الآن')),
        ],
      ));
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final token = await widget.getToken();
      if (token == null) { _snack('سجّل الدخول في لوحة الإدارة أولاً'); setState(() => _busy = false); return; }
      final (code, txt) = await PushApi.post({
        'action': 'broadcast', 'idToken': token,
        'title': t, 'body': b, 'image': img, 'topic': _topic,
      });
      if (code == 200) {
        HapticFeedback.heavyImpact();
        _hist.insert(0, {'t': t, 'b': b, 'to': _topic, 'at': DateTime.now().toIso8601String()});
        if (_hist.length > 30) _hist = _hist.take(30).toList();
        (await SharedPreferences.getInstance()).setString(_kHist, jsonEncode(_hist));
        _title.clear(); _body.clear(); _image.clear();
      }
      _snack(PushApi.explain(code, txt));
    } catch (e) {
      _snack('تعذّر الاتصال — تحقّق من الإنترنت');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating, backgroundColor: kCard,
      content: Text(m, style: const TextStyle(color: Colors.white))));
  }

  Widget _preview() {
    final t = _title.text.trim().isEmpty ? 'عنوان الإشعار' : _title.text.trim();
    final b = _body.text.trim().isEmpty ? 'نص الإشعار يظهر هنا' : _body.text.trim();
    final img = _image.text.trim().startsWith('https://') ? _image.text.trim() : _icon;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF22222A), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 18, height: 18, alignment: Alignment.center,
              decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle),
              child: const Text('T', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900))),
          const SizedBox(width: 6),
          const Text('TOTV+ • الآن', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(b, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
          ])),
          const SizedBox(width: 10),
          ClipRRect(borderRadius: BorderRadius.circular(8),
              child: Image.network(img, width: 46, height: 46, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 46, height: 46, color: Colors.black,
                      alignment: Alignment.center,
                      child: const Text('T', style: TextStyle(color: kGold, fontSize: 24, fontWeight: FontWeight.w900))))),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إشعار فوري', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [IconButton(tooltip: 'فحص الإشعارات', icon: const Icon(Icons.health_and_safety_rounded),
          onPressed: () => Navigator.push(context, _route(PushCheckPage(getToken: widget.getToken))))]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('معاينة', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white60)),
      const SizedBox(height: 6),
      _preview(),
      const SizedBox(height: 16),
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final (t, b) in _templates)
          Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ActionChip(
            label: Text(t), onPressed: () { _title.text = t; _body.text = b; })),
      ])),
      const SizedBox(height: 12),
      TextField(controller: _title, maxLength: 65,
          decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder())),
      const SizedBox(height: 6),
      TextField(controller: _body, maxLength: 240, maxLines: 4, minLines: 3,
          decoration: const InputDecoration(labelText: 'نص الإشعار', border: OutlineInputBorder())),
      const SizedBox(height: 6),
      TextField(controller: _image, textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'رابط صورة (اختياري — الافتراضي أيقونة TOTV+)',
              border: OutlineInputBorder())),
      const SizedBox(height: 14),
      const Text('المستلمون', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _topics.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: _topic == e.key,
            selectedColor: kGold,
            labelStyle: TextStyle(color: _topic == e.key ? Colors.black : Colors.white, fontWeight: FontWeight.w700),
            onSelected: (_) => setState(() => _topic = e.key),
          ),
      ]),
      const SizedBox(height: 20),
      SizedBox(height: 54, child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
        onPressed: _busy ? null : _send,
        icon: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
            : const Icon(Icons.send_rounded),
        label: const Text('إرسال الإشعار الآن', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
      )),
      const SizedBox(height: 26),
      if (_hist.isNotEmpty) ...[
        const Text('آخر الإشعارات المرسلة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        for (final h in _hist)
          Card(
            color: kCard,
            child: ListTile(
              title: Text('${h['t']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${h['b']}\n${_topics[h['to']] ?? h['to']} • ${'${h['at']}'.replaceFirst('T', ' ').substring(0, 16)}',
                  style: const TextStyle(color: Colors.white60, height: 1.5)),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.replay_rounded, color: kGold),
                tooltip: 'إعادة استخدام',
                onPressed: () => setState(() { _title.text = '${h['t']}'; _body.text = '${h['b']}'; }),
              ),
            ),
          ),
      ],
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════
//  فحص الإشعارات — يبيّن بالضبط أين المشكلة وكيف تُحل
// ════════════════════════════════════════════════════════════════════
class PushCheckPage extends StatefulWidget {
  final Future<String?> Function() getToken;
  const PushCheckPage({super.key, required this.getToken});
  @override State<PushCheckPage> createState() => _PushCheckPageState();
}

class _PushCheckPageState extends State<PushCheckPage> {
  bool _loading = true, _busy = false;
  int _code = -1;
  Map<String, dynamic>? _h;
  bool? _admin;
  List<String> _log = [];

  @override
  void initState() { super.initState(); _run(); }

  Future<void> _run() async {
    setState(() => _loading = true);
    await AdminPush.ready.future.timeout(const Duration(seconds: 25), onTimeout: () {});
    final (c, j) = await PushApi.health();
    String? tok;
    try { tok = await widget.getToken(); } catch (_) {}
    final log = await CrashLog.read();
    if (!mounted) return;
    setState(() { _code = c; _h = j; _admin = tok != null; _log = log; _loading = false; });
  }

  Future<void> _test(String action) async {
    setState(() => _busy = true);
    String msg;
    try {
      final tok = await widget.getToken();
      if (tok == null) {
        msg = 'سجّل الدخول في لوحة الإدارة أولاً';
      } else {
        final body = action == 'order'
            ? {'action': 'order', 'idToken': tok, 'order_id': 'TEST', 'name': 'تجربة من تطبيق الإدارة',
               'plan': 'شهر', 'price': '5,000', 'method': 'اختبار'}
            : {'action': 'broadcast', 'idToken': tok, 'topic': 'admins',
               'title': '✅ تجربة الإشعارات', 'body': 'إذا وصلك هذا فكل شيء يعمل'};
        final (code, txt) = await PushApi.post(body);
        msg = code == 200 ? '✅ أُرسل — يجب أن يصلك خلال ثوانٍ' : PushApi.explain(code, txt);
      }
    } catch (_) { msg = 'تعذّر الاتصال'; }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating,
        backgroundColor: kCard, content: Text(msg, style: const TextStyle(color: Colors.white))));
  }

  Widget _row(bool? ok, String title, String detail, {String? fix}) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kCard, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ok == false ? Colors.redAccent.withOpacity(0.5) : Colors.white10),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(ok == null ? Icons.help_outline_rounded : ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: ok == null ? Colors.white38 : ok ? const Color(0xFF20D460) : Colors.redAccent, size: 26),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 3),
        Text(detail, style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.5)),
        if (ok == false && fix != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kGold.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
            child: Text(fix, style: const TextStyle(fontSize: 12.5, height: 1.6)),
          ),
        ],
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final fnOk = _code == 200;
    final fcmOk = _h?['fcm'] == true;
    final admins = (_h?['admins'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('فحص الإشعارات', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [IconButton(onPressed: _loading ? null : _run, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : ListView(padding: const EdgeInsets.all(16), children: [
              const Text('استقبال الإشعارات على هذا الهاتف',
                  style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (AdminPush.safeMode || !AdminPush.enabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy ? null : () async {
                      setState(() => _busy = true);
                      await AdminPush.retry();
                      if (mounted) setState(() => _busy = false);
                      _run();
                    },
                    icon: const Icon(Icons.notifications_active_rounded),
                    label: const Text('إعادة تفعيل الإشعارات', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              _row(AdminPush.permission == null ? null
                      : AdminPush.permission == AuthorizationStatus.authorized ||
                        AdminPush.permission == AuthorizationStatus.provisional,
                  'إذن الإشعارات', 'السماح للتطبيق بعرض الإشعارات',
                  fix: 'الإعدادات ← التطبيقات ← TOTV+ Admin ← الإشعارات ← تفعيل'),
              _row(AdminPush.token != null, 'الاتصال بـ Firebase',
                  'المصدر: ${AdminPush.mode}${AdminPush.error.isNotEmpty ? '\n${AdminPush.error}' : ''}',
                  fix: 'تحقّق من الإنترنت ثم أعد فتح التطبيق. إن استمر: أضف تطبيق Android باسم com.totv.admin '
                      'في Firebase وضع ملفه google-services.json في totv_admin/android/app.'),
              _row(AdminPush.subscribed, 'قناة «طلبات الاشتراك»', 'الهاتف مشترك في إشعارات الطلبات والمشرفين'),
              const SizedBox(height: 14),
              const Text('دالة الإرسال (Supabase)', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _row(fnOk, 'دالة push منشورة',
                  _code == 0 ? 'لا اتصال' : fnOk ? 'تعمل' : 'الرد: $_code',
                  fix: 'الدالة غير منشورة. الأسهل: في GitHub أضف 3 أسرار '
                      '(SUPABASE_ACCESS_TOKEN و FCM_SERVICE_ACCOUNT و ADMIN_EMAILS) '
                      'ثم Actions ← «Supabase — Deploy push function» ← Run workflow.'),
              _row(fnOk ? fcmOk : null, 'مفتاح Firebase في الدالة',
                  fnOk ? (fcmOk ? 'FCM_SERVICE_ACCOUNT مضبوط (${_h?['project'] ?? ''})' : 'غير مضبوط') : '—',
                  fix: 'أضف سرّ FCM_SERVICE_ACCOUNT = محتوى ملف JSON من '
                      'Firebase ← Project settings ← Service accounts ← Generate new private key.'),
              _row(fnOk ? admins > 0 : null, 'بريد المشرف', fnOk ? 'عدد البريدات المسموحة: $admins' : '—',
                  fix: 'أضف سرّ ADMIN_EMAILS = بريدك (مثل haedirasso@gmail.com).'),
              _row(_admin, 'تسجيل الدخول في لوحة الإدارة', _admin == true ? 'مسجّل' : 'غير مسجّل',
                  fix: 'سجّل الدخول من الشاشة الرئيسية للتطبيق.'),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => AdminPush.show('🔔 تجربة محلية', 'هذا صوت وشكل إشعار الطلبات'),
                  icon: const Icon(Icons.volume_up_rounded), label: const Text('تجربة الصوت'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
                  onPressed: _busy ? null : () => _test('order'),
                  icon: const Icon(Icons.receipt_long_rounded), label: const Text('تجربة إشعار طلب'))),
              ]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _test('broadcast'),
                icon: const Icon(Icons.campaign_rounded), label: const Text('تجربة إشعار للمشرفين فقط'))),
              const SizedBox(height: 14),
              const Text('ملاحظة: إشعار الطلب يُحدَّد بطلب واحد كل 45 ثانية لكل حساب.',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              if (_log.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(child: Text('سجل الأخطاء (أرسله للدعم عند وجود مشكلة)',
                      style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800))),
                  IconButton(tooltip: 'نسخ', icon: const Icon(Icons.copy_rounded, size: 20),
                      onPressed: () => Clipboard.setData(ClipboardData(text: _log.join('\n')))),
                  IconButton(tooltip: 'مسح', icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      onPressed: () async { await CrashLog.clear(); _run(); }),
                ]),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
                  child: SelectableText(_log.join('\n\n'), textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'monospace')),
                ),
              ],
            ]),
    );
  }
}
