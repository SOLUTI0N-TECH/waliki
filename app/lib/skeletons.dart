import 'package:flutter/material.dart';

import 'ui.dart';

// Loading states shaped like the screen that is coming. A spinner says
// "wait"; a skeleton says "this is what you are about to read", so the layout
// never jumps once the chain answers.

/// Sweeps a highlight across everything painted below it.
///
/// The mask is applied once, at the top of each skeleton, so the glow crosses
/// the whole screen as a single sheet of light instead of each box blinking on
/// its own.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honor the system "remove animations" setting: the shapes still read.
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        // srcATop paints the gradient only where the skeleton shapes are,
        // leaving the page background untouched.
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [kSkeleton, kSkeletonGlow, kSkeleton],
          stops: const [0.3, 0.5, 0.7],
          transform: _Sweep(_c.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

/// Slides the highlight from fully off the left edge to fully off the right.
class _Sweep extends GradientTransform {
  final double t;
  const _Sweep(this.t);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2.6 - 1.3), 0, 0);
}

/// A single placeholder shape. A null height fills the parent's constraints.
class SkBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  const SkBox({super.key, this.width, this.height, this.radius = 14});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: kSkeleton,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// A placeholder for a line of text, measured as a fraction of the width.
class SkLine extends StatelessWidget {
  final double widthFactor;
  final double height;
  const SkLine({super.key, this.widthFactor = 1, this.height = 12});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: widthFactor,
      child: SkBox(height: height, radius: height / 2),
    ),
  );
}

// ── Per-screen moulds ────────────────────────────────────────────────────

/// Mould of the register home: name, verified-sales card, charge button and
/// the two shop tiles.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    // Scrollable so a RefreshIndicator can still be pulled while it shows.
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: SkLine(widthFactor: 0.72, height: 26)),
              const SizedBox(width: 10),
              SkBox(width: 62, height: 24, radius: 999),
            ],
          ),
          const SizedBox(height: 10),
          const SkLine(widthFactor: 0.46, height: 12),
          const SizedBox(height: 16),
          const SkBox(height: 132, radius: 20),
          const SizedBox(height: 14),
          const SkBox(height: 54),
          const SizedBox(height: 22),
          const SkLine(widthFactor: 0.28, height: 11),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(
                child: AspectRatio(aspectRatio: 1.32, child: SkBox(radius: 18)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: AspectRatio(aspectRatio: 1.32, child: SkBox(radius: 18)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Mould of the owner's shop list (the header and the create button are real
/// already, so this only stands in for the list itself).
class MisComerciosSkeleton extends StatelessWidget {
  const MisComerciosSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: 3,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => const SkBox(height: 132, radius: 20),
    ),
  );
}

/// Mould of the on-chain history: the totals strip and a run of sale rows.
class HistorialSkeleton extends StatelessWidget {
  const HistorialSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SkBox(height: 46),
        const SizedBox(height: 10),
        for (var i = 0; i < 6; i++) ...[
          const SkBox(height: 68, radius: 20),
          const SizedBox(height: 10),
        ],
      ],
    ),
  );
}

/// Mould of the reports screen: period filters, the takings card, the KPI
/// tiles, the daily chart and the export card.
class ReportesSkeleton extends StatelessWidget {
  const ReportesSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              const Expanded(child: SkBox(height: 36, radius: 999)),
              if (i < 3) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 16),
        const SkBox(height: 126, radius: 20),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(child: SkBox(height: 92, radius: 20)),
            SizedBox(width: 12),
            Expanded(child: SkBox(height: 92, radius: 20)),
          ],
        ),
        const SizedBox(height: 12),
        const SkBox(height: 112, radius: 20),
        const SizedBox(height: 18),
        const SkBox(height: 214, radius: 20),
        const SizedBox(height: 18),
        const SkBox(height: 128, radius: 20),
      ],
    ),
  );
}
