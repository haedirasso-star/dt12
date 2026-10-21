part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  الدخول — مرة واحدة فقط. Firebase يحفظ الجلسة على الهاتف للأبد،
//  وقاعدة الاشتراكات تُربط بنفس البريد وتتجدد تلقائياً.
// ════════════════════════════════════════════════════════════════════
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController(text: Prefs.p.getString('last_email') ?? '');
  final _pass = TextEditingController();
  final _spass = TextEditingController();
  bool _busy = false, _show = false, _other = false;
  String _err = '';

  Future<void> _login() async {
    final e = _email.text.trim().toLowerCase(), p = _pass.text;
    if (e.isEmpty || p.isEmpty) { setState(() => _err = 'اكتب البريد وكلمة المرور'); return; }
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _err = ''; });
    try {
      // قاعدة الاشتراكات أولاً (لا تمنع الدخول إن فشلت — تُربط لاحقاً)
      try { await Supa.login(e, _spass.text.isNotEmpty ? _spass.text : p); }
      catch (x) { CrashLog.add('supa login: $x'); Prefs.p.setString('supa_login_err', Fmt.err(x)); }
      await Prefs.p.setString('last_email', e);
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: e, password: p);
    } on FirebaseAuthException catch (x) {
      final c = x.code;
      setState(() => _err = c.contains('invalid') || c.contains('wrong') || c.contains('user-not-found')
          ? 'البريد أو كلمة المرور غير صحيحة'
          : c.contains('network') ? 'لا يوجد اتصال بالإنترنت'
          : c.contains('too-many') ? 'محاولات كثيرة — انتظر قليلاً'
          : (x.message ?? '').contains('API key') || (x.message ?? '').contains('blocked')
              ? 'مفتاح Firebase مرفوض لهذا التطبيق — اضغط «تجربة المفتاح البديل» ثم أعد فتح التطبيق'
              : 'تعذّر الدخول: ${x.message ?? c}');
    } catch (x) {
      setState(() => _err = Fmt.err(x));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: RadialGradient(
        center: Alignment(0, -1.1), radius: 1.2,
        colors: [Color(0x33F5B82E), K.bg])),
      child: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(
            width: 96, height: 96, alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(28),
                border: Border.all(color: K.gold.withOpacity(.45)),
                boxShadow: [BoxShadow(color: K.gold.withOpacity(.18), blurRadius: 40)]),
            child: const Text('T', style: TextStyle(color: K.gold, fontSize: 58, fontWeight: FontWeight.w900)),
          )),
          const SizedBox(height: 18),
          const Center(child: Text('TOTV+ ADMIN', textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4))),
          const SizedBox(height: 6),
          const Center(child: Text('لوحة الإدارة — دخول مرة واحدة ويبقى محفوظاً', style: K.sub)),
          const SizedBox(height: 32),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.alternate_email_rounded))),
          const SizedBox(height: 12),
          TextField(controller: _pass, obscureText: !_show, textDirection: TextDirection.ltr,
              onSubmitted: (_) => _login(),
              decoration: InputDecoration(labelText: 'كلمة المرور', prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    onPressed: () => setState(() => _show = !_show)))),
          const SizedBox(height: 6),
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton(
            onPressed: () => setState(() => _other = !_other),
            child: Text(_other ? 'إخفاء' : 'كلمة مرور قاعدة الاشتراكات مختلفة؟', style: const TextStyle(fontSize: 12.5)))),
          if (_other)
            TextField(controller: _spass, obscureText: true, textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'كلمة مرور Supabase (اختياري)', prefixIcon: Icon(Icons.storage_rounded))),
          if (_err.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_err)],
          const SizedBox(height: 20),
          BusyButton(label: 'دخول', icon: Icons.login_rounded, busy: _busy, onPressed: _login),
          const SizedBox(height: 14),
          Center(child: TextButton(
            onPressed: () async {
              final web = !(Prefs.p.getBool('fb_web_key') ?? false);
              await Prefs.p.setBool('fb_web_key', web);
              UI.toast(web ? 'سيُستخدم مفتاح الويب — أغلق التطبيق وافتحه' : 'سيُستخدم مفتاح أندرويد — أغلق التطبيق وافتحه');
            },
            child: Text('تجربة المفتاح البديل (${Boot.mode})', style: K.tiny),
          )),
        ]),
      ))),
    ),
  );
}
