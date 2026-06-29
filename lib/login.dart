import 'package:flutter/material.dart';
import 'api.dart';
import 'ui.dart';
import 'home.dart';

/// تسجيل دخول بسيط — يوزر/باسوورد فقط، الهوست ثابت، بلا حساب/Firebase
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String _err = '';

  @override
  void dispose() { _user.dispose(); _pass.dispose(); super.dispose(); }

  Future<void> _login() async {
    final u = _user.text.trim(), p = _pass.text.trim();
    if (u.isEmpty || p.isEmpty) { setState(() => _err = 'أدخل اسم المستخدم وكلمة المرور'); return; }
    setState(() { _busy = true; _err = ''; });
    final ok = await Api.validate(u, p);
    if (!ok) {
      setState(() { _busy = false; _err = 'بيانات غير صحيحة أو الاشتراك منتهٍ'; });
      return;
    }
    await Session.save(u, p);
    if (!mounted) return;
    Navigator.pushReplacement(context,
        PageRouteBuilder(pageBuilder: (_, __, ___) => const HomePage(),
            transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // خلفية متدرّجة فخمة
        Container(decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment.center, radius: 1.1,
            colors: [Color(0xFF18130A), K.bg]))),
        Center(
          child: SingleChildScrollView(
            child: Container(
              width: 460,
              padding: const EdgeInsets.all(34),
              decoration: BoxDecoration(
                color: K.bg2.withOpacity(0.85),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: K.gold.withOpacity(0.25)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('TOTV+', style: K.en(s: 40, c: K.gold, ls: 4)),
                const SizedBox(height: 6),
                Text('سجّل الدخول لمشاهدة المحتوى', style: K.ar(s: 14, c: K.sub)),
                const SizedBox(height: 26),
                _field(_user, 'اسم المستخدم', Icons.person_rounded, auto: true),
                const SizedBox(height: 14),
                _field(_pass, 'كلمة المرور', Icons.lock_rounded, obscure: true),
                if (_err.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(_err, style: K.ar(s: 13, c: const Color(0xFFE05050))),
                ],
                const SizedBox(height: 22),
                TvFocus(
                  onSelect: _busy ? () {} : _login,
                  builder: (f) => Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFFD479), K.gold]),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: f ? Colors.white : Colors.transparent, width: 2),
                      boxShadow: f ? [BoxShadow(color: K.gold.withOpacity(0.5), blurRadius: 18)] : null,
                    ),
                    child: Center(child: _busy
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
                        : Text('دخول', style: K.ar(s: 17, w: FontWeight.w900, c: Colors.black))),
                  ),
                ),
                const SizedBox(height: 16),
                Text('الخادم مُعدّ مسبقاً — تحتاج فقط اسم المستخدم وكلمة المرور',
                    textAlign: TextAlign.center, style: K.ar(s: 11, c: K.dim)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {bool obscure = false, bool auto = false}) {
    return Focus(
      child: Builder(builder: (ctx) {
        final f = Focus.of(ctx).hasFocus;
        return Container(
          decoration: BoxDecoration(
            color: K.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: f ? K.gold : Colors.white10, width: 1.6),
          ),
          child: TextField(
            controller: c,
            autofocus: auto,
            obscureText: obscure,
            style: K.ar(s: 16, c: K.text),
            textInputAction: obscure ? TextInputAction.done : TextInputAction.next,
            onSubmitted: (_) { if (obscure) _login(); },
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: K.ar(s: 14, c: K.dim),
              prefixIcon: Icon(icon, color: K.gold, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            ),
          ),
        );
      }),
    );
  }
}
