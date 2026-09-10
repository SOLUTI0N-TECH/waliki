import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Design tokens ──────────────────────────────────────────────
// Sampled straight from the logo (design/brand/logo-source.jpg): the mark runs
// violet to cyan and the wordmark is navy. Same values as the web app, so the
// product reads as one.
const kBrandViolet = Color(0xFF6D2FF8);
const kBrandIndigo = Color(0xFF3D32F1);
const kBrand = Color(0xFF0072EF);
const kBrandCyan = Color(0xFF03BAE5);
const kBrandTeal = Color(0xFF33D0D4);
const kBrandInk = Color(0xFF031740);
const kBrandTint = Color(0xFFE7F0FE);
const kCyanTint = Color(0xFFE0F7FA);

/// The mark's own gradient, for the surfaces that carry the brand.
const kBrandGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kBrandViolet, kBrand, kBrandCyan],
);

/// Same run, darkened at the far end so white text keeps its contrast. Used
/// where type sits on top of it: the primary button and the paid screen.
const kActionGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF5B2CF5), Color(0xFF1668E8)],
);

// Neutrals carry a blue cast now, to sit under the navy rather than fight it.
const kInk = Color(0xFF0B1220);
const kInkSoft = Color(0xFF4B5B76);
const kSurface = Color(0xFFFFFFFF);
const kSurface2 = Color(0xFFF2F6FC);
const kPage = Color(0xFFF0F4FA);
const kLine = Color(0xFFE0E7F1);
const kDisabled = Color(0xFFDCE3EE);
const kDisabledInk = Color(0xFF97A3B8);

// The paid screen: the brand run, anchored in navy so every white label on it
// clears 4.5:1.
const kSuccessTop = kBrandViolet;
const kSuccessMid = Color(0xFF1B4FE8);
const kSuccessBottom = Color(0xFF041B4D);

const kAmber = Color(0xFF9A5B00);
const kAmberTint = Color(0xFFFDF2E3);
// Violet belongs to the brand now, so mockup markers moved to a quiet slate.
const kConcept = Color(0xFF5B6B8C);
const kConceptTint = Color(0xFFEEF1F7);
// Loading placeholders: a shade below the page so the shapes read as absent
// content, plus the highlight the shimmer sweeps across them.
const kSkeleton = Color(0xFFE2E9F4);
const kSkeletonGlow = Color(0xFFF6F9FD);
const kDanger = Color(0xFFC62A2A);
const kDangerTint = Color(0xFFFDECEB);

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
}) => TextStyle(
  fontFamily: mono ? 'JetBrainsMono' : 'PlusJakartaSans',
  fontSize: size,
  color: color,
  height: height,
  letterSpacing: size * tracking,
  fontVariations: [FontVariation('wght', weight)],
  fontWeight:
      FontWeight.values[((weight / 100).round() - 1).clamp(
        0,
        FontWeight.values.length - 1,
      )],
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
);

/// Money and any figure that updates in place (tabular: never jitters).
TextStyle wkNum({double size = 42, double weight = 800, Color color = kInk}) =>
    wk(
      size: size,
      weight: weight,
      color: color,
      tracking: -0.04,
      tabular: true,
    );

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

/// Marks a vision screen as a mockup — honest, but not louder than the design.
class ConceptChip extends StatelessWidget {
  final String label;
  const ConceptChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
    margin: const EdgeInsets.only(right: 8),
    decoration: BoxDecoration(
      color: kConceptTint,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: kConcept,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: wk(size: 11.5, weight: 700, color: kConcept)),
      ],
    ),
  );
}

/// Slim top bar: wordmark on the left, optional actions on the right.
///
/// Scaffold grows the bar by the status-bar inset on top of [preferredSize],
/// so the SafeArea below paints the brand surface behind the notch and keeps
/// the row itself clear of it.
class WalikiBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool back;
  final List<Widget> actions;

  /// Screens that already show the logo as their hero pass false, so the brand
  /// is not stated twice on one screen.
  final bool mark;

  const WalikiBar({
    super.key,
    this.title,
    this.back = false,
    this.actions = const [],
    this.mark = true,
  });

  static const double barHeight = 54;

  @override
  Size get preferredSize => const Size.fromHeight(barHeight);

  /// Dark status-bar icons: the bar is white, so the system defaults
  /// (light icons) would be invisible on it.
  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: kSurface,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: overlay,
    child: Container(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(bottom: BorderSide(color: kLine)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              if (back)
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: kInk,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              else
                const SizedBox(width: 18),
              if (title == null && mark) ...[
                Image.asset(
                  'assets/brand/symbol.png',
                  height: 26,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(width: 9),
                Text(
                  'Waliki',
                  style: wk(
                    size: 19,
                    weight: 800,
                    color: kBrandInk,
                    tracking: -0.03,
                  ),
                ),
              ] else if (title != null)
                Text(title!, style: wk(size: 17, weight: 700, tracking: -0.02)),
              const Spacer(),
              ...actions,
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Centres a short message while staying scrollable: a RefreshIndicator only
/// reacts to a scrollable child, so empty and error states need one too.
class ScrollableCenter extends StatelessWidget {
  final Widget child;
  const ScrollableCenter({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
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
      border: Border.all(
        color: border ?? kLine,
        width: border != null ? 1.5 : 1,
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D0E1A15),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: child,
  );
}

class WChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const WChip(
    this.text, {
    super.key,
    this.bg = kBrandTint,
    this.fg = kBrandInk,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: wk(size: 12, weight: 700, color: fg)),
  );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  /// A solid colour overrides the brand gradient — used where the button sits
  /// on top of the gradient itself and has to invert.
  final Color? color;
  final Color fg;
  const PrimaryButton(
    this.label, {
    super.key,
    this.onTap,
    this.color,
    this.fg = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final radius = BorderRadius.circular(14);
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: enabled && color == null ? kActionGradient : null,
          color: !enabled ? kDisabled : color,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: (color ?? kBrandIndigo).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: wk(
                  size: 15.5,
                  weight: 700,
                  color: enabled ? fg : kDisabledInk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
