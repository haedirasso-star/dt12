import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api.dart';
import 'ui.dart';
import 'login.dart';
import 'home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const TotvTvApp());
}

class TotvTvApp extends StatelessWidget {
  const TotvTvApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TOTV+',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: K.bg,
          colorScheme: const ColorScheme.dark(primary: K.gold, surface: K.bg2),
          useMaterial3: true,
        ),
        home: const _Intro(),
      );
}

/// ════════════════════════════════════════════════════════════════
///  انترو فخم — حرف T أولاً ثم OTV+ (نفس طابع التطبيق الأساسي)
/// ════════════════════════════════════════════════════════════════
class _Intro extends StatefulWidget {
  const _Intro();
  @override
  State<_Intro> createState() => _IntroState();
}

class _IntroState extends State<_Intro> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _tFade, _tScale, _restFade, _restSlide, _glow, _sweep, _subFade, _out;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))..forward();
    Sfx.intro();
    _tFade = CurvedAnimation(parent: _c, curve: const Interval(0.04, 0.18, curve: Curves.easeOut));
    _tScale = Tween(begin: 1.7, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: const Interval(0.04, 0.30, curve: Curves.easeOutCubic)));
    _restFade = CurvedAnimation(parent: _c, curve: const Interval(0.20, 0.36, curve: Curves.easeOut));
    _restSlide = Tween(begin: -0.35, end: 0.0)
        .animate(CurvedAnimation(parent: _c, curve: const Interval(0.20, 0.40, curve: Curves.easeOutBack)));
    _glow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 18),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.5), weight: 82),
    ]).animate(CurvedAnimation(parent: _c, curve: const Interval(0.36, 1.0)));
    _sweep = Tween(begin: -1.5, end: 2.5)
        .animate(CurvedAnimation(parent: _c, curve: const Interval(0.40, 0.72, curve: Curves.easeInOut)));
    _subFade = CurvedAnimation(parent: _c, curve: const Interval(0.45, 0.62, curve: Curves.easeOut));
    _out = Tween(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _c, curve: const Interval(0.90, 1.0, curve: Curves.easeIn)));

    _boot();
  }

  Future<void> _boot() async {
    await Session.load();
    await Future.delayed(const Duration(milliseconds: 3300));
    if (!mounted) return;
    final next = Session.isLoggedIn ? const HomePage() : const LoginPage();
    Navigator.pushReplacement(context,
        PageRouteBuilder(pageBuilder: (_, __, ___) => next,
            transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
            transitionDuration: const Duration(milliseconds: 400)));
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.cinzelDecorative(
        fontSize: 72, fontWeight: FontWeight.w900, color: K.text, letterSpacing: 6);
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Opacity(
          opacity: _out.value,
          child: Center(
            child: ShaderMask(
              shaderCallback: (b) => LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: const [K.goldDim, K.gold, Color(0xFFFFF3C4), K.gold, K.goldDim],
                stops: [
                  (_sweep.value - 0.30).clamp(0.0, 1.0),
                  (_sweep.value - 0.12).clamp(0.0, 1.0),
                  _sweep.value.clamp(0.0, 1.0),
                  (_sweep.value + 0.12).clamp(0.0, 1.0),
                  (_sweep.value + 0.30).clamp(0.0, 1.0),
                ],
              ).createShader(b),
              blendMode: BlendMode.srcIn,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  decoration: BoxDecoration(boxShadow: [
                    BoxShadow(color: K.gold.withOpacity(0.5 * _glow.value),
                        blurRadius: 70 * _glow.value, spreadRadius: 10 * _glow.value),
                  ]),
                  child: Row(mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Opacity(opacity: _tFade.value,
                        child: Transform.scale(scale: _tScale.value, alignment: Alignment.bottomCenter,
                          child: Text('T', style: style.copyWith(fontSize: 86)))),
                      Opacity(opacity: _restFade.value,
                        child: Transform.translate(offset: Offset(_restSlide.value * 40, 0),
                          child: Text('OTV+', style: style))),
                    ]),
                ),
                const SizedBox(height: 14),
                Opacity(opacity: _subFade.value,
                  child: Text('منصة البث الذكية',
                      style: GoogleFonts.cairo(fontSize: 16, color: K.dim, letterSpacing: 4))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
