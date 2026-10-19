part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  طلبات الاشتراك — المنتظرة مباشرة (Live) + السجل عند الطلب
// ════════════════════════════════════════════════════════════════════
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with AutomaticKeepAliveClientMixin {
  String _f = 'pending';
  final _q = TextEditingController();
  bool _busy = false;

  @override bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try { await Store.loadHistory(); HapticFeedback.lightImpact(); } catch (e) { UI.err(e); }
    if (mounted) setState(() => _busy = false);
  }

  List<AppOrder> _list(List<AppOrder> pending, List<AppOrder> hist) {
    final ids = pending.map((o) => o.id).toSet();
    final all = [...pending, ...hist.where((o) => !ids.contains(o.id))];
    final q = _q.text.trim().toLowerCase();
    return all.where((o) {
      if (_f != 'all' && o.status != _f) return false;
      if (q.isEmpty) return true;
      return '${o.name} ${o.email} ${o.phone} ${o.orderId} ${o.method} ${o.uid}'.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => (b.created ?? DateTime(2000)).compareTo(a.created ?? DateTime(2000)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<List<AppOrder>>(
      valueListenable: Store.pending,
      builder: (_, pending, __) => ValueListenableBuilder<List<AppOrder>>(
        valueListenable: Store.history,
        builder: (_, hist, __) {
          final list = _list(pending, hist);
          final dupes = <String, int>{};
          for (final o in [...pending, ...hist]) {
            final h = o.raw.str('receipt_hash');
            if (h.isNotEmpty) dupes[h] = (dupes[h] ?? 0) + 1;
          }
          return RefreshIndicator(
            color: K.gold, backgroundColor: K.card,
            onRefresh: _refresh,
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: PageHeader('الطلبات',
                  sub: Store.historyAt == null ? 'المنتظرة تصل مباشرة · السجل عند التحديث' : 'السجل محدَّث ${Fmt.ago(Store.historyAt)}',
                  actions: [IconButton(
                    onPressed: _busy ? null : _refresh,
                    icon: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: K.gold))
                                : const Icon(Icons.refresh_rounded, size: 28))])),
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: _stats(pending, hist))),
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: SearchBox(controller: _q, hint: 'بحث بالاسم أو البريد أو الهاتف أو رقم الطلب', onChanged: (_) => setState(() {})))),
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Filters<String>(
                value: _f, onChanged: (v) => setState(() => _f = v),
                items: [
                  ('pending', 'بانتظارك', pending.length),
                  ('approved', 'مفعّلة', null),
                  ('rejected', 'مرفوضة', null),
                  ('all', 'الكل', null),
                ]))),
              if (!Store.pendingReady.value && _f == 'pending')
                const SliverToBoxAdapter(child: Loading(text: 'جاري الاتصال بالطلبات المباشرة...'))
              else if (list.isEmpty)
                SliverToBoxAdapter(child: EmptyView(
                  icon: _f == 'pending' ? Icons.celebration_rounded : Icons.inbox_rounded,
                  title: _f == 'pending' ? 'لا طلبات بانتظارك' : 'لا طلبات هنا',
                  sub: _f == 'pending' ? 'سيصلك إشعار بصوت الكاش فور وصول أي طلب' : (hist.isEmpty ? 'اسحب للأسفل لتحميل السجل' : null)))
              else
                SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final o = list[i];
                    final c = o.created;
                    final prev = i == 0 ? null : list[i - 1].created;
                    final newDay = c == null ? i == 0 : (prev == null || prev.day != c.day || prev.month != c.month || prev.year != c.year);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (newDay) _DayHeader(c, list.where((x) {
                          final d = x.created;
                          return c == null ? d == null : (d != null && d.day == c.day && d.month == c.month && d.year == c.year);
                        }).length),
                        OrderCard(o, dup: (dupes[o.raw.str('receipt_hash')] ?? 0) > 1),
                      ]),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ]),
          );
        },
      ),
    );
  }

  Widget _stats(List<AppOrder> pending, List<AppOrder> hist) {
    final now = DateTime.now();
    final all = [...pending, ...hist];
    final today = all.where((o) { final c = o.created; return c != null && c.year == now.year && c.month == now.month && c.day == now.day; }).length;
    final week = all.where((o) { final c = o.created; return c != null && now.difference(c).inDays < 7; }).length;
    final ok30 = hist.where((o) { final c = o.created; return o.status == 'approved' && c != null && now.difference(c).inDays < 30; }).toList();
    final rev = ok30.fold<int>(0, (s, o) => s + o.amount);
    final resp = ok30.map((o) { final a = o.created, b = o.resolved; return a != null && b != null ? b.difference(a).inSeconds : -1; })
        .where((x) => x > 0).toList()..sort();
    final median = resp.isEmpty ? 0 : resp[resp.length ~/ 2];
    return KpiGrid(children: [
      Kpi(label: 'طلبات اليوم', value: '$today', icon: Icons.today_rounded, color: K.blu, hint: 'آخر 7 أيام: $week'),
      Kpi(label: 'إيراد 30 يوماً (د.ع)', value: Fmt.n(rev), icon: Icons.payments_rounded, color: K.grn,
          hint: median > 0 ? 'متوسط وقت التفعيل ${Fmt.dur(median)}' : '${ok30.length} طلب مفعّل'),
    ]);
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime? d;
  final int count;
  const _DayHeader(this.d, this.count);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
    child: Row(children: [
      Text(d == null ? 'بدون تاريخ' : Fmt.dayLabel(d!), style: K.h3),
      const SizedBox(width: 10),
      const Expanded(child: Divider()),
      const SizedBox(width: 10),
      Pill('$count', color: K.t2),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════
//  بطاقة الطلب
// ════════════════════════════════════════════════════════════════════
class OrderCard extends StatelessWidget {
  final AppOrder o;
  final bool dup;
  const OrderCard(this.o, {super.key, this.dup = false});

  Color get _c => o.pending ? K.gold : (o.status == 'approved' ? K.grn : K.red);

  @override
  Widget build(BuildContext context) {
    final sub = Subs.of(o.uid, o.email);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Box(
        padding: EdgeInsets.zero,
        border: _c.withOpacity(o.pending ? .45 : .2),
        onTap: () => Nav.push(OrderDetailPage(o)),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, decoration: BoxDecoration(color: _c,
              borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(18)).resolve(Directionality.of(context)))),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Avatar(o.name),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: K.h3),
                  if (o.email.isNotEmpty) Text(o.email, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: K.tiny),
                  const SizedBox(height: 3),
                  Text('${Fmt.time(o.created)} · ${Fmt.ago(o.created)}', style: K.tiny.copyWith(color: K.t2)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (o.amount > 0) Text(Fmt.n(o.amount), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: K.gold2)),
                  if (o.amount > 0) const Text('د.ع', style: K.tiny),
                ]),
                if (o.hasReceipt) ...[const SizedBox(width: 10), ReceiptThumb(o, size: 58)],
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill('${o.planTitle} · ${o.days} يوم', color: K.blu, icon: Icons.inventory_2_rounded),
                if (o.method.isNotEmpty) Pill(o.method, color: K.prp, icon: Icons.account_balance_wallet_rounded),
                if (o.phone.isNotEmpty) Pill(o.phone, color: K.t2, icon: Icons.phone_rounded),
                if (sub != null) Pill(sub.active ? 'مشترك (${sub.daysLeft} يوم)' : 'اشتراكه منتهٍ',
                    color: sub.active ? K.grn : K.org, icon: Icons.workspace_premium_rounded),
                if (dup) const Pill('إيصال مكرّر!', color: K.red, icon: Icons.warning_rounded),
                if (o.src == 'req') const Pill('طلب قديم', color: K.t3),
              ]),
              const SizedBox(height: 12),
              _Steps(o),
              if (o.status == 'rejected' && o.raw.str('rejection_reason').isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('سبب الرفض: ${o.raw.str('rejection_reason')}', style: K.sub.copyWith(color: K.red))),
              if (o.pending) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: SizedBox(height: 46, child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                    onPressed: () => approveOrder(o),
                    icon: const Icon(Icons.bolt_rounded, size: 20),
                    label: const Text('قبول وتفعيل')))),
                  const SizedBox(width: 8),
                  _icon(Icons.close_rounded, K.red, 'رفض', () => rejectOrder(o)),
                  const SizedBox(width: 8),
                  _icon(Icons.more_horiz_rounded, K.t1, 'المزيد', () => orderMenu(o)),
                ]),
              ],
            ]),
          )),
        ])),
      ),
    );
  }

  Widget _icon(IconData i, Color c, String tip, VoidCallback f) => Material(
    color: K.card2, borderRadius: BorderRadius.circular(14),
    child: InkWell(borderRadius: BorderRadius.circular(14), onTap: f,
        child: SizedBox(width: 46, height: 46, child: Tooltip(message: tip, child: Icon(i, color: c)))),
  );
}

/// مراحل الطلب: استلام ← مراجعة ← تفعيل
class _Steps extends StatelessWidget {
  final AppOrder o;
  const _Steps(this.o);
  @override
  Widget build(BuildContext context) {
    final s = o.status;
    final a = o.created, b = o.resolved;
    final took = a != null && b != null ? ' بعد ${Fmt.dur(b.difference(a).inSeconds)}' : '';
    Widget dot(Color c, String t, {bool ring = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle,
          boxShadow: ring ? [BoxShadow(color: c.withOpacity(.4), blurRadius: 0, spreadRadius: 3)] : null)),
      const SizedBox(width: 5),
      Text(t, style: TextStyle(fontSize: 11, color: c == K.line ? K.t3 : K.t2, fontWeight: FontWeight.w700)),
    ]);
    Widget ln(bool on) => Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 6), color: on ? K.grn : K.line));
    return Row(children: [
      dot(K.grn, 'استلام'),
      ln(s != 'pending'),
      s == 'pending' ? dot(K.gold, 'بانتظار المراجعة', ring: true) : (s == 'approved' ? dot(K.grn, 'مراجَع') : dot(K.red, 'مرفوض')),
      ln(s == 'approved'),
      dot(s == 'approved' ? K.grn : K.line, s == 'approved' ? 'مفعّل$took' : 'تفعيل'),
    ]);
  }
}

class ReceiptThumb extends StatelessWidget {
  final AppOrder o;
  final double size;
  const ReceiptThumb(this.o, {super.key, this.size = 58});
  @override
  Widget build(BuildContext context) {
    final cached = Store.receipts[o.id];
    final url = o.receiptUrl;
    Widget img;
    if (cached != null) {
      img = Image.memory(cached, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (url.isNotEmpty) {
      img = Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: K.t3));
    } else if (o.pending) {
      img = FutureBuilder<Uint8List?>(
        future: Store.receipt(o),
        builder: (_, s) => s.data != null ? Image.memory(s.data!, fit: BoxFit.cover)
            : (s.connectionState == ConnectionState.done ? const Icon(Icons.image_not_supported_rounded, color: K.t3)
                : const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: K.gold)))),
      );
    } else {
      img = const Icon(Icons.receipt_rounded, color: K.gold);
    }
    return GestureDetector(
      onTap: () => Nav.push(ReceiptView(o)),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Container(
        width: size, height: size, color: K.card2, child: img)),
    );
  }
}

class ReceiptView extends StatelessWidget {
  final AppOrder o;
  const ReceiptView(this.o, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, title: Text('إيصال ${o.name}')),
    body: Center(child: o.receiptUrl.isNotEmpty && Store.receipts[o.id] == null
        ? InteractiveViewer(maxScale: 6, child: Image.network(o.receiptUrl))
        : FutureBuilder<Uint8List?>(
            future: Store.receipt(o),
            builder: (_, s) => s.connectionState != ConnectionState.done
                ? const Loading(text: 'جاري تحميل الإيصال...')
                : s.data == null ? const EmptyView(icon: Icons.image_not_supported_rounded, title: 'لا توجد صورة')
                    : InteractiveViewer(maxScale: 6, child: Image.memory(s.data!)))),
  );
}

// ════════════════════════════════════════════════════════════════════
//  الإجراءات
// ════════════════════════════════════════════════════════════════════
Future<void> approveOrder(AppOrder o) async {
  if (o.uid.isEmpty || o.uid == 'guest') {
    UI.toast('الطلب من ضيف بلا حساب — اطلب منه تسجيل الدخول في التطبيق', error: true);
    return;
  }
  final choice = await UI.pick<String>('طريقة التفعيل', [
    ('auto', 'تلقائي من المخزون (موصى به)', Icons.auto_awesome_rounded),
    ('manual', 'يدوي — أكتب بيانات السيرفر بنفسي', Icons.edit_rounded),
  ]);
  if (choice == 'auto') {
    await AutoActivateSheet.open(uid: o.uid, email: o.email, name: o.name, days: o.days, order: o);
  } else if (choice == 'manual') {
    await Nav.push(ManualActivatePage(order: o));
  }
}

Future<void> rejectOrder(AppOrder o) async {
  final reason = await UI.input('رفض طلب ${o.name}', hint: 'سبب الرفض (اختياري)', ok: 'رفض الطلب',
      help: 'مثال: الإيصال غير واضح، المبلغ غير مطابق…');
  if (reason == null) return;
  try { await Store.reject(o, reason); UI.toast('تم رفض الطلب'); } catch (e) { UI.err(e); }
}

Future<void> orderMenu(AppOrder o) async {
  final a = await UI.pick<String>(o.name, [
    if (o.phone.isNotEmpty) ('wa', 'مراسلة واتساب', Icons.chat_rounded),
    if (o.phone.isNotEmpty) ('phone', 'نسخ الرقم', Icons.copy_rounded),
    ('member', 'ملف المشترك الكامل', Icons.person_rounded),
    ('manual', 'تفعيل يدوي', Icons.edit_rounded),
    ('id', 'نسخ رقم الطلب', Icons.tag_rounded),
  ]);
  switch (a) {
    case 'wa': await UI.whatsapp(o.phone, text: 'مرحباً ${o.name} 👋\nبخصوص طلب اشتراكك في TOTV+'); break;
    case 'phone': await UI.copy(o.phone); break;
    case 'member': await Nav.push(MemberPage(uid: o.uid, email: o.email)); break;
    case 'manual': await Nav.push(ManualActivatePage(order: o)); break;
    case 'id': await UI.copy(o.orderId); break;
  }
}

class OrderDetailPage extends StatelessWidget {
  final AppOrder o;
  const OrderDetailPage(this.o, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تفاصيل الطلب'), actions: [
      IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () => orderMenu(o)),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Avatar(o.name, size: 56),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(o.name, style: K.h2),
          Text(o.email, textDirection: TextDirection.ltr, style: K.sub),
        ])),
        Pill(o.pending ? 'بانتظار المراجعة' : (o.status == 'approved' ? 'مفعّل' : 'مرفوض'),
            color: o.pending ? K.gold : (o.status == 'approved' ? K.grn : K.red)),
      ]),
      const SizedBox(height: 16),
      if (o.hasReceipt) GestureDetector(
        onTap: () => Nav.push(ReceiptView(o)),
        child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Container(
          height: 300, color: K.card,
          child: o.receiptUrl.isNotEmpty && Store.receipts[o.id] == null
              ? Image.network(o.receiptUrl, fit: BoxFit.contain)
              : FutureBuilder<Uint8List?>(future: Store.receipt(o), builder: (_, s) => s.data != null
                  ? Image.memory(s.data!, fit: BoxFit.contain)
                  : s.connectionState == ConnectionState.done ? const EmptyView(icon: Icons.image_not_supported_rounded, title: 'لا توجد صورة')
                      : const Loading())),
        )),
      const SizedBox(height: 14),
      Box(child: Column(children: [
        InfoRow('رقم الطلب', o.orderId, copy: true, ltr: true),
        InfoRow('الباقة', '${o.planTitle} — ${o.days} يوم'),
        InfoRow('المبلغ', o.amount > 0 ? '${Fmt.n(o.amount)} د.ع' : '—', color: K.gold2),
        InfoRow('طريقة الدفع', o.method),
        if (o.raw.str('method_number').isNotEmpty) InfoRow('حُوّل إلى', o.raw.str('method_number'), copy: true, ltr: true),
        InfoRow('الهاتف', o.phone, copy: true, ltr: true),
        InfoRow('وقت الطلب', Fmt.dt(o.created)),
        if (!o.pending) InfoRow('وقت المعالجة', Fmt.dt(o.resolved)),
        if (o.by.isNotEmpty) InfoRow('بواسطة', o.by, ltr: true),
        if (o.raw.str('asia_card_code').isNotEmpty) InfoRow('كود الكرت', o.raw.str('asia_card_code'), copy: true, ltr: true),
        InfoRow('UID', o.uid, copy: true, ltr: true),
      ])),
      if (o.raw.str('note').isNotEmpty) ...[const SizedBox(height: 10), Banner2(o.raw.str('note'), icon: Icons.sticky_note_2_rounded)],
    ]),
    bottomNavigationBar: o.pending ? BottomAction(child: Row(children: [
      Expanded(child: SizedBox(height: 52, child: FilledButton.icon(
        onPressed: () => approveOrder(o), icon: const Icon(Icons.bolt_rounded), label: const Text('قبول وتفعيل')))),
      const SizedBox(width: 10),
      SizedBox(height: 52, child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: K.red, side: const BorderSide(color: K.red)),
        onPressed: () async { await rejectOrder(o); if (context.mounted) Navigator.pop(context); },
        icon: const Icon(Icons.close_rounded), label: const Text('رفض'))),
    ])) : null,
  );
}
