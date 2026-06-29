import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'api.dart';
import 'ui.dart';
import 'player.dart';

class SeriesDetailPage extends StatefulWidget {
  final dynamic item;
  const SeriesDetailPage({super.key, required this.item});
  @override
  State<SeriesDetailPage> createState() => _SeriesDetailPageState();
}

class _SeriesDetailPageState extends State<SeriesDetailPage> {
  bool _loading = true;
  Map<String, dynamic> _info = {};
  Map<String, List<dynamic>> _seasons = {};
  String _selSeason = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = sId(widget.item);
    final data = await Api.seriesInfo(id);
    final eps = (data['episodes'] is Map) ? Map<String, dynamic>.from(data['episodes']) : {};
    final seasons = <String, List<dynamic>>{};
    eps.forEach((season, list) {
      if (list is List) seasons[season] = list;
    });
    setState(() {
      _info = (data['info'] is Map) ? Map<String, dynamic>.from(data['info']) : {};
      _seasons = seasons;
      _selSeason = seasons.keys.isNotEmpty ? seasons.keys.first : '';
      _loading = false;
    });
  }

  void _playEp(dynamic ep) {
    final id = (ep is Map ? (ep['id'] ?? '') : '').toString();
    final ext = (ep is Map ? (ep['container_extension'] ?? 'mp4') : 'mp4').toString();
    final title = (ep is Map ? (ep['title'] ?? sName(widget.item)) : '').toString();
    final url = Api.streamUrl('series', id, ext);
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => PlayerPage(url: url, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: K.gold)));
    }
    final cover = sLogo(widget.item).isNotEmpty ? sLogo(widget.item) : (_info['cover'] ?? '').toString();
    final plot = (_info['plot'] ?? '').toString();
    final eps = _seasons[_selSeason] ?? [];

    return Scaffold(
      body: Stack(children: [
        if (cover.isNotEmpty)
          Positioned.fill(child: Opacity(opacity: 0.16,
            child: CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox()))),
        Positioned.fill(child: Container(color: K.bg.withOpacity(0.7))),
        SafeArea(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              TvFocus(autofocus: true, scale: 1.1, onSelect: () => Navigator.pop(context),
                builder: (f) => Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: f ? K.gold : K.card, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_back_rounded, color: f ? Colors.black : K.text, size: 22))),
              const SizedBox(width: 14),
              Expanded(child: Text(sName(widget.item),
                  style: K.ar(s: 24, w: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            if (plot.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(plot, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: K.ar(s: 13, c: K.sub, ls: 0)),
            ],
            const SizedBox(height: 18),
            // المواسم
            if (_seasons.length > 1)
              SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal,
                children: _seasons.keys.map((s) {
                  final on = s == _selSeason;
                  return Padding(padding: const EdgeInsets.only(left: 8),
                    child: TvFocus(scale: 1.0, onSelect: () => setState(() => _selSeason = s),
                      builder: (f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: f || on ? K.gold.withOpacity(0.16) : K.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: f || on ? K.gold : Colors.transparent, width: 2)),
                        child: Text('الموسم $s', style: K.ar(s: 13,
                            w: f || on ? FontWeight.w800 : FontWeight.w500,
                            c: f || on ? K.gold : K.sub)))));
                }).toList())),
            const SizedBox(height: 14),
            // الحلقات
            Expanded(child: eps.isEmpty
              ? Center(child: Text('لا توجد حلقات', style: K.ar(s: 15, c: K.sub)))
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240, childAspectRatio: 3.4,
                    crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: eps.length,
                  itemBuilder: (_, i) {
                    final ep = eps[i];
                    final num = (ep is Map ? (ep['episode_num'] ?? (i + 1)) : (i + 1)).toString();
                    final title = (ep is Map ? (ep['title'] ?? 'حلقة $num') : 'حلقة $num').toString();
                    return TvFocus(scale: 1.04, autofocus: i == 0, onSelect: () => _playEp(ep),
                      builder: (f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: f ? K.gold.withOpacity(0.14) : K.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: f ? K.gold : Colors.white10, width: 2)),
                        child: Row(children: [
                          Icon(Icons.play_circle_outline_rounded,
                              color: f ? K.gold : K.sub, size: 22),
                          const SizedBox(width: 10),
                          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: K.ar(s: 13, w: FontWeight.w600, c: f ? K.gold : K.text))),
                        ])));
                  })),
          ]),
        )),
      ]),
    );
  }
}
