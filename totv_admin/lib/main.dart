// ════════════════════════════════════════════════════════════════════
//  TOTV+ Admin — تطبيق الإدارة
//
//  • صفحة الأدمن (v6.1) كما هي تماماً، تُخدم من داخل التطبيق على
//    http://localhost:8787 (نفس طريقة «التشغيل المحلي») داخل WebView كامل.
//    تسجيل الدخول والإعدادات والكاش محفوظة على الجهاز كما في المتصفح.
//  • دعم أصلي لما لا يعمل داخل WebView افتراضياً:
//    نوافذ alert/confirm/prompt · اختيار الصور · تنزيل CSV/TXT (مشاركة)
//    · النسخ · فتح واتساب/تلجرام/الهاتف خارج التطبيق.
//  • زر «تحديث»: يمسح كاش بيانات الصفحة ويعيد تحميلها (بدون تسجيل خروج).
//  • إشعار فوري عند وصول طلب اشتراك جديد (بصوت الكاش) — الضغط يفتح الطلبات.
//  • عدّاد الطلبات المنتظرة في الشريط العلوي.
//  • زر «إشعار»: إشعار فوري لكل المستخدمين بصورة أيقونة TOTV+
//    عبر Supabase Edge Function «push» (مجانية — مفتاح Firebase لا يدخل الهاتف).
// ════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const kGold = Color(0xFFF5A623);
const kBg   = Color(0xFF0B0B0E);
const kCard = Color(0xFF16161A);

// Supabase (مفاتيح عامة — نفس الموجودة في صفحة الأدمن)
const kSupaUrl = 'https://hlmaksidfqdarwunedqj.supabase.co';
const kSupaKey = 'sb_publishable_-lEvqrjoQgkXJdN4lZExxw_1cycMoEj';
const kPushFn  = '$kSupaUrl/functions/v1/push';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdminPush.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBg,
  ));
  runApp(const AdminApp());
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
    ),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const AdminShell(),
  );
}

// ════════════════════════════════════════════════════════════════════
//  إشعارات الإدارة — طلبات الاشتراك الجديدة
// ════════════════════════════════════════════════════════════════════
class AdminPush {
  static bool enabled = false;
  static final _ln = FlutterLocalNotificationsPlugin();
  /// يُستدعى عند الضغط على إشعار طلب (opened=true) أو وصوله والتطبيق مفتوح
  static void Function(bool opened)? onOrder;
  static bool _pendingOpen = false;

  static const _orders = AndroidNotificationChannel(
    'admin_orders', 'طلبات الاشتراك',
    description: 'إشعار فوري عند وصول طلب اشتراك جديد',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('cash'),
  );

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[push] Firebase غير مضبوط (google-services.json): $e');
      return;
    }
    try {
      await _ln.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
        onDidReceiveNotificationResponse: (_) => _open(),
      );
      await _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_orders);
      final m = FirebaseMessaging.instance;
      await m.requestPermission(alert: true, badge: true, sound: true);
      await m.subscribeToTopic('admin_orders');
      await m.subscribeToTopic('admins');
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n == null) return;
        _ln.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, n.title, n.body,
          NotificationDetails(android: AndroidNotificationDetails(
            _orders.id, _orders.name,
            importance: Importance.max, priority: Priority.max,
            icon: '@drawable/ic_notification',
            sound: const RawResourceAndroidNotificationSound('cash'),
            color: kGold,
          )));
        if (msg.data['type'] == 'order') onOrder?.call(false);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((msg) { if (msg.data['type'] == 'order') _open(); });
      final first = await m.getInitialMessage();
      if (first?.data['type'] == 'order') _pendingOpen = true;
      enabled = true;
    } catch (e) { debugPrint('[push] $e'); }
  }

  static void _open() { if (onOrder != null) { onOrder!(true); } else { _pendingOpen = true; } }

  /// بعد تجهيز الصفحة: إن فُتح التطبيق من إشعار طلب ⇐ افتح الطلبات
  static void flushPending() { if (_pendingOpen) { _pendingOpen = false; onOrder?.call(true); } }
}

// ════════════════════════════════════════════════════════════════════
//  خادم محلي صغير — يقدّم صفحة الأدمن من داخل التطبيق
// ════════════════════════════════════════════════════════════════════
class LocalSite {
  static HttpServer? _server;
  static String? _html;

  static Future<String> start() async {
    if (_server != null) return 'http://localhost:${_server!.port}/';
    _html ??= await rootBundle.loadString('assets/admin/index.html');
    // منفذ ثابت حتى يبقى تسجيل الدخول والإعدادات محفوظة بين التشغيلات
    for (final port in [8787, 8788, 8789, 8790]) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true);
        break;
      } catch (_) {}
    }
    _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
    return 'http://localhost:${_server!.port}/';
  }

  static void _handle(HttpRequest req) {
    final res = req.response;
    final path = req.uri.path;
    res.headers.set('Cache-Control', 'no-store');
    if (path == '/' || path == '/index.html') {
      res.headers.contentType = ContentType.html;
      res.write(_html);
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
//  الشاشة الرئيسية — WebView + شريط أدوات أصلي
// ════════════════════════════════════════════════════════════════════
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  WebViewController? _c;
  String _base = '';
  int _progress = 0;
  bool _error = false;
  int _pending = 0;
  Timer? _badgeTimer;
  bool _pageReady = false;
  final Map<int, Completer<String?>> _tokenWaiters = {};
  int _tokenSeq = 0;
  DateTime _lastBack = DateTime.fromMillisecondsSinceEpoch(0);

  // يُحقن بعد كل تحميل: نسخ + تنزيل الملفات عبر التطبيق
  static const _bridgeJs = r'''
(function(){
  if (window.__totvNative) return; window.__totvNative = true;
  function post(o){ try{ TotvNative.postMessage(JSON.stringify(o)); }catch(e){} }
  // النسخ
  var cb = { writeText: function(t){ post({t:'copy', v:String(t)}); return Promise.resolve(); },
             readText: function(){ return Promise.resolve(''); } };
  try { Object.defineProperty(navigator, 'clipboard', { value: cb, configurable: true }); }
  catch(e){ try { navigator.clipboard.writeText = cb.writeText; } catch(_){} }
  // لا نحذف روابط blob فوراً حتى نقرأها
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
})();
''';

  @override
  void initState() {
    super.initState();
    AdminPush.onOrder = (opened) { if (opened) { _openOrders(); } else { _reloadOrdersIfOpen(); } };
    _init();
    _badgeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _readBadge());
  }

  @override
  void dispose() { _badgeTimer?.cancel(); AdminPush.onOrder = null; super.dispose(); }

  // ── الطلبات: فتح القسم + العدّاد ─────────────────────────────────────
  Future<void> _openOrders() async {
    await _c?.runJavaScript("try{ nav('requests'); var b=document.querySelector('[data-rf=pending]'); "
        "if(b && typeof setReqFilter==='function') setReqFilter(b,'pending'); loadRequests(); }catch(e){}");
  }

  Future<void> _reloadOrdersIfOpen() async {
    await _c?.runJavaScript("try{ if(typeof refreshReqBadge==='function') refreshReqBadge(); "
        "if(typeof CUR!=='undefined' && CUR==='requests') loadRequests(); }catch(e){}");
    Future.delayed(const Duration(seconds: 2), _readBadge);
  }

  Future<void> _readBadge() async {
    final c = _c;
    if (c == null || !_pageReady) return;
    try {
      final r = await c.runJavaScriptReturningResult(
          "(function(){var e=document.getElementById('nb-req');return e?e.textContent:'0';})()");
      final n = int.tryParse('$r'.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (mounted && n != _pending) setState(() => _pending = n);
    } catch (_) {}
  }

  /// توكن Firebase للمشرف المسجّل في الصفحة (لإثبات هويته عند الإرسال)
  Future<String?> idToken() async {
    final c = _c;
    if (c == null) return null;
    final id = ++_tokenSeq;
    final done = Completer<String?>();
    _tokenWaiters[id] = done;
    await c.runJavaScript('''
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
    _base = await LocalSite.start();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kBg)
      ..addJavaScriptChannel('TotvNative', onMessageReceived: (m) => _onBridge(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) { if (mounted) setState(() => _progress = p); },
        onPageStarted: (_) { if (mounted) setState(() => _error = false); },
        onPageFinished: (_) async {
          await _c?.runJavaScript(_bridgeJs);
          _pageReady = true;
          Future.delayed(const Duration(seconds: 4), () { _readBadge(); AdminPush.flushPending(); });
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) setState(() => _error = true);
        },
        onNavigationRequest: (req) {
          final u = req.url;
          if (u.startsWith(_base) || u.startsWith('about:') || u.startsWith('blob:') || u.startsWith('data:')) {
            return NavigationDecision.navigate;
          }
          // أي رابط خارجي (واتساب، تلجرام، هاتف، صور الإيصالات…) يُفتح خارج التطبيق
          launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
      ))
      ..setOnJavaScriptAlertDialog((r) => _alert(r.message))
      ..setOnJavaScriptConfirmDialog((r) => _confirm(r.message))
      ..setOnJavaScriptTextInputDialog((r) => _prompt(r.message, r.defaultText ?? ''));

    if (c.platform is AndroidWebViewController) {
      final a = c.platform as AndroidWebViewController;
      a.setMediaPlaybackRequiresUserGesture(false);
      a.setOnShowFileSelector(_pickFiles);
    }
    await c.loadRequest(Uri.parse(_base));
    if (mounted) setState(() => _c = c);
  }

  // ── الجسر بين الصفحة والتطبيق ─────────────────────────────────────
  Future<void> _onBridge(String raw) async {
    try {
      final m = jsonDecode(raw) as Map;
      switch (m['t']) {
        case 'copy':
          await Clipboard.setData(ClipboardData(text: '${m['v'] ?? ''}'));
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

  // ── نوافذ JavaScript ─────────────────────────────────────────────
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
    // null = المستخدم ألغى (الصفحة تتعامل مع '' كإلغاء أيضاً في أغلب الحالات)
    return r ?? '';
  }

  void _toast(String msg) {
    if (!mounted || msg.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kCard,
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        duration: const Duration(seconds: 2),
      ));
  }

  // ── التحديث ──────────────────────────────────────────────────────
  Future<void> _refresh({bool hard = false}) async {
    final c = _c;
    if (c == null) return;
    HapticFeedback.mediumImpact();
    // يمسح كاش البيانات داخل الصفحة (totv_cache_*) بدون تسجيل الخروج
    await c.runJavaScript('''
      try { if (typeof cacheClear === 'function') cacheClear(); } catch(e) {}
      try { Object.keys(localStorage).filter(function(k){ return k.indexOf('totv_cache_') === 0; })
              .forEach(function(k){ localStorage.removeItem(k); }); } catch(e) {}
    ''');
    if (hard) await c.clearCache();
    await c.reload();
    _toast(hard ? '⟳ تحديث كامل للصفحات والبيانات' : '⟳ تم تحديث البيانات');
  }

  Future<void> _onBack() async {
    final c = _c;
    if (c != null && await c.canGoBack()) { await c.goBack(); return; }
    final now = DateTime.now();
    if (now.difference(_lastBack).inSeconds < 2) { SystemNavigator.pop(); return; }
    _lastBack = now;
    _toast('اضغط رجوع مرة أخرى للخروج');
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) { if (!did) _onBack(); },
      child: Scaffold(
        body: Column(children: [
          // ── شريط الأدوات ──
          Container(
            padding: EdgeInsets.fromLTRB(8, top + 4, 8, 4),
            color: kBg,
            child: Row(children: [
              const SizedBox(width: 6),
              const Text('TOTV+', textDirection: TextDirection.ltr,
                  style: TextStyle(color: kGold, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(6)),
                child: const Text('ADMIN', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'الطلبات',
                onPressed: _openOrders,
                icon: Badge(
                  isLabelVisible: _pending > 0,
                  label: Text('$_pending'),
                  backgroundColor: const Color(0xFFE50914),
                  child: const Icon(Icons.receipt_long_rounded, size: 25),
                ),
              ),
              IconButton(
                tooltip: 'إشعار لكل المستخدمين',
                icon: const Icon(Icons.campaign_rounded, color: kGold, size: 26),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => NotifyPage(getToken: idToken))),
              ),
              GestureDetector(
                onLongPress: () => _refresh(hard: true),
                child: IconButton(
                  tooltip: 'تحديث (اضغط مطولاً للتحديث الكامل)',
                  icon: const Icon(Icons.refresh_rounded, size: 26),
                  onPressed: () => _refresh(),
                ),
              ),
            ]),
          ),
          if (_progress < 100)
            LinearProgressIndicator(value: _progress / 100, minHeight: 2,
                color: kGold, backgroundColor: Colors.transparent),
          Expanded(child: _c == null
              ? const Center(child: CircularProgressIndicator(color: kGold))
              : Stack(children: [
                  WebViewWidget(controller: _c!),
                  if (_error)
                    Container(
                      color: kBg,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(30),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.wifi_off_rounded, size: 54, color: Colors.white38),
                        const SizedBox(height: 12),
                        const Text('تعذّر التحميل — تحقّق من الإنترنت',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        FilledButton.icon(onPressed: () => _refresh(),
                            icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة')),
                      ]),
                    ),
                ])),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  إشعار فوري لكل المستخدمين — يظهر كأنه من تطبيق TOTV+ (أيقونته وصورته)
//  يُرسل عبر Supabase Edge Function «push» التي تتحقق أنك مشرف.
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
      if (token == null) { _snack('سجّل الدخول في صفحة الإدارة أولاً'); setState(() => _busy = false); return; }
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse(kPushFn));
      req.headers
        ..set('apikey', kSupaKey)
        ..contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'action': 'broadcast', 'idToken': token,
        'title': t, 'body': b, 'image': img, 'topic': _topic,
      })));
      final res = await req.close().timeout(const Duration(seconds: 25));
      final txt = await res.transform(utf8.decoder).join();
      client.close();
      if (res.statusCode == 200) {
        HapticFeedback.heavyImpact();
        _hist.insert(0, {'t': t, 'b': b, 'to': _topic, 'at': DateTime.now().toIso8601String()});
        if (_hist.length > 30) _hist = _hist.take(30).toList();
        (await SharedPreferences.getInstance()).setString(_kHist, jsonEncode(_hist));
        _title.clear(); _body.clear(); _image.clear();
        _snack('✅ تم الإرسال فوراً');
      } else if (res.statusCode == 403) {
        _snack('بريدك غير موجود في ADMIN_EMAILS داخل Supabase');
      } else if (res.statusCode == 401) {
        _snack('انتهت جلسة الدخول — حدّث الصفحة وسجّل الدخول');
      } else if (res.statusCode == 404) {
        _snack('دالة push غير منشورة في Supabase بعد');
      } else {
        _snack('خطأ ${res.statusCode}: ${txt.length > 140 ? txt.substring(0, 140) : txt}');
      }
    } catch (e) {
      _snack('تعذّر الاتصال: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating, backgroundColor: kCard,
      content: Text(m, style: const TextStyle(color: Colors.white))));
  }

  // معاينة بشكل إشعار أندرويد الحقيقي
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
    appBar: AppBar(
      backgroundColor: kBg,
      title: const Text('إشعار فوري', style: TextStyle(fontWeight: FontWeight.w800)),
    ),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (!AdminPush.enabled)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kGold.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kGold.withOpacity(0.35))),
          child: const Text('إرسال الإشعارات يعمل. لاستقبال إشعارات الطلبات على هذا الهاتف أضف '
              'google-services.json لتطبيق com.totv.admin ثم ابنِ من جديد.',
              style: TextStyle(fontSize: 12.5, height: 1.5)),
        ),
      const Text('معاينة', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white60)),
      const SizedBox(height: 6),
      _preview(),
      const SizedBox(height: 16),
      SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: [
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
