part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  الشبكة: طلبات JSON + قاعدة الاشتراكات (Supabase) + Firestore REST الخفيف
// ════════════════════════════════════════════════════════════════════
class NetResult {
  final int code;
  final dynamic body;
  final String raw;
  NetResult(this.code, this.body, this.raw);
  bool get ok => code >= 200 && code < 300;
}

class Net {
  static Future<NetResult> req(String method, String url,
      {Map<String, String>? headers, Object? body, Duration timeout = const Duration(seconds: 30)}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final r = await client.openUrl(method, Uri.parse(url)).timeout(timeout);
      headers?.forEach(r.headers.set);
      if (body != null) {
        r.headers.contentType = ContentType.json;
        r.add(utf8.encode(body is String ? body : jsonEncode(body)));
      }
      final res = await r.close().timeout(timeout);
      final raw = await res.transform(utf8.decoder).join().timeout(timeout);
      dynamic j;
      try { j = raw.isEmpty ? null : jsonDecode(raw); } catch (_) {}
      return NetResult(res.statusCode, j, raw);
    } finally {
      client.close(force: true);
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  قاعدة الاشتراكات (Supabase) — جلسة محفوظة تتجدد تلقائياً
// ════════════════════════════════════════════════════════════════════
class Supa {
  static const url = 'https://hlmaksidfqdarwunedqj.supabase.co';
  static const key = 'sb_publishable_-lEvqrjoQgkXJdN4lZExxw_1cycMoEj';
  static const _k = 'supa_session_v1';

  static Map<String, dynamic>? _s = Prefs.getJson(_k);
  static final linked = Live<bool>(_s != null);
  static Future<bool>? _refreshing;

  static String get email => _s?.str('email') ?? '';

  static Future<void> login(String email, String password) async {
    final r = await Net.req('POST', '$url/auth/v1/token?grant_type=password',
        headers: {'apikey': key}, body: {'email': email, 'password': password});
    final d = r.body is Map ? Map<String, dynamic>.from(r.body as Map) : <String, dynamic>{};
    if (!r.ok || d['access_token'] == null) {
      final raw = '${d['error_description'] ?? d['msg'] ?? d['message'] ?? d['error'] ?? r.raw}'.toLowerCase();
      if (raw.contains('not confirmed')) throw Exception('حساب قاعدة الاشتراكات غير مُفعّل — Supabase ← Authentication ← Users ← Confirm email');
      if (raw.contains('invalid')) throw Exception('كلمة مرور قاعدة الاشتراكات خاطئة');
      throw Exception('تعذّر ربط قاعدة الاشتراكات (HTTP ${r.code})');
    }
    await _save(d, email);
  }

  static Future<void> _save(Map<String, dynamic> d, [String? email]) async {
    final exp = d['expires_at'] is num
        ? (d['expires_at'] as num).toInt() * 1000
        : DateTime.now().millisecondsSinceEpoch + ((d['expires_in'] as num?)?.toInt() ?? 3600) * 1000;
    _s = {
      'access_token': d['access_token'],
      'refresh_token': d['refresh_token'] ?? _s?['refresh_token'] ?? '',
      'expires_at': exp,
      'email': email ?? _s?['email'] ?? '',
    };
    await Prefs.setJson(_k, _s!);
    linked.value = true;
  }

  static Future<void> logout() async {
    _s = null;
    await Prefs.p.remove(_k);
    linked.value = false;
  }

  /// جلسة أحدث كتبها البوت في الخلفية (عملية منفصلة)؟ نأخذها بدل التجديد مرتين
  static Future<bool> _adoptStored() async {
    try { await Prefs.p.reload(); } catch (_) {}
    final st = Prefs.getJson(_k);
    if (st == null) return false;
    final se = (st['expires_at'] as num?)?.toInt() ?? 0, me = (_s?['expires_at'] as num?)?.toInt() ?? 0;
    if (st['access_token'] != _s?['access_token'] && se > me) { _s = st; linked.value = true; }
    return se - DateTime.now().millisecondsSinceEpoch > 90000;
  }

  static Future<bool> _refresh() {
    return _refreshing ??= () async {
      try {
        if (await _adoptStored()) return true;
        final rt = _s?.str('refresh_token') ?? '';
        if (rt.isEmpty) return false;
        final r = await Net.req('POST', '$url/auth/v1/token?grant_type=refresh_token',
            headers: {'apikey': key}, body: {'refresh_token': rt});
        if (r.ok && r.body is Map && (r.body as Map)['access_token'] != null) {
          await _save(Map<String, dynamic>.from(r.body as Map));
          return true;
        }
        if (r.code == 400 || r.code == 401) {
          if (await _adoptStored()) return true;   // سبقنا البوت بالتجديد
          await logout();
        }
        return false;
      } catch (_) {
        return false; // انقطاع شبكة: نحتفظ بالجلسة ونحاول لاحقاً
      } finally {
        _refreshing = null;
      }
    }();
  }

  static Future<void> _ensure() async {
    if (_s == null) throw Exception('اربط قاعدة الاشتراكات أولاً (المزيد ← الحساب)');
    final exp = (_s!['expires_at'] as num?)?.toInt() ?? 0;
    if (exp - DateTime.now().millisecondsSinceEpoch < 90000) await _refresh();
    if (_s == null) throw Exception('انتهت جلسة قاعدة الاشتراكات — سجّل مرة واحدة من جديد');
  }

  /// استدعاء دالة RPC — يعيد JSON كما هو
  static Future<dynamic> rpc(String fn, [Map<String, dynamic>? params, bool retried = false]) async {
    await _ensure();
    final r = await Net.req('POST', '$url/rest/v1/rpc/$fn',
        headers: {'apikey': key, 'Authorization': 'Bearer ${_s!['access_token']}'}, body: params ?? {});
    if (r.code == 401 && !retried && await _refresh()) return rpc(fn, params, true);
    if (r.code == 401) throw Exception('انتهت جلسة قاعدة الاشتراكات — سجّل من جديد');
    if (r.code == 403) throw Exception('صلاحية ناقصة في قاعدة الاشتراكات');
    if (!r.ok) {
      final m = r.body is Map ? '${(r.body as Map)['message'] ?? (r.body as Map)['hint'] ?? ''}' : '';
      throw Exception(m.isNotEmpty ? m : 'خطأ HTTP ${r.code}');
    }
    return r.body;
  }

  /// RPC يعيد {ok:true,...} — يرمي خطأ مفهوماً إن فشل
  static Future<Map<String, dynamic>> call(String fn, [Map<String, dynamic>? params]) async {
    final r = await rpc(fn, params);
    final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
    if (m['ok'] == false) {
      final e = '${m['error'] ?? 'فشل'}';
      throw Exception(_errAr[e] ?? e);
    }
    return m;
  }

  static const _errAr = {
    'NOT_ADMIN': 'حسابك ليس مشرفاً في قاعدة الاشتراكات',
    'NO_STOCK': 'لا يوجد حساب جاهز في المخزون يغطي هذه المدة',
    'NO_HOST': 'لم تحدد «الهوست الحالي» — من صفحة المخزون',
    'NOT_FOUND': 'غير موجود',
    'MISSING_FIELDS': 'بيانات ناقصة',
    'EMPTY': 'القيمة فارغة',
  };
}

// ════════════════════════════════════════════════════════════════════
//  Firestore REST — قراءة حقول محددة فقط (بدون صور الإيصالات الثقيلة)
// ════════════════════════════════════════════════════════════════════
class FsRest {
  static const _base = 'https://firestore.googleapis.com/v1/projects/$kProjectId/databases/(default)/documents';

  static Future<Map<String, String>> _h() async {
    final t = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (t == null) throw Exception('سجّل الدخول أولاً');
    return {'Authorization': 'Bearer $t'};
  }

  static dynamic val(dynamic v) {
    if (v is! Map) return null;
    if (v.containsKey('stringValue')) return v['stringValue'];
    if (v.containsKey('integerValue')) return int.tryParse('${v['integerValue']}') ?? 0;
    if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
    if (v.containsKey('booleanValue')) return v['booleanValue'] == true;
    if (v.containsKey('timestampValue')) return DateTime.tryParse('${v['timestampValue']}')?.toLocal();
    if (v.containsKey('nullValue')) return null;
    if (v.containsKey('mapValue')) return fields((v['mapValue'] as Map)['fields']);
    if (v.containsKey('arrayValue')) return ((v['arrayValue'] as Map)['values'] as List? ?? []).map(val).toList();
    return null;
  }

  static Map<String, dynamic> fields(dynamic f) {
    final out = <String, dynamic>{};
    if (f is Map) f.forEach((k, v) => out['$k'] = val(v));
    return out;
  }

  /// استعلام بحقول محددة + ترتيب + حد
  static Future<List<Map<String, dynamic>>> query(String collection, {List<String>? select, String? orderBy,
      bool desc = true, int limit = 100, Map<String, dynamic>? whereEq}) async {
    final q = <String, dynamic>{
      'from': [{'collectionId': collection}],
      'limit': limit,
    };
    if (select != null) q['select'] = {'fields': select.map((f) => {'fieldPath': f}).toList()};
    if (orderBy != null) q['orderBy'] = [{'field': {'fieldPath': orderBy}, 'direction': desc ? 'DESCENDING' : 'ASCENDING'}];
    if (whereEq != null && whereEq.isNotEmpty) {
      final filters = whereEq.entries.map((e) => {
        'fieldFilter': {'field': {'fieldPath': e.key}, 'op': 'EQUAL', 'value': _enc(e.value)}
      }).toList();
      q['where'] = filters.length == 1 ? filters.first : {'compositeFilter': {'op': 'AND', 'filters': filters}};
    }
    final r = await Net.req('POST', '$_base:runQuery', headers: await _h(), body: {'structuredQuery': q});
    if (!r.ok) throw Exception(r.code == 403 ? 'permission-denied' : 'Firestore HTTP ${r.code}');
    final out = <Map<String, dynamic>>[];
    for (final row in (r.body as List? ?? [])) {
      final d = (row as Map)['document'];
      if (d is! Map) continue;
      final m = fields(d['fields']);
      m['_id'] = '${d['name']}'.split('/').last;
      out.add(m);
    }
    return out;
  }

  static Map<String, dynamic> _enc(dynamic v) {
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    return {'stringValue': '$v'};
  }

  /// حقول محددة من مستند واحد
  static Future<Map<String, dynamic>> getFields(String path, List<String> mask) async {
    final qs = mask.map((m) => 'mask.fieldPaths=${Uri.encodeQueryComponent(m)}').join('&');
    final r = await Net.req('GET', '$_base/$path?$qs', headers: await _h());
    if (!r.ok) throw Exception('Firestore HTTP ${r.code}');
    return fields((r.body as Map)['fields']);
  }
}

// ════════════════════════════════════════════════════════════════════
//  الذكاء الاصطناعي (Gemini) — المفتاح من app_config/settings.ai_key
// ════════════════════════════════════════════════════════════════════
class AI {
  static String? _key;
  static Future<String> key() async {
    if (_key != null && _key!.isNotEmpty) return _key!;
    final d = await FirebaseFirestore.instance.collection('app_config').doc('settings').get();
    _key = '${d.data()?['ai_key'] ?? ''}'.trim();
    if (_key!.isEmpty) throw Exception('أضف مفتاح Gemini في: المزيد ← التحكم بالتطبيق ← المفاتيح');
    return _key!;
  }

  /// يعيد JSON من Gemini
  static Future<dynamic> json(String prompt, {List<Map<String, dynamic>> extra = const [], String model = 'gemini-2.5-flash'}) async {
    final k = await key();
    final r = await Net.req('POST',
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${Uri.encodeQueryComponent(k)}',
        body: {
          'contents': [{'parts': [{'text': prompt}, ...extra]}],
          'generationConfig': {'temperature': 0.7, 'responseMimeType': 'application/json'},
        }, timeout: const Duration(seconds: 60));
    if (!r.ok) throw Exception('Gemini: ${r.body is Map ? ((r.body as Map)['error']?['message'] ?? r.code) : r.code}');
    final parts = (((r.body as Map)['candidates'] as List?)?.first?['content']?['parts'] as List?) ?? [];
    final txt = parts.map((p) => '${(p as Map)['text'] ?? ''}').join().replaceAll(RegExp(r'^```json\s*|```$'), '');
    return jsonDecode(txt);
  }
}
