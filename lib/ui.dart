import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';

/// ════════════════════════════════════════════════════════════════
///  هوية بصرية خفيفة + أدوات تنقّل بالريموت (D-pad)
/// ════════════════════════════════════════════════════════════════
class K {
  static const bg     = Color(0xFF0A0A0C);
  static const bg2    = Color(0xFF121216);
  static const card   = Color(0xFF1A1A20);
  static const gold   = Color(0xFFF5A623);
  static const goldDim= Color(0xFFB07A18);
  static const text   = Color(0xFFF5F5F7);
  static const sub    = Color(0xFF9A9AA6);
  static const dim    = Color(0xFF5A5A66);

  static TextStyle ar({double s = 16, FontWeight w = FontWeight.w500, Color c = text, double? ls}) =>
      GoogleFonts.cairo(fontSize: s, fontWeight: w, color: c, letterSpacing: ls);
  static TextStyle en({double s = 16, FontWeight w = FontWeight.w700, Color c = text, double? ls}) =>
      GoogleFonts.cinzel(fontSize: s, fontWeight: w, color: c, letterSpacing: ls);
}

class Sfx {
  static final _p = AudioPlayer();
  static bool on = true;
  static Future<void> _play(String a, {double v = 1}) async {
    if (!on) return;
    try {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.release);
      await p.setVolume(v);
      await p.play(AssetSource('sounds/$a'));
      p.onPlayerComplete.listen((_) { try { p.dispose(); } catch (_) {} });
    } catch (_) {}
  }
  static void intro() => _play('intro.wav', v: 0.9);
  static void tap()   => _play('tap.wav', v: 0.4);
}

/// عنصر قابل للتركيز بالريموت — يكبر ويُضيء عند التركيز، ويُفعّل بزر OK
class TvFocus extends StatefulWidget {
  final Widget Function(bool focused) builder;
  final VoidCallback onSelect;
  final bool autofocus;
  final double scale;
  const TvFocus({
    super.key,
    required this.builder,
    required this.onSelect,
    this.autofocus = false,
    this.scale = 1.08,
  });
  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: (v) => setState(() => _f = v),
      onFocusChange: (v) { if (v) Sfx.tap(); },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) { widget.onSelect(); return null; }),
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _f ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: widget.builder(_f),
        ),
      ),
    );
  }
}

/// بطاقة بوستر (فيلم/مسلسل) قابلة للتركيز
class PosterCard extends StatelessWidget {
  final String title;
  final String logo;
  final VoidCallback onSelect;
  final bool autofocus;
  final double w, h;
  const PosterCard({
    super.key,
    required this.title,
    required this.logo,
    required this.onSelect,
    this.autofocus = false,
    this.w = 150,
    this.h = 220,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (f) => Container(
        width: w,
        margin: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: f ? K.gold : Colors.transparent, width: 2.5),
          boxShadow: f
              ? [BoxShadow(color: K.gold.withOpacity(0.4), blurRadius: 22, spreadRadius: 1)]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: h,
              width: w,
              child: logo.isEmpty
                  ? _ph()
                  : CachedNetworkImage(
                      imageUrl: logo,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _ph(),
                      errorWidget: (_, __, ___) => _ph()),
            ),
            Container(
              width: w,
              color: f ? K.gold.withOpacity(0.14) : K.card,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: K.ar(s: 12.5, w: FontWeight.w600, c: f ? K.gold : K.text)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _ph() => Container(
        color: K.card,
        child: const Center(child: Icon(Icons.movie_outlined, color: K.dim, size: 34)),
      );
}

/// بطاقة قناة مباشرة (شعار مربّع)
class LiveCard extends StatelessWidget {
  final String title;
  final String logo;
  final VoidCallback onSelect;
  final bool autofocus;
  const LiveCard({
    super.key,
    required this.title,
    required this.logo,
    required this.onSelect,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (f) => Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: f ? K.gold.withOpacity(0.12) : K.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: f ? K.gold : Colors.white10, width: 2),
        ),
        child: Column(children: [
          SizedBox(
            height: 78,
            child: logo.isEmpty
                ? const Icon(Icons.live_tv_rounded, color: K.dim, size: 38)
                : CachedNetworkImage(
                    imageUrl: logo,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.live_tv_rounded, color: K.dim, size: 38)),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: K.ar(s: 12, w: FontWeight.w600, c: f ? K.gold : K.text)),
        ]),
      ),
    );
  }
}
