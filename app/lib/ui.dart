import 'package:flutter/material.dart';

// ── Design tokens ────────────────────────────────────────────────────────
// Same palette and type scale as the web app, so the product reads as one.
const kBrand = Color(0xFF0A7A4A);
const kBrandInk = Color(0xFF075C37);
const kBrandTint = Color(0xFFE8F4EE);
const kSuccessTop = Color(0xFF12A862);
const kSuccessBottom = Color(0xFF086A41);
const kInk = Color(0xFF0E1A15);
const kInkSoft = Color(0xFF4A5A52);
const kSurface = Color(0xFFFFFFFF);
const kSurface2 = Color(0xFFF4F7F5);
const kPage = Color(0xFFF2F5F3);
const kLine = Color(0xFFE2E8E4);
const kAmber = Color(0xFFA35A08);
const kAmberTint = Color(0xFFFBF1E4);
const kViolet = Color(0xFF6D28D9);
const kVioletTint = Color(0xFFF1EBFC);
const kDanger = Color(0xFFC62A2A);
const kDangerTint = Color(0xFFFDECEB);

// Legacy aliases kept so existing screens keep compiling
const kGreen = kBrand;
const kGreenBright = kSuccessTop;
const kGreenDark = kBrandInk;
const kMuted = kInkSoft;
const kBg = kPage;
const kAmberBg = kAmberTint;
const kRed = kDanger;

/// Variable-font text style. Weight rides the `wght` axis so every weight
/// comes from one bundled file.
TextStyle wk({
  double size = 15,
  double weight = 500,
  Color color = kInk,
  double tracking = -0.01,
  double? height,
  bool tabular = false,
  bool mono = false,
}) =>
    TextStyle(
      fontFamily: mono ? 'JetBrainsMono' : 'PlusJakartaSans',
      fontSize: size,
      color: color,
      height: height,
      letterSpacing: size * tracking,
      fontVariations: [FontVariation('wght', weight)],
      fontWeight: FontWeight.values[
          ((weight / 100).round() - 1).clamp(0, FontWeight.values.length - 1)],
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

/// Money and any figure that updates in place (tabular: never jitters).
TextStyle wkNum({double size = 42, double weight = 800, Color color = kInk}) =>
    wk(size: size, weight: weight, color: color, tracking: -0.04, tabular: true);

String fmtNum(double v) {
  // Bolivian format: 1.245,50
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buf.write(digits[i]);
    final left = digits.length - i - 1;
    if (left > 0 && left % 3 == 0) buf.write('.');
  }
  return '$buf,${parts[1]}';
}

String fmtUsdt(BigInt units) => fmtNum(units.toDouble() / 1e6);

String short(String v) =>
    v.length > 12 ? '${v.substring(0, 6)}…${v.substring(v.length - 4)}' : v;

// ── Shared widgets ───────────────────────────────────────────────────────

/// Discreet, honest testnet marker: present in every screen, never shouting.
class EnvChip extends StatelessWidget {
  const EnvChip({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        decoration: BoxDecoration(
          color: kSurface2,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: kAmber),
            ),
            const SizedBox(width: 6),
            Text('Fase de prueba',
                style: wk(size: 11.5, weight: 600, color: kInkSoft)),
          ],
        ),
      );
}

/// Marks a vision screen as a mockup — honest, but not louder than the design.
class ConceptChip extends StatelessWidget {
  final String label;
  const ConceptChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: kVioletTint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: kViolet),
            ),
            const SizedBox(width: 6),
            Text(label, style: wk(size: 11.5, weight: 700, color: kViolet)),
          ],
        ),
      );
}

/// Slim top bar: wordmark on the left, the test-phase chip on the right.
class WalikiBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool back;
  final List<Widget> actions;

  const WalikiBar({super.key, this.title, this.back = false, this.actions = const []});

  @override
  Size get preferredSize => const Size.fromHeight(54);

  @override
  Widget build(BuildContext context) => Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(bottom: BorderSide(color: kLine)),
        ),
        child: Row(
          children: [
            if (back)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: kInk),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            else
              const SizedBox(width: 10),
            if (title == null) ...[
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: kBrand),
              ),
              const SizedBox(width: 7),
              Text('waliki', style: wk(size: 19, weight: 800, color: kBrandInk, tracking: -0.03)),
            ] else
              Text(title!, style: wk(size: 17, weight: 700, tracking: -0.02)),
            const Spacer(),
            ...actions,
            const EnvChip(),
            const SizedBox(width: 10),
          ],
        ),
      );
}

class WCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? border;
  const WCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.border,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: border ?? kLine, width: border != null ? 1.5 : 1),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D0E1A15), blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
        child: child,
      );
}

class WChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const WChip(this.text, {super.key, this.bg = kBrandTint, this.fg = kBrandInk});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: wk(size: 12, weight: 700, color: fg)),
      );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color fg;
  const PrimaryButton(this.label,
      {super.key, this.onTap, this.color = kBrand, this.fg = Colors.white});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: fg,
            disabledBackgroundColor: const Color(0xFFDBE2DD),
            disabledForegroundColor: const Color(0xFF8B978F),
            elevation: onTap == null ? 0 : 2,
            shadowColor: color.withValues(alpha: 0.45),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onTap,
          child: Text(label, style: wk(size: 15.5, weight: 700, color: onTap == null ? const Color(0xFF8B978F) : fg)),
        ),
      );
}
