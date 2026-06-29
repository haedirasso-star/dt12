import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'ui.dart';

/// مشغّل فيديو خفيف لشاشات التلفاز — تحكّم كامل بالريموت
class PlayerPage extends StatefulWidget {
  final String url;
  final String title;
  final bool isLive;
  const PlayerPage({super.key, required this.url, required this.title, this.isLive = false});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _vc;
  final _focus = FocusNode();
  bool _ready = false, _overlay = true, _err = false;
  String _errMsg = '';

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _vc = c;
      await c.initialize();
      await c.play();
      c.addListener(_tick);
      if (mounted) setState(() => _ready = true);
      _autoHide();
    } catch (e) {
      if (mounted) setState(() { _err = true; _errMsg = 'تعذّر تشغيل المحتوى'; });
    }
  }

  void _tick() { if (mounted) setState(() {}); }

  void _autoHide() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && (_vc?.value.isPlaying ?? false)) setState(() => _overlay = false);
    });
  }

  void _togglePlay() {
    final c = _vc; if (c == null) return;
    setState(() { c.value.isPlaying ? c.pause() : c.play(); _overlay = true; });
    _autoHide();
  }

  void _seek(int s) {
    final c = _vc; if (c == null || widget.isLive) return;
    final pos = c.value.position + Duration(seconds: s);
    final max = c.value.duration;
    c.seekTo(pos < Duration.zero ? Duration.zero : (pos > max ? max : pos));
    setState(() => _overlay = true);
    _autoHide();
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) { _seek(-10); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowRight) { _seek(10); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay(); return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      setState(() => _overlay = true); _autoHide(); return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
      Navigator.pop(context); return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _vc?.removeListener(_tick);
    _vc?.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _vc;
    final pos = c?.value.position ?? Duration.zero;
    final dur = c?.value.duration ?? Duration.zero;
    final prog = dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          onTap: _togglePlay,
          child: Stack(fit: StackFit.expand, children: [
            if (_ready && c != null)
              Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))
            else if (_err)
              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline_rounded, color: K.dim, size: 50),
                const SizedBox(height: 12),
                Text(_errMsg, style: K.ar(s: 16, c: K.sub)),
                const SizedBox(height: 18),
                TvFocus(autofocus: true, onSelect: () => Navigator.pop(context),
                  builder: (f) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                    decoration: BoxDecoration(
                      color: f ? K.gold : K.card, borderRadius: BorderRadius.circular(10)),
                    child: Text('رجوع', style: K.ar(s: 15, w: FontWeight.w800,
                        c: f ? Colors.black : K.text)))),
              ]))
            else
              const Center(child: CircularProgressIndicator(color: K.gold)),

            // طبقة التحكم
            if (_overlay && _ready)
              Positioned(left: 0, right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(30, 40, 30, 26),
                  decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.85)])),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.title, style: K.ar(s: 20, w: FontWeight.w800)),
                    const SizedBox(height: 14),
                    if (!widget.isLive) Row(children: [
                      Text(_fmt(pos), style: K.ar(s: 13, c: K.sub)),
                      const SizedBox(width: 12),
                      Expanded(child: Stack(children: [
                        Container(height: 5, decoration: BoxDecoration(
                          color: Colors.white24, borderRadius: BorderRadius.circular(4))),
                        FractionallySizedBox(widthFactor: prog, child: Container(height: 5,
                          decoration: BoxDecoration(color: K.gold, borderRadius: BorderRadius.circular(4)))),
                      ])),
                      const SizedBox(width: 12),
                      Text(_fmt(dur), style: K.ar(s: 13, c: K.sub)),
                    ]),
                    if (widget.isLive)
                      Row(children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(
                          color: Color(0xFFE53935), shape: BoxShape.circle)),
                        const SizedBox(width: 7),
                        Text('بث مباشر', style: K.ar(s: 13, w: FontWeight.w700, c: const Color(0xFFE53935))),
                      ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Icon(c!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: K.gold, size: 26),
                      const SizedBox(width: 10),
                      Text('OK: تشغيل/إيقاف   ◀ ▶: تقديم/إرجاع   رجوع: خروج',
                          style: K.ar(s: 12, c: K.dim)),
                    ]),
                  ]),
                )),
          ]),
        ),
      ),
    );
  }
}
