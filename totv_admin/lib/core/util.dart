part of '../main.dart';

class Prefs {
  static late SharedPreferences p;
  static Future<void> init() async { p = await SharedPreferences.getInstance(); }

  static Map<String, dynamic>? getJson(String k) {
    try { final s = p.getString(k); return s == null ? null : jsonDecode(s) as Map<String, dynamic>; } catch (_) { return null; }
  }
  static List<dynamic>? getList(String k) {
    try { final s = p.getString(k); return s == null ? null : jsonDecode(s) as List<dynamic>; } catch (_) { return null; }
  }
  static Future<void> setJson(String k, Object v) async {
    try { await p.setString(k, jsonEncode(v, toEncodable: _enc)); } catch (e) { CrashLog.add('prefs $k: $e'); }
  }
  static Object? _enc(Object? o) {
    if (o is DateTime) return o.toIso8601String();
    if (o is Timestamp) return o.toDate().toIso8601String();
    if (o is FieldValue) return null;
    return o.toString();
  }
}

/// تنسيق الأرقام والتواريخ — أرقام لاتينية واضحة
class Fmt {
  static String n(num? v) {
    if (v == null) return '—';
    final s = v.round().abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return (v < 0 ? '-' : '') + b.toString();
  }

  static String two(int x) => x.toString().padLeft(2, '0');
  static const _months = ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'];
  static const _days = ['الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];

  static String date(DateTime? d) => d == null ? '—' : '${d.day} ${_months[d.month - 1]} ${d.year}';
  static String dateShort(DateTime? d) => d == null ? '—' : '${two(d.day)}/${two(d.month)}/${d.year}';
  static String time(DateTime? d) => d == null ? '—' : '${two(d.hour)}:${two(d.minute)}';
  static String dt(DateTime? d) => d == null ? '—' : '${dateShort(d)}  ${time(d)}';
  static String weekday(DateTime d) => _days[d.weekday - 1];

  static String dayLabel(DateTime d) {
    final now = DateTime.now();
    final a = DateTime(d.year, d.month, d.day), b = DateTime(now.year, now.month, now.day);
    final diff = b.difference(a).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    if (diff == -1) return 'غداً';
    if (diff > 1 && diff < 7) return '${weekday(d)} ${d.day} ${_months[d.month - 1]}';
    return date(d);
  }

  static String ago(DateTime? d) {
    if (d == null) return '—';
    final s = DateTime.now().difference(d).inSeconds;
    if (s < 0) return 'بعد ${dur(-s)}';
    if (s < 60) return 'الآن';
    if (s < 3600) return 'منذ ${s ~/ 60} د';
    if (s < 86400) return 'منذ ${s ~/ 3600} س';
    if (s < 172800) return 'أمس';
    if (s < 30 * 86400) return 'منذ ${s ~/ 86400} يوم';
    return dateShort(d);
  }

  static String dur(int sec) {
    if (sec < 60) return '$sec ث';
    if (sec < 3600) return '${sec ~/ 60} د';
    if (sec < 86400) return '${(sec / 3600).toStringAsFixed(sec < 36000 ? 1 : 0)} س';
    return '${(sec / 86400).toStringAsFixed(sec < 864000 ? 1 : 0)} يوم';
  }

  /// الأيام المتبقية (سالب = منتهي)
  static int? daysLeft(DateTime? d) {
    if (d == null) return null;
    return (d.difference(DateTime.now()).inMinutes / 1440).ceil();
  }

  static DateTime? toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is Timestamp) return v.toDate();
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v > 1e12 ? v.toInt() : (v * 1000).toInt());
    if (v is Map) {
      final s = v['_seconds'] ?? v['seconds'];
      if (s is num) return DateTime.fromMillisecondsSinceEpoch((s * 1000).toInt());
    }
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  static int numOf(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v'.replaceAll(RegExp(r'[^0-9\-]'), '')) ?? 0;
  }

  static String s(dynamic v) => v == null ? '' : '$v';

  static String err(Object e) {
    var m = e.toString();
    m = m.replaceFirst('Exception: ', '').replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
    if (m.contains('permission-denied') || m.contains('PERMISSION_DENIED')) return 'لا تملك صلاحية — تأكد أن حسابك مشرف';
    if (m.contains('network') || m.contains('SocketException') || m.contains('Failed host lookup')) return 'لا يوجد اتصال بالإنترنت';
    if (m.contains('TimeoutException')) return 'انتهت المهلة — الشبكة بطيئة';
    return m.length > 160 ? '${m.substring(0, 160)}…' : m;
  }

  static const planAr = {'monthly': 'شهري', 'quarterly': '3 أشهر', 'yearly': 'سنوي', 'premium': 'بريميوم',
      'trial': 'تجريبي', 'free': 'مجاني', 'manual': 'يدوي'};
  static const srcAr = {'code': 'كود تفعيل', 'manual': 'تفعيل يدوي', 'stock': 'من المخزون', 'vip': 'VIP', 'unknown': 'غير محدّد'};
  static String plan(String? p) => planAr[p] ?? (p == null || p.isEmpty ? '—' : p);
}

extension MapX on Map<String, dynamic> {
  String str(String k) => this[k] == null ? '' : '${this[k]}';
  int i(String k) => Fmt.numOf(this[k]);
  bool b(String k) => this[k] == true;
  DateTime? d(String k) => Fmt.toDate(this[k]);
  Map<String, dynamic> m(String k) => this[k] is Map ? Map<String, dynamic>.from(this[k] as Map) : <String, dynamic>{};
  List<dynamic> l(String k) => this[k] is List ? this[k] as List : const [];
}

/// متغيّر مراقَب بسيط بدل مكتبات إدارة الحالة
class Live<T> extends ValueNotifier<T> {
  Live(super.v);
  void bump() => notifyListeners();
}
