part of '../../main.dart';

// ════════════════════════════════════════════════════════════════════
//  خطوات الاشتراك (بلا صفحة تعليمات):
//   1) الباقة  →  2) طريقة الدفع  →  3) الاسم ورقم الهاتف
//   →  4) رقم التحويل + إرفاق صورة الحوالة  →  تم: رقم الطلب + تتبّع + شكوى
//  الطلب يُكتب في Firestore (orders) كما في النظام السابق تماماً،
//  فلوحة الإدارة وتتبّع الطلبات يعملان بلا أي تغيير.
// ════════════════════════════════════════════════════════════════════
class SubscribeFlowPage extends StatefulWidget {
  const SubscribeFlowPage({super.key});

  static void open(BuildContext ctx) {
    if (AuthService.currentUser == null) { showLoginGate(ctx); return; }
    PayMethod.loadOverrides();
    Navigator.push(ctx, _fade(const SubscribeFlowPage()));
  }

  @override State<SubscribeFlowPage> createState() => _SubscribeFlowPageState();
}

class _SubscribeFlowPageState extends State<SubscribeFlowPage> {
  int _step = 0;                 // 0 باقة · 1 طريقة · 2 الاسم · 3 التحويل · 4 تم
  PayPlan _plan = PayPlan.all.first;
  PayMethod? _method;
  final _name  = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false, _uploading = false;
  String _err = '', _orderId = '', _receiptB64 = '', _receiptUrl = '';
  Future<void>? _upload;           // رفع الإيصال إلى Storage (احتياط للصور الكبيرة)
  static const _kMaxB64 = 780000;  // حد آمن داخل مستند Firestore (الحد 1MiB)

  static const _steps = ['الباقة', 'الدفع', 'بياناتك', 'التحويل'];

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    if ((u?.displayName ?? '').isNotEmpty) _name.text = u!.displayName!;
  }

  @override
  void dispose() { _name.dispose(); _phone.dispose(); super.dispose(); }

  void _go(int s) { Sound.hapticL(); FocusScope.of(context).unfocus(); setState(() { _step = s; _err = ''; }); }

  void _back() {
    if (_step == 0 || _step == 4) { Navigator.pop(context); return; }
    _go(_step - 1);
  }

  bool get _phoneOk => _phone.text.replaceAll(RegExp(r'\D'), '').length >= 10;
  bool get _nameOk  => _name.text.trim().length >= 2;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: _step == 0 || _step == 4,
        onPopInvokedWithResult: (did, _) { if (!did) _back(); },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(child: Column(children: [
            _header(),
            Expanded(child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(
                position: Tween(begin: const Offset(-0.04, 0), end: Offset.zero).animate(a), child: c)),
              child: KeyedSubtree(key: ValueKey(_step), child: switch (_step) {
                0 => _plans(),
                1 => _methods(),
                2 => _details(),
                3 => _transfer(),
                _ => _done(),
              }),
            )),
          ])),
        ),
      ),
    );
  }

  // ── الترويسة + شريط الخطوات ─────────────────────────────────────
  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
    child: Column(children: [
      Row(children: [
        IconButton(
          icon: Icon(_step == 4 || _step == 0 ? Icons.close_rounded : Icons.arrow_forward_ios_rounded,
              color: Colors.white, size: _step == 4 || _step == 0 ? 26 : 18),
          onPressed: _back),
        Expanded(child: Text(_step == 4 ? 'تم إرسال طلبك' : 'الاشتراك في TOTV+',
            style: T.cairo(s: FS.lg, w: FontWeight.w800, c: Colors.white))),
        if (_step < 4)
          Text('${_step + 1} / 4', style: T.cairo(s: FS.sm, c: Colors.white54, w: FontWeight.w700)),
      ]),
      if (_step < 4) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: Row(children: [
            for (int i = 0; i < 4; i++) ...[
              Expanded(child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _step ? C.gold : Colors.white12,
                    borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 5),
                Text(_steps[i], style: T.cairo(s: 11.5, w: FontWeight.w700,
                    c: i == _step ? Colors.white : Colors.white38)),
              ])),
              if (i < 3) const SizedBox(width: 6),
            ],
          ]),
        ),
      ],
    ]),
  );

  Widget _bottomBtn(String label, VoidCallback? onTap, {bool busy = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: SizedBox(
      height: 56, width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: C.gold, foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFF3A3424), disabledForegroundColor: Colors.white38,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
            : Text(label, style: T.cairo(s: FS.lg, w: FontWeight.w900, c: onTap == null ? Colors.white38 : Colors.black)),
      ),
    ),
  );

  // ══ 1) الباقة ════════════════════════════════════════════════════
  Widget _plans() => Column(children: [
    Expanded(child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      children: [
        Text('اختر باقتك', style: T.cairo(s: 24, w: FontWeight.w900, c: Colors.white)),
        const SizedBox(height: 4),
        Text('كل الباقات تشمل المباريات والقنوات والأفلام والمسلسلات',
            style: T.cairo(s: FS.sm, c: Colors.white60)),
        const SizedBox(height: 16),
        for (final p in PayPlan.all) _planCard(p),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () { final nav = Navigator.of(context); nav.pop(); RedeemCodeSheet.show(nav.context); },
          icon: const Icon(Icons.vpn_key_rounded, color: C.gold, size: 18),
          label: Text('لديك كود تفعيل؟ فعّله فوراً',
              style: T.cairo(s: FS.md, c: C.gold, w: FontWeight.w700)),
        ),
      ],
    )),
    _bottomBtn('متابعة', () => _go(1)),
  ]);

  Widget _planCard(PayPlan p) {
    final on = _plan.id == p.id;
    return GestureDetector(
      onTap: () { Sound.hapticL(); setState(() => _plan = p); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF1E1A10) : const Color(0xFF141417),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? C.gold : const Color(0xFF26262C), width: on ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22, height: 22,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  border: Border.all(color: on ? C.gold : Colors.white38, width: 2),
                  color: on ? C.gold : Colors.transparent),
              child: on ? const Icon(Icons.check_rounded, size: 15, color: Colors.black) : null,
            ),
            const SizedBox(width: 10),
            Text('باقة ${p.title}', style: T.cairo(s: FS.lg, w: FontWeight.w900, c: Colors.white)),
            const SizedBox(width: 8),
            if (p.badge.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: C.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(p.badge, style: T.cairo(s: 11, w: FontWeight.w800, c: C.gold)),
              ),
            const Spacer(),
            Text.rich(TextSpan(children: [
              TextSpan(text: p.price, style: T.cairo(s: 22, w: FontWeight.w900, c: Colors.white)),
              TextSpan(text: ' د.ع', style: T.cairo(s: FS.sm, c: Colors.white60, w: FontWeight.w700)),
            ])),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final f in p.features)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded, size: 14, color: on ? C.gold : Colors.white38),
                const SizedBox(width: 4),
                Text(f, style: T.cairo(s: FS.sm, c: Colors.white70)),
              ]),
          ]),
        ]),
      ),
    );
  }

  // ══ 2) طريقة الدفع ═══════════════════════════════════════════════
  Widget _methods() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
    children: [
      Text('اختر طريقة الدفع', style: T.cairo(s: 24, w: FontWeight.w900, c: Colors.white)),
      const SizedBox(height: 4),
      Text('باقة ${_plan.title} — ${_plan.price} د.ع',
          style: T.cairo(s: FS.md, c: C.gold, w: FontWeight.w700)),
      const SizedBox(height: 16),
      for (final m in PayMethod.all) _methodCard(m),
    ],
  );

  Widget _methodCard(PayMethod m) {
    final c = Color(m.color);
    return GestureDetector(
      onTap: () {
        Sound.hapticL();
        if (m.id == 'whatsapp') {
          final wa = RC.whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
          final u = FirebaseAuth.instance.currentUser;
          final msg = Uri.encodeComponent('مرحباً، أريد الاشتراك في TOTV+\n'
              'الباقة: ${_plan.title} (${_plan.price} د.ع)\nالبريد: ${u?.email ?? '—'}');
          if (wa.isNotEmpty) {
            launchUrl(Uri.parse('https://wa.me/$wa?text=$msg'), mode: LaunchMode.externalApplication);
          }
          return;
        }
        setState(() => _method = m);
        _go(2);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141417),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF26262C)),
        ),
        child: Row(children: [
          Container(
            width: 64, height: 44, padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: m.asset != null ? Colors.white : c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
            child: m.asset != null
                ? Image.asset(m.asset!, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(Icons.account_balance_wallet_rounded, color: c))
                : Icon(Icons.chat_rounded, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(m.label, style: T.cairo(s: FS.lg, w: FontWeight.w800, c: Colors.white)),
              if ((m.badge ?? '').isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(5)),
                  child: Text(m.badge!, style: T.cairo(s: 10.5, c: Colors.white70, w: FontWeight.w700)),
                ),
              ],
            ]),
            Text(m.sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: T.cairo(s: FS.sm, c: Colors.white54)),
          ])),
          const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white38, size: 16),
        ]),
      ),
    );
  }

  // ══ 3) الاسم ورقم الهاتف ═════════════════════════════════════════
  Widget _details() => Column(children: [
    Expanded(child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      children: [
        Text('اكتب اسمك', style: T.cairo(s: 24, w: FontWeight.w900, c: Colors.white)),
        const SizedBox(height: 4),
        Text('نستخدمه لمطابقة الحوالة مع طلبك', style: T.cairo(s: FS.sm, c: Colors.white60)),
        const SizedBox(height: 18),
        _field(_name, 'الاسم الكامل', Icons.person_outline_rounded),
        const SizedBox(height: 12),
        _field(_phone, 'رقم الهاتف (07XX XXX XXXX)', Icons.phone_iphone_rounded, phone: true),
        if (_err.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_err, style: T.cairo(s: FS.sm, c: Colors.redAccent)),
        ),
      ],
    )),
    _bottomBtn('متابعة', (_nameOk && _phoneOk) ? () => _go(3) : null),
  ]);

  Widget _field(TextEditingController c, String hint, IconData icon, {bool phone = false}) => TextField(
    controller: c,
    keyboardType: phone ? TextInputType.phone : TextInputType.name,
    textDirection: phone ? TextDirection.ltr : TextDirection.rtl,
    textAlign: TextAlign.right,
    onChanged: (_) => setState(() {}),
    style: T.cairo(s: FS.lg, w: FontWeight.w700, c: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: T.cairo(s: FS.md, c: Colors.white38),
      prefixIcon: Icon(icon, color: Colors.white54),
      filled: true, fillColor: const Color(0xFF141417),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2A2A30))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.gold, width: 1.5)),
    ),
  );

  // ══ 4) التحويل + الإيصال ════════════════════════════════════════
  Widget _transfer() {
    final m = _method!;
    final c = Color(m.color);
    final hasReceipt = _receiptB64.isNotEmpty;
    return Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        children: [
          Text('حوّل المبلغ', style: T.cairo(s: 24, w: FontWeight.w900, c: Colors.white)),
          const SizedBox(height: 4),
          Text('حوّل المبلغ كاملاً إلى الرقم أدناه ثم أرفق صورة الحوالة',
              style: T.cairo(s: FS.sm, c: Colors.white60)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Color(m.bg),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.withOpacity(0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                if (m.asset != null)
                  Container(width: 70, height: 40, padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Image.asset(m.asset!, fit: BoxFit.contain)),
                const SizedBox(width: 10),
                Expanded(child: Text(m.label, style: T.cairo(s: FS.lg, w: FontWeight.w900, c: c))),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('المبلغ', style: T.cairo(s: 11, c: Colors.white54)),
                  Text('${_plan.price} د.ع', style: T.cairo(s: 20, w: FontWeight.w900, c: Colors.white)),
                ]),
              ]),
              const SizedBox(height: 16),
              Text('الرقم — اضغط للنسخ', style: T.cairo(s: FS.xs, c: Colors.white54)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _copy(m.liveNumber),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.withOpacity(0.3))),
                  child: Row(children: [
                    Expanded(child: Text(m.liveNumber, textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                        style: T.cairo(s: 22, w: FontWeight.w900, c: Colors.white, ls: 1.2))),
                    Icon(Icons.copy_rounded, color: c, size: 20),
                  ]),
                ),
              ),
              if (m.liveName.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('باسم: ${m.liveName}', style: T.cairo(s: FS.md, c: Colors.white70, w: FontWeight.w700)),
              ],
            ]),
          ),
          const SizedBox(height: 18),
          Text('صورة الحوالة', style: T.cairo(s: FS.md, w: FontWeight.w800, c: Colors.white)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _uploading ? null : _pickReceipt,
            child: Container(
              height: hasReceipt ? 180 : 130,
              decoration: BoxDecoration(
                color: const Color(0xFF141417),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: hasReceipt ? C.green : C.gold.withOpacity(0.5), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: _uploading
                  ? const Center(child: CircularProgressIndicator(color: C.gold))
                  : hasReceipt
                      ? Stack(fit: StackFit.expand, children: [
                          Image.memory(base64Decode(_receiptB64), fit: BoxFit.cover),
                          Positioned(bottom: 8, left: 8, child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                            child: Text('✓ تم الإرفاق — اضغط للتغيير',
                                style: T.cairo(s: FS.xs, c: C.green, w: FontWeight.w700)),
                          )),
                        ])
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.add_photo_alternate_outlined, color: C.gold, size: 36),
                          const SizedBox(height: 6),
                          Text('أرفق صورة الحوالة', style: T.cairo(s: FS.md, w: FontWeight.w800, c: Colors.white)),
                          Text('من معرض الصور', style: T.cairo(s: FS.xs, c: Colors.white54)),
                        ]),
            ),
          ),
          if (_err.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_err, style: T.cairo(s: FS.sm, c: Colors.redAccent)),
          ),
        ],
      )),
      _bottomBtn('إرسال طلب الاشتراك', hasReceipt ? _submit : null, busy: _busy),
    ]);
  }

  Future<void> _pickReceipt() async {
    Sound.hapticL();
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 50, maxWidth: 1000);
      if (img == null) return;
      setState(() => _uploading = true);
      final bytes = await img.readAsBytes();
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        setState(() { _uploading = false; _err = 'الصورة كبيرة جداً — اختر صورة أصغر'; });
        return;
      }
      _receiptB64 = base64Encode(bytes);
      _receiptUrl = '';
      _err = '';
      // نسخة في Storage أيضاً — إلزامية إذا كانت الصورة أكبر من أن تُخزَّن داخل الطلب
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      _upload = () async {
        try {
          final ref = FirebaseStorage.instance.ref('receipts/$uid/receipt_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await ref.putData(Uint8List.fromList(bytes), SettableMetadata(contentType: 'image/jpeg'));
          _receiptUrl = await ref.getDownloadURL();
        } catch (e) { debugPrint('[receipt upload] $e'); }
      }();
      if (_receiptB64.length > _kMaxB64) await _upload;
      if (mounted) setState(() => _uploading = false);
    } catch (e) {
      if (mounted) setState(() { _uploading = false; _err = 'تعذّر إرفاق الصورة — حاول مجدداً'; });
    }
  }

  String _fnv(String s) {
    int h = 0x811c9dc5;
    for (int i = 0; i < s.length; i++) { h ^= s.codeUnitAt(i); h = (h * 0x01000193) & 0xFFFFFFFF; }
    return '${h.toRadixString(16)}_${s.length}';
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() { _busy = true; _err = ''; });
    final user = FirebaseAuth.instance.currentUser;
    final m = _method!;
    _orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
    // ★ تأكد أن صورة الإيصال ستصل مع الطلب
    final inlineOk = _receiptB64.isNotEmpty && _receiptB64.length <= _kMaxB64;
    if (_upload != null) {
      try { await _upload!.timeout(Duration(seconds: inlineOk ? 6 : 40)); } catch (_) {}
    }
    if (!inlineOk && _receiptUrl.isEmpty) {
      if (mounted) setState(() { _busy = false; _err = 'تعذّر رفع صورة الإيصال — اختر صورة أصغر أو أعد المحاولة'; });
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('orders').doc(_orderId).set({
        'order_id': _orderId,
        'uid': user?.uid ?? 'guest',
        'email': user?.email ?? '',
        'account_name': user?.displayName ?? '',
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'plan': _plan.id,
        'plan_title': _plan.title,
        'price': _plan.price,
        'price_num': _plan.priceNum,
        'method': m.label,
        'method_number': m.liveNumber,
        'type': 'transfer',
        'asia_card_code': '',
        'asia_amount': '',
        'has_receipt': true,
        'receipt_url': _receiptUrl,
        'receipt_b64': inlineOk ? _receiptB64 : '',
        'receipt_hash': _fnv(_receiptB64),
        'status': 'pending',
        'created': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[subscribe] $e');
      if (mounted) setState(() { _busy = false; _err = 'تعذّر إرسال الطلب — تحقّق من الاتصال وحاول مجدداً'; });
      return;
    }
    // ★ إشعار فوري لتطبيق الإدارة: «لديك طلب اشتراك — يرجى التفعيل»
    unawaited(AdminOrderPush.send(orderId: _orderId, name: _name.text.trim(),
        plan: _plan.title, price: _plan.price, method: m.label));
    // إشعار الإدارة (نفس آلية النظام السابق)
    try {
      await DioClient.telegram.post(
        'https://api.telegram.org/bot${_PayPaymentSheetState._tgBotToken}/sendMessage',
        data: {
          'chat_id': _PayPaymentSheetState._tgChatId,
          'text': '🔔 *طلب اشتراك جديد*\n\n🆔 `$_orderId`\n👤 ${_name.text.trim()}\n📞 ${_phone.text.trim()}\n'
              '📦 اشتراك ${_plan.title}\n💰 ${_plan.price} د.ع\n💳 ${m.label} (${m.liveNumber})\n'
              '📧 ${user?.email ?? '—'}\n🧾 إيصال: نعم',
          'parse_mode': 'Markdown',
        },
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}
    await Sound.hapticOk();
    Sound.cash();
    if (mounted) setState(() { _busy = false; _step = 4; });
  }

  Future<void> _copy(String v) async {
    await Clipboard.setData(ClipboardData(text: v));
    Sound.hapticM();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating, backgroundColor: C.gold,
      content: Text('تم نسخ الرقم', style: T.cairo(s: FS.sm, c: Colors.black, w: FontWeight.w700))));
  }

  // ══ تم ═══════════════════════════════════════════════════════════
  Widget _done() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
    children: [
      Center(child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 650), curve: Curves.elasticOut,
        builder: (_, v, __) => Transform.scale(scale: v, child: Container(
          width: 96, height: 96,
          decoration: BoxDecoration(shape: BoxShape.circle, color: C.green.withOpacity(0.12),
              border: Border.all(color: C.green, width: 2)),
          child: const Icon(Icons.check_rounded, color: C.green, size: 52))),
      )),
      const SizedBox(height: 18),
      Center(child: Text('تم إنشاء طلب الاشتراك', style: T.cairo(s: 22, w: FontWeight.w900, c: Colors.white))),
      const SizedBox(height: 6),
      Center(child: Text('سنراجع الحوالة ونفعّل اشتراكك خلال دقائق',
          textAlign: TextAlign.center, style: T.cairo(s: FS.md, c: Colors.white60))),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF141417), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF26262C))),
        child: Column(children: [
          _kv('رقم الطلب', _orderId, copy: true),
          _kv('الباقة', '${_plan.title} — ${_plan.price} د.ع'),
          _kv('طريقة الدفع', _method?.label ?? ''),
          _kv('الحالة', '⏳ قيد المراجعة'),
        ]),
      ),
      const SizedBox(height: 22),
      SizedBox(height: 54, child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: C.gold, foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        onPressed: () => Navigator.pushReplacement(context, _fade(const OrderTrackingPage())),
        icon: const Icon(Icons.track_changes_rounded),
        label: Text('تتبّع الطلب', style: T.cairo(s: FS.lg, w: FontWeight.w900, c: Colors.black)),
      )),
      const SizedBox(height: 10),
      SizedBox(height: 52, child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        onPressed: () => ComplaintSheet.show(context),
        icon: const Icon(Icons.report_gmailerrorred_rounded, color: Colors.white70),
        label: Text('تقديم شكوى', style: T.cairo(s: FS.md, w: FontWeight.w800, c: Colors.white)),
      )),
      const SizedBox(height: 10),
      Center(child: TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('العودة للتطبيق', style: T.cairo(s: FS.md, c: Colors.white60, w: FontWeight.w700)),
      )),
      const SizedBox(height: 6),
      Center(child: Text('تجد «تتبّع طلب الاشتراك» و«تقديم شكوى» دائماً في قائمة المزيد',
          textAlign: TextAlign.center, style: T.cairo(s: FS.xs, c: Colors.white38))),
    ],
  );

  Widget _kv(String k, String v, {bool copy = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Text(k, style: T.cairo(s: FS.sm, c: Colors.white54)),
      const Spacer(),
      GestureDetector(
        onTap: copy ? () => _copy(v) : null,
        child: Row(children: [
          Text(v, textDirection: TextDirection.ltr,
              style: T.cairo(s: FS.md, w: FontWeight.w800, c: copy ? C.gold : Colors.white)),
          if (copy) ...[const SizedBox(width: 6), const Icon(Icons.copy_rounded, size: 15, color: C.gold)],
        ]),
      ),
    ]),
  );
}
