part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🤖 البوت الداخلي — مراقب السيرفرات
//  يعمل داخل التطبيق بشكل مستمر:
//   • كل 15 دقيقة والتطبيق مفتوح، وكل 30 دقيقة في الخلفية (حتى لو أُغلق التطبيق)
//   • يكتشف: حساب سيرفر انتهى وعليه مشتركون · سينتهي خلال 24 ساعة / 3 أيام
//     · المخزون منخفض · مشتركون بلا حساب
//   • ينقل المشتركين تلقائياً من الحساب المنتهي إلى حساب متاح (النقل التلقائي)
//   • يرسل إشعاراً على هاتفك لكل حدث جديد (مرة واحدة فقط لكل حدث)
//   • يسجّل كل شيء في «سجل البوت» مع رسوم بيانية
// ════════════════════════════════════════════════════════════════════
class BotLog {
  static const _k = 'bot_log_v1';
  static final rev = Live<int>(0);

  static List<Map<String, dynamic>> read() {
    final l = Prefs.getList(_k) ?? [];
    return l.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static void add(String kind, String title, String body) {
    try {
      final l = read();
      l.insert(0, {'at': DateTime.now().toIso8601String(), 'kind': kind, 'title': title, 'body': body});
      Prefs.setJson(_k, l.take(400).toList());
      rev.value++;
    } catch (_) {}
  }

  static Future<void> clear() async { await Prefs.p.remove(_k); rev.value++; }
}

class BotReport {
  int lines = 0, free = 0, full = 0, expired = 0, review = 0, disabled = 0;
  int seats = 0, deadUsers = 0, soon3 = 0, moved = 0, failed = 0, alerts = 0;
  String error = '';
  Map<String, dynamic> toJson() => {'lines': lines, 'free': free, 'full': full, 'expired': expired, 'review': review,
    'disabled': disabled, 'seats': seats, 'dead': deadUsers, 'soon3': soon3, 'moved': moved, 'failed': failed,
    'alerts': alerts, 'error': error, 'at': DateTime.now().toIso8601String()};
}

class ServerBot {
  static const alarmId = 7701;
  static const channel = AndroidNotificationChannel(
    'server_bot', 'مراقب السيرفرات',
    description: 'تنبيهات انتهاء حسابات السيرفر والنقل التلقائي',
    importance: Importance.high,
  );
  static Timer? _timer;
  static bool _running = false;
  static final last = Live<Map<String, dynamic>>(Prefs.getJson('bot_last_v1') ?? {});

  static bool get background => Prefs.p.getBool('bot_bg') ?? true;
  static int get lowSeats => Prefs.p.getInt('bot_low') ?? 5;
  static int get intervalMin => Prefs.p.getInt('bot_interval') ?? 30;

  /// والتطبيق مفتوح: فحص بعد قليل ثم كل 15 دقيقة
  static void startForeground() {
    _timer?.cancel();
    Future.delayed(const Duration(seconds: 8), () => runIfDue(minutes: 10));
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => run());
    unawaited(schedule());
  }

  static void stopForeground() { _timer?.cancel(); _timer = null; }

  static Future<void> runIfDue({int minutes = 10}) async {
    final lastAt = DateTime.tryParse('${last.value['at'] ?? ''}');
    if (lastAt == null || DateTime.now().difference(lastAt).inMinutes >= minutes) await run();
  }

  /// جدولة العمل في الخلفية (حتى لو أُغلق التطبيق)
  static Future<void> schedule() async {
    try {
      await AndroidAlarmManager.initialize();
      if (!background) { await AndroidAlarmManager.cancel(alarmId); return; }
      await AndroidAlarmManager.periodic(Duration(minutes: intervalMin), alarmId, botAlarmCallback,
          allowWhileIdle: true, wakeup: true, rescheduleOnReboot: true);
    } catch (e) { CrashLog.add('bot schedule: $e'); }
  }

  /// الفحص الكامل
  static Future<BotReport> run({bool bg = false, bool manual = false}) async {
    final rep = BotReport();
    if (_running) return rep;
    _running = true;
    try {
      // البوت قد يعمل في الخلفية (عملية منفصلة) — نقرأ آخر ما كتبه
      try { await Prefs.p.reload(); } catch (_) {}
      if (!Supa.linked.value) { rep.error = 'قاعدة الاشتراكات غير مربوطة'; return rep; }
      await AdminPush.ensureLocal();
      final r = await Future.wait([
        Supa.call('admin_lines_list'),
        Supa.call('admin_summary').catchError((_) => <String, dynamic>{}),
      ]);
      final list = r[0], sum = r[1];
      final old = await DiskCache.read('stock');
      await DiskCache.write('stock', {'list': list, 'sum': sum, 'impact': old is Map ? old['impact'] : null});
      final lines = list.l('lines').map((e) => Line(Map<String, dynamic>.from(e as Map))).toList();
      if (!bg) { StockLines.lines = lines; StockLines.currentHost = list.str('current_host'); StockLines.at = DateTime.now(); }

      final now = DateTime.now();
      final events = <(String, String, String, String, bool)>[]; // key, kind, title, body, notify
      rep.lines = lines.length;
      rep.seats = sum.i('stock_seats');
      final autoRescue = '${list['auto_rescue'] ?? 'on'}' == 'on';

      for (final l in lines) {
        switch (l.state) {
          case 'free': rep.free++; break;
          case 'full': rep.full++; break;
          case 'expired': rep.expired++; break;
          case 'review': rep.review++; break;
          case 'disabled': rep.disabled++; break;
        }
        final e = l.expiry;
        if (e == null || l.disabled) continue;
        final expKey = e.toIso8601String().substring(0, 16);
        if (!e.isAfter(now)) {
          if (l.users > 0) {
            rep.deadUsers += l.users;
            events.add(('dead:${l.id}:$expKey', 'dead', '⛔ انتهى حساب السيرفر ${l.username}',
                'عليه ${l.users} مشترك — ${autoRescue ? 'جاري نقلهم تلقائياً لحسابات متاحة' : 'انقلهم من صفحة المخزون'}', true));
          } else {
            events.add(('exp:${l.id}:$expKey', 'expired', 'انتهى حساب ${l.username}', 'الحساب فارغ — يمكنك حذفه أو تجديده', false));
          }
        } else if (l.users > 0) {
          final h = e.difference(now).inHours;
          if (h <= 24) {
            events.add(('soon1:${l.id}:$expKey', 'soon', '⏰ حساب ${l.username} ينتهي خلال $h ساعة',
                'عليه ${l.users} مشترك — جدّده في البنل أو سيُنقلون تلقائياً عند انتهائه', true));
          }
          if (h <= 72) {
            rep.soon3++;
            if (h > 24) {
              events.add(('soon3:${l.id}:$expKey', 'soon', '📅 حساب ${l.username} ينتهي ${Fmt.dayLabel(e)}',
                  'عليه ${l.users} مشترك · ينتهي ${Fmt.dt(e)}', true));
            }
          }
        }
      }
      if (rep.seats < lowSeats) {
        events.add(('low:${now.toIso8601String().substring(0, 10)}', 'low', '📦 المخزون منخفض: ${rep.seats} مقعد',
            'أضف حسابات سيرفر جديدة حتى لا تتوقف التفعيلات', true));
      }

      // ── النقل التلقائي ──
      final needsMove = lines.any((l) => (l.disabled || (l.expiry != null && !l.expiry!.isAfter(now))) && l.users > 0);
      if (autoRescue && needsMove) {
        // في الخلفية: ننقل فقط إن كان Firebase جاهزاً لكتابة البيانات الجديدة عند المشتركين
        if (!bg || Boot.ok) {
          try {
            final rr = await Supa.call('admin_rescue', {'p_dry': false, 'p_line_id': null});
            final moved = rr.l('moved').map((e) => Map<String, dynamic>.from(e as Map)).toList();
            final failed = rr.l('failed');
            rep.moved = moved.length;
            rep.failed = failed.length;
            if (moved.isNotEmpty) {
              await syncUsersCreds(moved);
              events.add(('moved:${now.millisecondsSinceEpoch}', 'moved', '🔁 نُقل ${moved.length} مشترك تلقائياً',
                  moved.take(4).map((m) => '${m.str('email').isEmpty ? m.str('uid') : m.str('email')}: ${m.str('from')} ⇐ ${m.str('to')}').join('\n'), true));
            }
            if (failed.isNotEmpty) {
              events.add(('failed:${now.toIso8601String().substring(0, 13)}', 'failed', '🛑 ${failed.length} مشترك بلا حساب متاح',
                  'المخزون لا يكفي — أضف حسابات ثم اضغط «نقل الآن»', true));
            }
            await Prefs.p.setInt('rescue_at', now.millisecondsSinceEpoch);
          } catch (e) { CrashLog.add('bot rescue: $e'); }
        }
      }

      // ── أحداث جديدة فقط: سجل + إشعار ──
      final seen = (Prefs.p.getStringList('bot_seen_v1') ?? []).toSet();
      final fresh = events.where((e) => !seen.contains(e.$1)).toList();
      for (final e in fresh) {
        BotLog.add(e.$2, e.$3, e.$4);
        seen.add(e.$1);
      }
      final notify = fresh.where((e) => e.$5).toList();
      rep.alerts = notify.length;
      if (notify.length == 1) {
        await AdminPush.show(notify.first.$3, notify.first.$4, channel: channel, payload: 'bot');
      } else if (notify.length > 1) {
        await AdminPush.show('🤖 مراقب السيرفرات: ${notify.length} تنبيهات', notify.map((e) => e.$3).join('\n'), channel: channel, payload: 'bot');
      }
      await Prefs.p.setStringList('bot_seen_v1', seen.toList().reversed.take(600).toList());
      if (manual && fresh.isEmpty) BotLog.add('run', 'فحص يدوي — لا جديد', '${rep.free} حساب متاح · ${rep.seats} مقعد');

      // ── لقطة للرسوم (كل 30 دقيقة على الأكثر) ──
      final m = Prefs.getList('bot_metrics_v1') ?? [];
      final lastT = m.isEmpty ? null : DateTime.tryParse('${(m.first as Map)['t']}');
      if (lastT == null || now.difference(lastT).inMinutes >= 30) {
        m.insert(0, {'t': now.toIso8601String(), 'seats': rep.seats, 'free': rep.free, 'full': rep.full,
          'expired': rep.expired, 'dead': rep.deadUsers, 'active': sum.i('active_total')});
        await Prefs.setJson('bot_metrics_v1', m.take(300).toList());
      }
    } catch (e) {
      rep.error = Fmt.err(e);
      CrashLog.add('bot: $e');
    } finally {
      _running = false;
      final j = rep.toJson()..['bg'] = bg;
      await Prefs.setJson('bot_last_v1', j);
      last.value = j;
    }
    return rep;
  }
}

/// كتابة بيانات الحساب الجديد عند المشتركين في Firestore (دفعات 400)
Future<void> syncUsersCreds(List<Map<String, dynamic>> rows) async {
  final fs = FirebaseFirestore.instance;
  for (var i = 0; i < rows.length; i += 400) {
    final b = fs.batch();
    for (final m in rows.skip(i).take(400)) {
      if (m.str('uid').isEmpty) continue;
      b.update(fs.collection('users').doc(m.str('uid')), {
        'subscription.host': m.str('host'), 'subscription.server_host': m.str('host'),
        'subscription.username': m.str('username'), 'subscription.password': m.str('password'),
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    try { await b.commit(); } catch (e) { CrashLog.add('sync users: $e'); }
  }
}

/// يُستدعى من Android كل 30 دقيقة حتى لو كان التطبيق مغلقاً
@pragma('vm:entry-point')
Future<void> botAlarmCallback() async {
  try {
    DartPluginRegistrant.ensureInitialized();
    await Prefs.init();
    if (!(Prefs.p.getBool('bot_bg') ?? true)) return;
    if (!Boot.ok) await Boot.firebase();
    await ServerBot.run(bg: true);
  } catch (e) {
    try { CrashLog.add('bot bg: $e'); } catch (_) {}
  }
}
