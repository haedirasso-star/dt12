part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  الهوية البصرية + عناصر الواجهة المشتركة
// ════════════════════════════════════════════════════════════════════
class K {
  static const bg    = Color(0xFF08080C);
  static const bar   = Color(0xFF0E0E14);
  static const card  = Color(0xFF14141B);
  static const card2 = Color(0xFF1B1B24);
  static const line  = Color(0xFF262633);
  static const gold  = Color(0xFFF5B82E);
  static const gold2 = Color(0xFFFFD36B);
  static const grn   = Color(0xFF22C55E);
  static const red   = Color(0xFFEF4444);
  static const blu   = Color(0xFF3B82F6);
  static const org   = Color(0xFFF97316);
  static const prp   = Color(0xFFA855F7);
  static const cyn   = Color(0xFF06B6D4);
  static const t1    = Color(0xFFF4F4F6);
  static const t2    = Color(0xFFA1A1B0);
  static const t3    = Color(0xFF6B6B7B);

  static const h1  = TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: t1, height: 1.2);
  static const h2  = TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: t1, height: 1.3);
  static const h3  = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: t1, height: 1.35);
  static const body = TextStyle(fontSize: 14, color: t1, height: 1.5);
  static const sub = TextStyle(fontSize: 12.5, color: t2, height: 1.5);
  static const tiny = TextStyle(fontSize: 11, color: t3, height: 1.4);
  static const mono = TextStyle(fontSize: 13, color: t1, fontFamily: 'monospace', letterSpacing: .2);

  static ThemeData theme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(primary: gold, secondary: gold, surface: card, error: red),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg, surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: t1),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bar,
      surfaceTintColor: Colors.transparent,
      indicatorColor: gold.withOpacity(.16),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
        fontSize: 11.5, fontWeight: FontWeight.w800,
        color: s.contains(WidgetState.selected) ? gold : t3)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
        size: 25, color: s.contains(WidgetState.selected) ? gold : t2)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: t2),
      hintStyle: const TextStyle(color: t3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: gold, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: gold, foregroundColor: Colors.black,
      minimumSize: const Size(0, 50),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: t1, minimumSize: const Size(0, 46),
      side: const BorderSide(color: line),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: gold, textStyle: const TextStyle(fontWeight: FontWeight.w800))),
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: bar, surfaceTintColor: Colors.transparent, showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
    dialogTheme: DialogThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: card2,
      contentTextStyle: const TextStyle(color: t1, fontSize: 14, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black : t2),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? gold : card2),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    }),
  );
}

class Nav {
  static final key = GlobalKey<NavigatorState>();
  static final messenger = GlobalKey<ScaffoldMessengerState>();
  static BuildContext? get ctx => key.currentContext;
  static Future<T?> push<T>(Widget page) =>
      key.currentState!.push<T>(MaterialPageRoute(builder: (_) => page));
}

// ════════════════════════════════════════════════════════════════════
//  رسائل وحوارات
// ════════════════════════════════════════════════════════════════════
class UI {
  static void toast(String msg, {bool error = false}) {
    final m = Nav.messenger.currentState;
    if (m == null || msg.isEmpty) return;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(error ? Icons.error_rounded : Icons.check_circle_rounded, color: error ? K.red : K.grn, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        duration: Duration(milliseconds: error ? 3800 : 2200),
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      ));
  }

  static void err(Object e) => toast(Fmt.err(e), error: true);

  static Future<bool> confirm(String title, String body, {String ok = 'تأكيد', bool danger = false}) async {
    final c = Nav.ctx;
    if (c == null) return false;
    final r = await showDialog<bool>(context: c, builder: (d) => AlertDialog(
      title: Text(title, style: K.h3),
      content: Text(body, style: K.body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء', style: TextStyle(color: K.t2))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: K.red, foregroundColor: Colors.white, minimumSize: const Size(90, 44))
                        : FilledButton.styleFrom(minimumSize: const Size(90, 44)),
          onPressed: () => Navigator.pop(d, true), child: Text(ok)),
      ],
    ));
    return r ?? false;
  }

  /// إدخال نص (أو رقم) في نافذة سفلية
  static Future<String?> input(String title, {String hint = '', String initial = '', bool number = false,
      bool multiline = false, String ok = 'حفظ', String? help}) async {
    final c = Nav.ctx;
    if (c == null) return null;
    final ctrl = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
      context: c, isScrollControlled: true,
      builder: (s) => Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.of(s).viewInsets.bottom + 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: K.h2),
          if (help != null) ...[const SizedBox(height: 6), Text(help, style: K.sub)],
          const SizedBox(height: 14),
          TextField(
            controller: ctrl, autofocus: true,
            keyboardType: number ? const TextInputType.numberWithOptions(signed: true) : (multiline ? TextInputType.multiline : TextInputType.text),
            maxLines: multiline ? 5 : 1,
            textDirection: number ? TextDirection.ltr : null,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: multiline ? null : (v) => Navigator.pop(s, v.trim()),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.pop(s, ctrl.text.trim()), child: Text(ok)),
        ]),
      ),
    );
  }

  /// اختيار من قائمة
  static Future<T?> pick<T>(String title, List<(T, String, IconData?)> items) async {
    final c = Nav.ctx;
    if (c == null) return null;
    return showModalBottomSheet<T>(context: c, builder: (s) => SafeArea(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 8), child: Align(alignment: Alignment.centerRight, child: Text(title, style: K.h3))),
        for (final (v, label, icon) in items)
          ListTile(
            leading: icon == null ? null : Icon(icon, color: K.gold),
            title: Text(label, style: K.body.copyWith(fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pop(s, v),
          ),
        const SizedBox(height: 10),
      ])));
  }

  /// صفحة سفلية كاملة بمحتوى قابل للتمرير
  static Future<T?> sheet<T>(Widget child, {double initial = .85}) {
    final c = Nav.ctx!;
    return showModalBottomSheet<T>(
      context: c, isScrollControlled: true, useSafeArea: true,
      builder: (s) => DraggableScrollableSheet(
        expand: false, initialChildSize: initial, maxChildSize: .96, minChildSize: .35,
        builder: (_, sc) => PrimaryScrollController(controller: sc, child: child),
      ),
    );
  }

  static Future<void> copy(String text, {String label = 'تم النسخ'}) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    toast('📋 $label');
  }

  static Future<void> whatsapp(String phone, {String text = ''}) async {
    var p = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('0')) p = '964${p.substring(1)}';
    if (p.isEmpty) { toast('لا يوجد رقم', error: true); return; }
    final u = Uri.parse('https://wa.me/$p${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  static Future<void> open(String url) async {
    try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (e) { err(e); }
  }
}

// ════════════════════════════════════════════════════════════════════
//  عناصر الواجهة
// ════════════════════════════════════════════════════════════════════
class Box extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color, border;
  final VoidCallback? onTap;
  final double radius;
  final Gradient? gradient;
  const Box({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color,
      this.border, this.onTap, this.radius = 18, this.gradient});
  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? K.card) : null,
          gradient: gradient,
          borderRadius: r,
          border: Border.all(color: border ?? K.line.withOpacity(.6)),
        ),
        child: InkWell(onTap: onTap, borderRadius: r, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class Kpi extends StatelessWidget {
  final String label, value;
  final String? hint;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool big;
  const Kpi({super.key, required this.label, required this.value, required this.icon,
      this.color = K.gold, this.hint, this.onTap, this.big = false});
  @override
  Widget build(BuildContext context) => Box(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
    gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
        colors: [color.withOpacity(.13), K.card]),
    border: color.withOpacity(.22),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 32, height: 32, alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withOpacity(.16), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color)),
        const Spacer(),
        if (onTap != null) const Icon(Icons.chevron_left_rounded, size: 18, color: K.t3),
      ]),
      const SizedBox(height: 10),
      FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart,
        child: Text(value, textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: big ? 32 : 25, fontWeight: FontWeight.w900, color: color, height: 1.1))),
      const SizedBox(height: 4),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: K.t1, fontWeight: FontWeight.w700)),
      if (hint != null && hint!.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: K.tiny),
      ],
    ]),
  );
}

/// شبكة مؤشرات بعمودين
class KpiGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  const KpiGrid({super.key, required this.children, this.columns = 2});
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = 0; j < columns; j++) ...[
            if (j > 0) const SizedBox(width: 10),
            Expanded(child: i + j < children.length ? children[i + j] : const SizedBox()),
          ],
        ])),
      ));
    }
    return Column(children: rows);
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;
  const Pill(this.text, {super.key, this.color = K.t2, this.icon, this.solid = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: solid ? color : color.withOpacity(.14),
      borderRadius: BorderRadius.circular(20),
      border: solid ? null : Border.all(color: color.withOpacity(.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 13, color: solid ? Colors.black : color), const SizedBox(width: 4)],
      Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: solid ? Colors.black : color)),
    ]),
  );
}

class Section extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const Section(this.title, {super.key, this.sub, this.trailing, this.padding = const EdgeInsets.fromLTRB(2, 18, 2, 10)});
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: K.h3),
        if (sub != null) Text(sub!, style: K.tiny),
      ])),
      if (trailing != null) trailing!,
    ]),
  );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final Widget? action;
  const EmptyView({super.key, this.icon = Icons.inbox_rounded, required this.title, this.sub, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 76, height: 76, alignment: Alignment.center,
          decoration: BoxDecoration(color: K.card2, borderRadius: BorderRadius.circular(24)),
          child: Icon(icon, size: 36, color: K.t3)),
      const SizedBox(height: 14),
      Text(title, textAlign: TextAlign.center, style: K.h3),
      if (sub != null) ...[const SizedBox(height: 6), Text(sub!, textAlign: TextAlign.center, style: K.sub)],
      if (action != null) ...[const SizedBox(height: 16), action!],
    ]),
  );
}

class Loading extends StatelessWidget {
  final String? text;
  const Loading({super.key, this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.6, color: K.gold)),
      if (text != null) ...[const SizedBox(height: 14), Text(text!, style: K.sub)],
    ]),
  );
}

class ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorBox(this.message, {super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => Box(
    color: K.red.withOpacity(.08), border: K.red.withOpacity(.35),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: K.red),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: K.sub.copyWith(color: K.t1))),
      if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('إعادة')),
    ]),
  );
}

class Banner2 extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Widget? action;
  const Banner2(this.text, {super.key, this.icon = Icons.info_rounded, this.color = K.gold, this.action});
  @override
  Widget build(BuildContext context) => Box(
    padding: const EdgeInsets.all(12),
    color: color.withOpacity(.08), border: color.withOpacity(.3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: K.sub.copyWith(color: K.t1))),
      if (action != null) action!,
    ]),
  );
}

/// صف معلومة قابل للنسخ (مثل Host / Username)
class InfoRow extends StatelessWidget {
  final String label, value;
  final bool copy, ltr;
  final Color? color;
  const InfoRow(this.label, this.value, {super.key, this.copy = false, this.ltr = false, this.color});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: copy && value.isNotEmpty && value != '—' ? () => UI.copy(value, label: 'نُسخ $label') : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: K.sub)),
        Expanded(child: Text(value.isEmpty ? '—' : value,
            textDirection: ltr ? TextDirection.ltr : null,
            textAlign: TextAlign.start,
            style: (ltr ? K.mono : K.body).copyWith(fontWeight: FontWeight.w700, color: color))),
        if (copy && value.isNotEmpty && value != '—') const Icon(Icons.copy_rounded, size: 16, color: K.t3),
      ]),
    ),
  );
}

class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged, onSubmitted;
  const SearchBox({super.key, required this.controller, this.hint = 'بحث...', this.onChanged, this.onSubmitted});
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded, color: K.t3),
      suffixIcon: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, v, __) => v.text.isEmpty ? const SizedBox.shrink() : IconButton(
          icon: const Icon(Icons.close_rounded, color: K.t3),
          onPressed: () { controller.clear(); onChanged?.call(''); onSubmitted?.call(''); }),
      ),
    ),
  );
}

/// شريط فلاتر أفقي
class Filters<T> extends StatelessWidget {
  final List<(T, String, int?)> items;
  final T value;
  final ValueChanged<T> onChanged;
  const Filters({super.key, required this.items, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final (v, label, n) = items[i];
        final on = v == value;
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () { HapticFeedback.selectionClick(); onChanged(v); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? K.gold : K.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? K.gold : K.line),
            ),
            child: Text(n == null ? label : '$label  $n',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: on ? Colors.black : K.t1)),
          ),
        );
      },
    ),
  );
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 44});
  static const _colors = [K.gold, K.blu, K.grn, K.prp, K.cyn, K.org, K.red];
  @override
  Widget build(BuildContext context) {
    final n = name.trim().isEmpty ? '?' : name.trim();
    var h = 0;
    for (final c in n.codeUnits) { h = (h * 31 + c) & 0x7fffffff; }
    final col = _colors[h % _colors.length];
    return Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: col.withOpacity(.18), borderRadius: BorderRadius.circular(size * .32),
          border: Border.all(color: col.withOpacity(.4))),
      child: Text(n.characters.first.toUpperCase(),
          style: TextStyle(color: col, fontSize: size * .42, fontWeight: FontWeight.w900)),
    );
  }
}

class Meter extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;
  const Meter(this.value, {super.key, this.color = K.gold, this.height = 6});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: LinearProgressIndicator(value: value.clamp(0, 1).toDouble(), minHeight: height,
        color: color, backgroundColor: K.card2),
  );
}

/// زر إجراء صغير بأيقونة ونص
class ActBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool filled;
  const ActBtn(this.icon, this.label, this.onTap, {super.key, this.color = K.t1, this.filled = false});
  @override
  Widget build(BuildContext context) => Material(
    color: filled ? color : K.card2,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap == null ? null : () { HapticFeedback.selectionClick(); onTap!(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: filled ? Colors.black : color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: filled ? Colors.black : color)),
        ]),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════
//  رسوم بيانية خفيفة (بلا مكتبات)
// ════════════════════════════════════════════════════════════════════
class BarSeries {
  final String label;
  final List<double> values; // مكدّسة: كل قيمة طبقة
  const BarSeries(this.label, this.values);
}

class BarChart extends StatelessWidget {
  final List<BarSeries> bars;
  final List<Color> colors;
  final double height;
  final bool showValues;
  const BarChart({super.key, required this.bars, required this.colors, this.height = 160, this.showValues = true});
  @override
  Widget build(BuildContext context) {
    final maxV = bars.fold<double>(0, (m, b) => math.max(m, b.values.fold<double>(0, (s, v) => s + v)));
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final b in bars)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (showValues)
                Text(_fmtV(b.values.fold<double>(0, (s, v) => s + v)), style: const TextStyle(fontSize: 9.5, color: K.t2, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Expanded(child: LayoutBuilder(builder: (_, c) {
                final total = b.values.fold<double>(0, (s, v) => s + v);
                final h = maxV <= 0 ? 0.0 : c.maxHeight * total / maxV;
                return Align(alignment: Alignment.bottomCenter, child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                  child: SizedBox(height: math.max(h, total > 0 ? 3 : 1.5), width: double.infinity,
                    child: Column(children: [
                      for (var i = b.values.length - 1; i >= 0; i--)
                        if (b.values[i] > 0)
                          Expanded(flex: (b.values[i] * 1000).round(), child: Container(color: colors[i % colors.length])),
                      if (total <= 0) Expanded(child: Container(color: K.card2)),
                    ]),
                  ),
                ));
              })),
              const SizedBox(height: 5),
              Text(b.label, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 9.5, color: K.t3)),
            ]),
          )),
      ]),
    );
  }
  static String _fmtV(double v) => v <= 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));
}

class Donut extends StatelessWidget {
  final Map<String, double> data;
  final List<Color> colors;
  final double size;
  final String? center;
  const Donut({super.key, required this.data, this.colors = const [K.gold, K.blu, K.grn, K.prp, K.cyn, K.org, K.red], this.size = 120, this.center});
  @override
  Widget build(BuildContext context) {
    final e = data.entries.where((x) => x.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = e.fold<double>(0, (s, x) => s + x.value);
    return Row(children: [
      SizedBox(width: size, height: size, child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size(size, size), painter: _DonutPainter(e.map((x) => x.value).toList(), colors)),
        if (center != null) Text(center!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      ])),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < e.length && i < 6; i++)
          Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(child: Text(e[i].key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: K.t1))),
            Text('${e[i].value.toInt()}', style: const TextStyle(fontSize: 12.5, color: K.t2, fontWeight: FontWeight.w800)),
            Text(total > 0 ? '  ${(e[i].value * 100 / total).round()}%' : '', style: K.tiny),
          ])),
        if (e.isEmpty) const Text('لا بيانات', style: K.sub),
      ])),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> v;
  final List<Color> c;
  _DonutPainter(this.v, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final total = v.fold<double>(0, (a, b) => a + b);
    final rect = Rect.fromLTWH(9, 9, s.width - 18, s.height - 18);
    final bgP = Paint()..style = PaintingStyle.stroke..strokeWidth = 16..color = K.card2;
    canvas.drawArc(rect, 0, math.pi * 2, false, bgP);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < v.length; i++) {
      final sweep = v[i] / total * math.pi * 2;
      final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 16..strokeCap = StrokeCap.butt..color = c[i % c.length];
      canvas.drawArc(rect, start, math.max(sweep - .03, .01), false, p);
      start += sweep;
    }
  }
  @override
  bool shouldRepaint(covariant _DonutPainter o) => o.v != v;
}

/// زر ثابت أسفل الصفحة
class BottomAction extends StatelessWidget {
  final Widget child;
  const BottomAction({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
    decoration: const BoxDecoration(color: K.bar, border: Border(top: BorderSide(color: K.line))),
    child: child,
  );
}

/// زر بحالة تحميل
class BusyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function()? onPressed;
  final bool busy;
  final Color? color;
  const BusyButton({super.key, required this.label, this.icon, this.onPressed, this.busy = false, this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54, width: double.infinity,
    child: FilledButton.icon(
      style: color == null ? null : FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
      onPressed: busy || onPressed == null ? null : () => onPressed!(),
      icon: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black))
          : Icon(icon ?? Icons.check_rounded),
      label: Text(label),
    ),
  );
}

class InField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint, help;
  final bool ltr, number, obscure, multiline;
  final IconData? icon;
  final ValueChanged<String>? onChanged;
  const InField(this.controller, this.label, {super.key, this.hint, this.help, this.ltr = false, this.number = false,
      this.obscure = false, this.multiline = false, this.icon, this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      keyboardType: number ? TextInputType.number : (multiline ? TextInputType.multiline : (ltr ? TextInputType.url : TextInputType.text)),
      maxLines: multiline ? 6 : 1,
      minLines: multiline ? 3 : 1,
      textDirection: ltr || number ? TextDirection.ltr : null,
      decoration: InputDecoration(labelText: label, hintText: hint, helperText: help, helperMaxLines: 3,
          prefixIcon: icon == null ? null : Icon(icon, color: K.t3, size: 20)),
    ),
  );
}

class SwitchRow extends StatelessWidget {
  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final Color color;
  const SwitchRow({super.key, required this.title, this.sub, required this.value, required this.onChanged, this.icon, this.color = K.gold});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      if (icon != null) ...[
        Container(width: 38, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(color: (value ? color : K.t3).withOpacity(.14), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: value ? color : K.t3)),
        const SizedBox(width: 12),
      ],
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: K.body.copyWith(fontWeight: FontWeight.w800)),
        if (sub != null) Text(sub!, style: K.tiny),
      ])),
      Switch(value: value, onChanged: (v) { HapticFeedback.mediumImpact(); onChanged(v); }),
    ]),
  );
}
