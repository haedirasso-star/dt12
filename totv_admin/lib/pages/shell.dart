part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  الهيكل: شريط سفلي (الرئيسية · الطلبات · المخزون · المشتركون · المزيد)
// ════════════════════════════════════════════════════════════════════
class Shell extends StatefulWidget {
  const Shell({super.key});
  static final tab = Live<int>(0);
  static void go(int i) => tab.value = i;
  @override State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  late final Future<void> _boot;
  DateTime _lastBack = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot = _start();
    AdminPush.onOpenOrders = () { Nav.key.currentState?.popUntil((r) => r.isFirst); Shell.go(1); };
    AdminPush.onOpenBot = () { Nav.push(const BotPage()); };
    AdminPush.onOpenChat = (uid) {
      Nav.push(uid.isEmpty ? const ChatsPage() : ChatRoomPage(uid: uid));
    };
  }

  Future<void> _start() async {
    await Store.start();
    unawaited(Subs.loadCached());
    // 🤖 البوت الداخلي: يبدأ مع التطبيق ويستمر في الخلفية
    if (Store.isAdmin) ServerBot.startForeground();
    // 🛟 شبكة أمان للطلبات: فحص خفيف كل 10 دقائق في الخلفية
    if (Store.isAdmin) unawaited(OrderWatch.schedule());
    // الإشعارات بعد ظهور الواجهة — لا تؤخر الفتح
    Future.delayed(const Duration(seconds: 2), () async { await AdminPush.init(); AdminPush.flush(); });
    final e = Prefs.p.getString('supa_login_err');
    if (e != null && !Supa.linked.value) {
      Future.delayed(const Duration(seconds: 1), () => UI.toast('قاعدة الاشتراكات لم تُربط: $e', error: true));
      Prefs.p.remove('supa_login_err');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Store.stop();
    ServerBot.stopForeground();
    AdminPush.onOpenOrders = null;
    AdminPush.onOpenBot = null;
    AdminPush.onOpenChat = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && Store.isAdmin) {
      Prefs.p.reload().then((_) { BotLog.rev.value++; }, onError: (_) {});
      ServerBot.runIfDue(minutes: 10);
    }
  }

  void _back() {
    if (Shell.tab.value != 0) { Shell.go(0); return; }
    final now = DateTime.now();
    if (now.difference(_lastBack).inSeconds < 2) { SystemNavigator.pop(); return; }
    _lastBack = now;
    UI.toast('اضغط رجوع مرة أخرى للخروج');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _boot,
    builder: (_, snap) {
      if (snap.connectionState != ConnectionState.done) return const SplashView();
      if (!Store.isAdmin) return const AgentHome();
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (did, _) { if (!did) _back(); },
        child: ValueListenableBuilder<int>(
          valueListenable: Shell.tab,
          builder: (_, i, __) => Scaffold(
            body: IndexedStack(index: i, children: const [
              HomePage(), OrdersPage(), StockPage(), MembersPage(), MorePage(),
            ]),
            bottomNavigationBar: ValueListenableBuilder<List<AppOrder>>(
              valueListenable: Store.pending,
              builder: (_, p, __) => NavigationBar(
                selectedIndex: i,
                onDestinationSelected: (x) { HapticFeedback.selectionClick(); Shell.go(x); },
                destinations: [
                  const NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'الرئيسية'),
                  NavigationDestination(
                    icon: Badge(isLabelVisible: p.isNotEmpty, label: Text('${p.length}'), backgroundColor: K.red,
                        child: const Icon(Icons.receipt_long_outlined)),
                    selectedIcon: Badge(isLabelVisible: p.isNotEmpty, label: Text('${p.length}'), backgroundColor: K.red,
                        child: const Icon(Icons.receipt_long_rounded)),
                    label: 'الطلبات'),
                  const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded), label: 'المخزون'),
                  const NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt_rounded), label: 'المشتركون'),
                  const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'المزيد'),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class SplashView extends StatelessWidget {
  const SplashView({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Text('T', style: TextStyle(color: K.gold, fontSize: 64, fontWeight: FontWeight.w900)),
    SizedBox(height: 16),
    SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: K.gold)),
  ])));
}

/// عنوان الصفحات الرئيسية
class PageHeader extends StatelessWidget {
  final String title;
  final String? sub;
  final List<Widget> actions;
  const PageHeader(this.title, {super.key, this.sub, this.actions = const []});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 12, 10, 6),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: K.h1),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: K.sub)),
      ])),
      ...actions,
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════
//  «المزيد» — كل الأقسام
// ════════════════════════════════════════════════════════════════════
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  Widget _tile(IconData icon, String title, String sub, Color c, Widget Function() page, {int badge = 0}) => Box(
    padding: const EdgeInsets.all(14),
    onTap: () => Nav.push(page()),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: c.withOpacity(.15), borderRadius: BorderRadius.circular(12)),
          child: Badge(isLabelVisible: badge > 0, label: Text('$badge'), backgroundColor: K.red,
              child: Icon(icon, color: c, size: 22))),
      const SizedBox(height: 12),
      Text(title, style: K.h3.copyWith(fontSize: 14.5)),
      const SizedBox(height: 2),
      Text(sub, maxLines: 2, style: K.tiny),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return ListView(padding: EdgeInsets.zero, children: [
      const PageHeader('المزيد', sub: 'كل أدوات الإدارة'),
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Box(
        child: Row(children: [
          Avatar(email, size: 48),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(email, textDirection: TextDirection.ltr, style: K.h3),
            const SizedBox(height: 4),
            ValueListenableBuilder<bool>(valueListenable: Supa.linked, builder: (_, l, __) => Row(children: [
              const Pill('مشرف', color: K.gold, icon: Icons.verified_rounded),
              const SizedBox(width: 6),
              Pill(l ? 'قاعدة الاشتراكات مربوطة' : 'قاعدة الاشتراكات غير مربوطة',
                  color: l ? K.grn : K.red, icon: l ? Icons.link_rounded : Icons.link_off_rounded),
            ])),
          ])),
        ]),
      )),
      Padding(
        padding: const EdgeInsets.all(16),
        child: KpiGrid(children: [
          ValueListenableBuilder<int>(valueListenable: Engage.unread, builder: (_, n, __) =>
              _tile(Icons.forum_rounded, 'المحادثات', n > 0 ? '$n رسالة غير مقروءة' : 'رسائل المستخدمين والرد عليهم', K.t1,
                  () => const ChatsPage(), badge: n)),
          _tile(Icons.emoji_events_rounded, 'الجوائز والتوقعات', 'الفائزون · الدعوات · النتائج', K.gold, () => const RewardsPage()),
          _tile(Icons.storage_rounded, 'قاعدة المستخدمين', 'تحميل كل المستخدمين وحفظهم على الهاتف', K.cyn, () => const UsersDbPage()),
          _tile(Icons.style_rounded, 'بطاقات المباريات', 'صورة العرض + القناة الموصى بها + أعطال القنوات', K.org, () => const MatchCardsPage()),
          _tile(Icons.sensors_rounded, 'استوديو البث', 'قناة TOTV Live: ابدأ البث · إشعار · بوستر', K.red, () => const StudioPage()),
          _tile(Icons.photo_library_rounded, 'الإعلانات', 'صور المباريات والإعلانات العامة من هاتفك', K.prp, () => const PromosPage()),
          _tile(Icons.campaign_rounded, 'إشعار فوري', 'لكل المستخدمين بأيقونة التطبيق', K.gold, () => const NotifyPage()),
          _tile(Icons.sports_soccer_rounded, 'إشعارات المباريات', 'جدول صافرة البداية + ذكاء اصطناعي', K.grn, () => const MatchesPage()),
          _tile(Icons.key_rounded, 'أكواد التفعيل', 'توليد وإدارة الأكواد', K.blu, () => const CodesPage()),
          _tile(Icons.bolt_rounded, 'تفعيل يدوي', 'بحث عن مستخدم وتفعيله', K.org, () => const ManualActivatePage()),
          _tile(Icons.payments_rounded, 'طرق الدفع والأسعار', 'أرقام التحويل والأسماء', K.cyn, () => const PaymentPage()),
          _tile(Icons.tune_rounded, 'التحكم بالتطبيق', 'صيانة · قفل · إصدار · مفاتيح', K.prp, () => const AppControlPage()),
          _tile(Icons.dns_rounded, 'السيرفرات', 'إضافة وفحص السيرفرات', K.blu, () => const ServersPage()),
          _tile(Icons.badge_rounded, 'الوكلاء', 'الوكلاء والتارجت', K.gold, () => const AgentsPage()),
          _tile(Icons.support_agent_rounded, 'الشكاوى', 'رسائل المستخدمين', K.org, () => const ComplaintsPage()),
          _tile(Icons.smart_toy_rounded, 'مراقب السيرفرات', 'البوت · التنبيهات · السجل والرسوم', K.red, () => const BotPage()),
          _tile(Icons.health_and_safety_rounded, 'فحص النظام', 'الإشعارات والاتصالات والأخطاء', K.grn, () => const SystemCheckPage()),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Box(
        padding: EdgeInsets.zero,
        child: Column(children: [
          ValueListenableBuilder<bool>(valueListenable: Supa.linked, builder: (_, l, __) => ListTile(
            leading: const Icon(Icons.storage_rounded, color: K.gold),
            title: Text(l ? 'إعادة ربط قاعدة الاشتراكات' : 'ربط قاعدة الاشتراكات', style: K.body.copyWith(fontWeight: FontWeight.w800)),
            subtitle: Text(l ? Supa.email : 'مطلوبة للمخزون والأكواد والمشتركين', style: K.tiny),
            onTap: () => linkSupabase(),
          )),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cleaning_services_rounded, color: K.t2),
            title: Text('مسح البيانات المحفوظة', style: K.body.copyWith(fontWeight: FontWeight.w800)),
            subtitle: const Text('يُعاد تحميلها عند الضغط على تحديث', style: K.tiny),
            onTap: () async {
              if (!await UI.confirm('مسح البيانات المحفوظة؟', 'لن يتم تسجيل الخروج. ستُحمَّل البيانات من جديد عند التحديث.')) return;
              await DiskCache.clearAll();
              UI.toast('تم المسح');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: K.red),
            title: Text('تسجيل الخروج', style: K.body.copyWith(fontWeight: FontWeight.w800, color: K.red)),
            onTap: () async {
              if (!await UI.confirm('تسجيل الخروج؟', 'ستحتاج إدخال كلمة المرور من جديد.', ok: 'خروج', danger: true)) return;
              await Supa.logout();
              await FirebaseAuth.instance.signOut();
            },
          ),
        ]),
      )),
      const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('TOTV+ Admin v3.2 — تطبيق أصلي', style: K.tiny))),
    ]);
  }
}

/// ربط/إعادة ربط قاعدة الاشتراكات
Future<void> linkSupabase() async {
  final pass = await UI.input('ربط قاعدة الاشتراكات',
      help: 'اكتب كلمة مرور حسابك في قاعدة الاشتراكات (غالباً نفس كلمة مرور الدخول). تُحفظ الجلسة وتتجدد تلقائياً.',
      hint: 'كلمة المرور', ok: 'ربط');
  if (pass == null || pass.isEmpty) return;
  try {
    await Supa.login(FirebaseAuth.instance.currentUser?.email ?? '', pass);
    UI.toast('تم الربط ✅');
  } catch (e) { UI.err(e); }
}

/// للوكلاء: واجهة مبسطة
class AgentHome extends StatelessWidget {
  const AgentHome({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(padding: EdgeInsets.zero, children: [
      const PageHeader('لوحة الوكيل'),
      Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Banner2('حسابك وكيل. يمكنك تفعيل المشتركين يدوياً. باقي أدوات الإدارة للمشرف فقط.'),
        const SizedBox(height: 16),
        BusyButton(label: 'تفعيل مشترك', icon: Icons.bolt_rounded, onPressed: () async { await Nav.push(const ManualActivatePage()); }),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async { await FirebaseAuth.instance.signOut(); },
          icon: const Icon(Icons.logout_rounded), label: const Text('تسجيل الخروج')),
      ])),
    ]),
  );
}
