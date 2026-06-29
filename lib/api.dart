import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ════════════════════════════════════════════════════════════════
///  TOTV+ TV — عميل Xtream خفيف (نفس منطق التطبيق الأساسي)
///  لا Firebase — تسجيل دخول بيوزر/باسوورد وهوست ثابت + كاش محلي
/// ════════════════════════════════════════════════════════════════

const String kFixedHost = 'http://max.m950.org:2052'; // الهوست الثابت

class Session {
  static String user = '';
  static String pass = '';
  static bool get isLoggedIn => user.isNotEmpty && pass.isNotEmpty;

  static const _kU = 'tv_user', _kP = 'tv_pass';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    user = p.getString(_kU) ?? '';
    pass = p.getString(_kP) ?? '';
  }

  static Future<void> save(String u, String pw) async {
    user = u.trim();
    pass = pw.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kU, user);
    await p.setString(_kP, pass);
  }

  static Future<void> logout() async {
    user = '';
    pass = '';
    final p = await SharedPreferences.getInstance();
    await p.remove(_kU);
    await p.remove(_kP);
    Api.clearMemory();
  }
}

class Api {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
  ));

  static String _api(String action, {Map<String, String>? extra}) {
    final params = <String, String>{
      'username': Session.user,
      'password': Session.pass,
      'action': action,
      ...?extra,
    };
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$kFixedHost/player_api.php?$q';
  }

  /// رابط البث — type: live | movie | series
  static String streamUrl(String type, String id, String ext) =>
      '$kFixedHost/$type/${Session.user}/${Session.pass}/$id.$ext';

  /// تحقّق تسجيل الدخول (يرجع true إن كان الحساب صالحاً)
  static Future<bool> validate(String user, String pass) async {
    try {
      final url =
          '$kFixedHost/player_api.php?username=${Uri.encodeComponent(user)}&password=${Uri.encodeComponent(pass)}';
      final r = await _dio.get(url);
      final data = r.data is String ? jsonDecode(r.data) : r.data;
      if (data is Map && data['user_info'] is Map) {
        final auth = data['user_info']['auth'];
        final status = (data['user_info']['status'] ?? '').toString();
        return auth == 1 || status.toLowerCase() == 'active';
      }
    } catch (e) {
      debugPrint('[Api.validate] $e');
    }
    return false;
  }

  static Future<List<dynamic>> _list(String action,
      {Map<String, String>? extra}) async {
    try {
      final r = await _dio.get(_api(action, extra: extra));
      final d = r.data is String ? jsonDecode(r.data) : r.data;
      if (d is List) return d;
      if (d is Map && d['data'] is List) return d['data'] as List;
    } catch (e) {
      debugPrint('[Api.$action] $e');
    }
    return [];
  }

  // ── الذاكرة المؤقتة (RAM) ──────────────────────────────────
  static List<dynamic> movieCats = [], seriesCats = [], liveCats = [];
  static List<dynamic> movies = [], series = [], live = [];
  static bool loaded = false;

  static void clearMemory() {
    movieCats = seriesCats = liveCats = [];
    movies = series = live = [];
    loaded = false;
  }

  // ── الكاش على القرص (SharedPreferences) + TTL يوم ──────────
  static const _kTime = 'tv_cache_time';
  static const _ttlMs = 24 * 60 * 60 * 1000;

  static Future<void> _saveDisk() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('tv_mc', jsonEncode(movieCats));
      await p.setString('tv_sc', jsonEncode(seriesCats));
      await p.setString('tv_lc', jsonEncode(liveCats));
      await p.setString('tv_m', jsonEncode(movies.take(2500).toList()));
      await p.setString('tv_s', jsonEncode(series.take(2500).toList()));
      await p.setString('tv_l', jsonEncode(live.take(2000).toList()));
      await p.setInt(_kTime, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[Api._saveDisk] $e');
    }
  }

  static Future<bool> _loadDisk() async {
    try {
      final p = await SharedPreferences.getInstance();
      final t = p.getInt(_kTime) ?? 0;
      if (t == 0) return false;
      List<dynamic> dec(String? s) =>
          (s == null || s.isEmpty) ? [] : (jsonDecode(s) as List);
      movieCats = dec(p.getString('tv_mc'));
      seriesCats = dec(p.getString('tv_sc'));
      liveCats = dec(p.getString('tv_lc'));
      movies = dec(p.getString('tv_m'));
      series = dec(p.getString('tv_s'));
      live = dec(p.getString('tv_l'));
      final fresh =
          DateTime.now().millisecondsSinceEpoch - t < _ttlMs;
      loaded = movies.isNotEmpty || live.isNotEmpty;
      return loaded && fresh;
    } catch (e) {
      debugPrint('[Api._loadDisk] $e');
      return false;
    }
  }

  /// تحميل كل المحتوى — كاش أولاً (فوري) ثم تحديث من السيرفر إن لزم
  static Future<void> loadAll({bool force = false}) async {
    if (!force) {
      final fresh = await _loadDisk();
      if (fresh) {
        loaded = true;
        return; // كاش حديث — لا اتصال بالسيرفر (خفّة + سرعة)
      }
    }
    final res = await Future.wait([
      _list('get_vod_categories'),
      _list('get_series_categories'),
      _list('get_live_categories'),
      _list('get_vod_streams'),
      _list('get_series'),
      _list('get_live_streams'),
    ]);
    movieCats = res[0];
    seriesCats = res[1];
    liveCats = res[2];
    movies = res[3];
    series = res[4];
    live = res[5];
    loaded = true;
    await _saveDisk();
  }

  /// تفاصيل حلقة/مواسم مسلسل
  static Future<Map<String, dynamic>> seriesInfo(String id) async {
    try {
      final r = await _dio.get(_api('get_series_info', extra: {'series_id': id}));
      final d = r.data is String ? jsonDecode(r.data) : r.data;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (e) {
      debugPrint('[Api.seriesInfo] $e');
    }
    return {};
  }
}

// ── أدوات مساعدة لقراءة حقول Xtream ───────────────────────────
String sName(dynamic m) => (m is Map ? (m['name'] ?? m['title'] ?? '') : '').toString();
String sId(dynamic m) =>
    (m is Map ? (m['stream_id'] ?? m['series_id'] ?? m['id'] ?? '') : '').toString();
String sCat(dynamic m) => (m is Map ? (m['category_id'] ?? '') : '').toString();
String sCatName(dynamic m) => (m is Map ? (m['category_name'] ?? '') : '').toString();
String sLogo(dynamic m) {
  if (m is! Map) return '';
  return (m['stream_icon'] ?? m['cover'] ?? m['movie_image'] ?? m['cover_big'] ?? '')
      .toString();
}
String sExt(dynamic m) {
  final e = (m is Map ? (m['container_extension'] ?? '') : '').toString();
  return e.isEmpty ? 'mp4' : e;
}
