import 'package:flutter/material.dart';

// Waliki palette (same tokens as the design canvas and the web)
const kGreen = Color(0xFF0C8A56);
const kGreenBright = Color(0xFF0EA05C);
const kGreenDark = Color(0xFF0B3B27);
const kInk = Color(0xFF15201B);
const kMuted = Color(0xFF5C6B63);
const kBg = Color(0xFFF6F7F5);
const kLine = Color(0xFFE4E8E4);
const kAmber = Color(0xFFB45309);
const kAmberBg = Color(0xFFFBF3E8);
const kViolet = Color(0xFF6D28D9);
const kRed = Color(0xFFDC2626);

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

class TestnetBanner extends StatelessWidget {
  const TestnetBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: kAmber,
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        child: const Text(
          'MODO PRUEBA · BASE SEPOLIA — LOS FONDOS NO SON REALES',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
}

class ConceptBanner extends StatelessWidget {
  final String label;
  const ConceptBanner(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: kViolet,
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
}

class WCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const WCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );
}

class WChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const WChip(this.text, {super.key, this.bg = const Color(0xFFEAF3EE), this.fg = const Color(0xFF0B7D4A)});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color fg;
  const PrimaryButton(this.label, {super.key, this.onTap, this.color = kGreen, this.fg = Colors.white});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 58,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: fg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.6),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      );
}
