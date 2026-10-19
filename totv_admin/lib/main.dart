// ════════════════════════════════════════════════════════════════════
//  TOTV+ Admin — تطبيق الإدارة الأصلي (Native) v3
//
//  تطبيق Flutter كامل — بلا صفحات ويب:
//  • دخول مرة واحدة (Firebase + قاعدة الاشتراكات) ويبقى محفوظاً للأبد.
//  • الطلبات مباشرة (Live) + إشعار فوري بصوت الكاش عند كل طلب جديد.
//  • كل شيء محفوظ على الهاتف — لا يُعاد التحميل إلا عند ضغطك «تحديث».
//  • قراءات Firestore بالحد الأدنى: الطلبات المنتظرة فقط مباشرة،
//    والباقي من قاعدة الاشتراكات (مجانية) أو عند الطلب.
// ════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show DartPluginRegistrant;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

part 'core/theme.dart';
part 'core/util.dart';
part 'core/net.dart';
part 'core/push.dart';
part 'core/store.dart';
part 'core/panel_parser.dart';
part 'core/bot.dart';
part 'core/engage.dart';
part 'pages/login.dart';
part 'pages/shell.dart';
part 'pages/home.dart';
part 'pages/orders.dart';
part 'pages/activate.dart';
part 'pages/stock.dart';
part 'pages/members.dart';
part 'pages/codes.dart';
part 'pages/app_control.dart';
part 'pages/notify.dart';
part 'pages/agents.dart';
part 'pages/bot.dart';
part 'pages/chat.dart';
part 'pages/rewards.dart';

// إعداد Firebase المدمج (مشروع totvq-8e439) — مفاتيح عامة بطبيعتها وليست أسراراً.
// يُستخدم فقط إن لم يوجد google-services.json لتطبيق com.totv.admin.
const kFbAndroid = FirebaseOptions(
  apiKey: 'AIzaSyBR9NjEZHm9RhngSfYNMmphaH_gDLTApTY',
  appId: '1:214530463737:android:c6447caa773d03b1164f28',
  messagingSenderId: '214530463737',
  projectId: 'totvq-8e439',
  storageBucket: 'totvq-8e439.firebasestorage.app',
);
const kFbWebKey = FirebaseOptions(
  apiKey: 'AIzaSyCk0dSmHGQ248b-OQi44Rm2zWrfbpLBkpU',
  appId: '1:214530463737:android:c6447caa773d03b1164f28',
  messagingSenderId: '214530463737',
  projectId: 'totvq-8e439',
  storageBucket: 'totvq-8e439.firebasestorage.app',
);
const kProjectId = 'totvq-8e439';
const kSuperAdmins = {'admin@totv.com', 'haedirasso@gmail.com'};

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) => CrashLog.add('flutter: ${d.exceptionAsString()}');
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: K.bar,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    await Prefs.init();
    await Boot.firebase();
    runApp(const AdminApp());
  }, (e, st) => CrashLog.add('$e\n${st.toString().split('\n').take(4).join('\n')}'));
}

/// تهيئة Firebase: الملف الرسمي إن وُجد، وإلا الإعداد المدمج (مرة واحدة فقط)
class Boot {
  static String mode = '—';
  static String error = '';
  static bool ok = false;

  static Future<void> firebase() async {
    try {
      await Firebase.initializeApp();
      mode = 'google-services.json';
      ok = true;
    } catch (_) {
      try {
        final web = Prefs.p.getBool('fb_web_key') ?? false;
        await Firebase.initializeApp(options: web ? kFbWebKey : kFbAndroid);
        mode = web ? 'مدمج (مفتاح الويب)' : 'مدمج';
        ok = true;
      } catch (e) {
        error = '$e';
        CrashLog.add('firebase init: $e');
      }
    }
    if (ok) {
      try {
        // كاش محلي كامل: كل ما يُقرأ مرة يبقى على الهاتف ويُعرض فوراً
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (e) { CrashLog.add('fs settings: $e'); }
    }
  }
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TOTV+ Admin',
    debugShowCheckedModeBanner: false,
    navigatorKey: Nav.key,
    scaffoldMessengerKey: Nav.messenger,
    theme: K.theme(),
    builder: (context, child) => MediaQuery(
      // حجم خط ثابت: التصميم لا يتأثر بإعداد خط الهاتف
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
    home: const Gate(),
  );
}

/// البوابة: إن كان مسجّلاً ⇐ التطبيق مباشرة، وإلا شاشة الدخول
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) {
    if (!Boot.ok) return BootErrorPage(error: Boot.error);
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snap) {
        final u = snap.data;
        if (u == null) return const LoginPage();
        return Shell(key: ValueKey(u.uid));
      },
    );
  }
}

class BootErrorPage extends StatelessWidget {
  final String error;
  const BootErrorPage({super.key, required this.error});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.cloud_off_rounded, size: 64, color: K.red),
        const SizedBox(height: 16),
        Text('تعذّر تشغيل Firebase', style: K.h2),
        const SizedBox(height: 8),
        Text(error, textAlign: TextAlign.center, style: K.sub),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            await Prefs.p.setBool('fb_web_key', !(Prefs.p.getBool('fb_web_key') ?? false));
            UI.toast('أغلق التطبيق وافتحه من جديد');
          },
          child: const Text('تجربة المفتاح البديل'),
        ),
      ]),
    )),
  );
}
