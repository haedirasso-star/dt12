import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'api.dart';
import 'ui.dart';
import 'player.dart';
import 'series_detail.dart';
import 'login.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

enum Section { home, movies, series, live, search }

class _HomePageState extends State<HomePage> {
  Section _sec = Section.home;
  bool _loading = true;
  String _backdrop = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Api.loaded) await Api.loadAll();
    _pickBackdrop();
    if (mounted) setState(() => _loading = false);
  }

  void _pickBackdrop() {
    for (final m in Api.movies) {
      final l = sLogo(m);
      if (l.isNotEmpty) { _backdrop = l; break; }
    }
  }

  // تجميع العناصر حسب الفئة
  Map<String, List<dynamic>> _group(List<dynamic> items, List<dynamic> cats) {
    final catName = <String, String>{
      for (final c in cats) (c['category_id']?.toString() ?? ''): (c['category_name'] ?? c['name'] ?? '').toString()
    };
    final out = <String, List<dynamic>>{};
    for (final it in items) {
      final name = catName[sCat(it)] ?? 'أخرى';
      (out[name] ??= []).add(it);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: K.gold)),
      );
    }
    return Scaffold(
      body: Row(children: [
        _sidebar(),
        Expanded(child: _content()),
      ]),
    );
  }

  // ── الشريط الجانبي ──────────────────────────────────────────
  Widget _sidebar() {
    Widget item(Section s, IconData ic, String label) {
      final on = _sec == s;
      return TvFocus(
        scale: 1.0,
        onSelect: () => setState(() => _sec = s),
        builder: (f) => Container(
          width: 168,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: f ? K.gold.withOpacity(0.16) : (on ? Colors.white10 : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: f ? K.gold : Colors.transparent, width: 2),
          ),
          child: Row(children: [
            Icon(ic, color: f || on ? K.gold : K.sub, size: 22),
            const SizedBox(width: 12),
            Text(label, style: K.ar(s: 15, w: f || on ? FontWeight.w800 : FontWeight.w500,
                c: f || on ? K.gold : K.sub)),
          ]),
        ),
      );
    }

    return Container(
      width: 190,
      color: K.bg2,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Text('TOTV+', style: K.en(s: 24, c: K.gold, ls: 2))),
          item(Section.home, Icons.home_rounded, 'الرئيسية'),
          item(Section.movies, Icons.movie_rounded, 'أفلام'),
          item(Section.series, Icons.live_tv_rounded, 'مسلسلات'),
          item(Section.live, Icons.podcasts_rounded, 'البث المباشر'),
          item(Section.search, Icons.search_rounded, 'بحث'),
          const Spacer(),
          TvFocus(
            scale: 1.0,
            onSelect: () async {
              await Session.logout();
              if (mounted) {
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LoginPage()));
              }
            },
            builder: (f) => Container(
              width: 168,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: f ? const Color(0xFFE53935).withOpacity(0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: f ? const Color(0xFFE53935) : Colors.transparent, width: 2),
              ),
              child: Row(children: [
                Icon(Icons.logout_rounded, color: f ? const Color(0xFFE53935) : K.sub, size: 22),
                const SizedBox(width: 12),
                Text('خروج', style: K.ar(s: 15, w: f ? FontWeight.w800 : FontWeight.w500,
                    c: f ? const Color(0xFFE53935) : K.sub)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  // ── المحتوى حسب القسم ───────────────────────────────────────
  Widget _content() {
    switch (_sec) {
      case Section.movies:
        return _rails(_group(Api.movies, Api.movieCats), 'movie');
      case Section.series:
        return _rails(_group(Api.series, Api.seriesCats), 'series');
      case Section.live:
        return _rails(_group(Api.live, Api.liveCats), 'live');
      case Section.search:
        return SearchView(onPlay: _open);
      case Section.home:
        return _homeView();
    }
  }

  Widget _homeView() {
    // الرئيسية: مزيج — أحدث الأفلام + المسلسلات + المباشر
    final rails = <String, List<dynamic>>{
      '🎬 أفلام مختارة': Api.movies.take(20).toList(),
      '📺 مسلسلات': Api.series.take(20).toList(),
      '🔴 قنوات مباشرة': Api.live.take(20).toList(),
    };
    return Stack(children: [
      // خلفية بوستر فخمة
      if (_backdrop.isNotEmpty)
        Positioned.fill(child: Opacity(opacity: 0.18,
          child: CachedNetworkImage(imageUrl: _backdrop, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox()))),
      Positioned.fill(child: Container(decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
          colors: [K.bg, K.bg.withOpacity(0.6)])))),
      _railsList(rails, mixedType: true),
    ]);
  }

  Widget _rails(Map<String, List<dynamic>> groups, String type) {
    if (groups.isEmpty) {
      return Center(child: Text('لا يوجد محتوى', style: K.ar(s: 16, c: K.sub)));
    }
    return _railsList(groups, forcedType: type);
  }

  Widget _railsList(Map<String, List<dynamic>> groups, {String? forcedType, bool mixedType = false}) {
    final entries = groups.entries.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
      itemCount: entries.length,
      itemBuilder: (_, ri) {
        final e = entries[ri];
        final type = forcedType ?? _guessType(e.key);
        final isLive = type == 'live';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(bottom: 10, top: 6),
            child: Text(e.key, style: K.ar(s: 18, w: FontWeight.w800))),
          SizedBox(
            height: isLive ? 150 : 250,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: e.value.length,
              itemBuilder: (_, i) {
                final it = e.value[i];
                final auto = ri == 0 && i == 0;
                if (isLive) {
                  return LiveCard(title: sName(it), logo: sLogo(it), autofocus: auto,
                      onSelect: () => _open(it, 'live'));
                }
                final t = mixedType ? _typeOf(it) : type;
                return PosterCard(title: sName(it), logo: sLogo(it), autofocus: auto,
                    onSelect: () => _open(it, t));
              },
            ),
          ),
          const SizedBox(height: 12),
        ]);
      },
    );
  }

  String _guessType(String railKey) {
    if (railKey.contains('مباشر') || railKey.contains('🔴')) return 'live';
    if (railKey.contains('مسلسل') || railKey.contains('📺')) return 'series';
    return 'movie';
  }

  String _typeOf(dynamic it) {
    if (it is Map && it['series_id'] != null) return 'series';
    if (it is Map && (it['stream_type'] == 'live')) return 'live';
    return 'movie';
  }

  void _open(dynamic item, String type) {
    if (type == 'series') {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => SeriesDetailPage(item: item)));
    } else {
      final url = Api.streamUrl(type == 'live' ? 'live' : 'movie', sId(item), sExt(item));
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => PlayerPage(url: url, title: sName(item), isLive: type == 'live')));
    }
  }
}

/// ── البحث ─────────────────────────────────────────────────────
class SearchView extends StatefulWidget {
  final void Function(dynamic, String) onPlay;
  const SearchView({super.key, required this.onPlay});
  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _c = TextEditingController();
  String _q = '';

  List<MapEntry<dynamic, String>> get _results {
    if (_q.length < 2) return [];
    final q = _q.toLowerCase();
    final out = <MapEntry<dynamic, String>>[];
    for (final m in Api.movies) {
      if (sName(m).toLowerCase().contains(q)) out.add(MapEntry(m, 'movie'));
      if (out.length > 60) break;
    }
    for (final s in Api.series) {
      if (sName(s).toLowerCase().contains(q)) out.add(MapEntry(s, 'series'));
      if (out.length > 90) break;
    }
    for (final l in Api.live) {
      if (sName(l).toLowerCase().contains(q)) out.add(MapEntry(l, 'live'));
      if (out.length > 120) break;
    }
    return out;
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final res = _results;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: BoxDecoration(color: K.card, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: K.gold.withOpacity(0.4))),
          child: TextField(
            controller: _c,
            autofocus: true,
            style: K.ar(s: 16),
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: InputDecoration(
              hintText: 'ابحث عن فيلم أو مسلسل أو قناة…',
              hintStyle: K.ar(s: 14, c: K.dim),
              prefixIcon: const Icon(Icons.search_rounded, color: K.gold),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: res.isEmpty
          ? Center(child: Text(_q.length < 2 ? 'اكتب للبحث' : 'لا نتائج', style: K.ar(s: 15, c: K.sub)))
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170, childAspectRatio: 0.62,
                crossAxisSpacing: 4, mainAxisSpacing: 14),
              itemCount: res.length,
              itemBuilder: (_, i) {
                final e = res[i];
                return PosterCard(title: sName(e.key), logo: sLogo(e.key), autofocus: i == 0,
                    onSelect: () => widget.onPlay(e.key, e.value));
              },
            )),
      ]),
    );
  }
}
