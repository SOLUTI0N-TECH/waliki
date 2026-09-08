import 'package:flutter/material.dart';

import '../session.dart';
import '../ui.dart';
import 'cajero_setup.dart';
import 'conectar.dart';

/// First run: pick a role. The whole product splits in two here — the owner
/// signs and administers, the cashier only charges and verifies.
class WelcomeScreen extends StatelessWidget {
  final Session session;
  const WelcomeScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WalikiBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('waliki',
                  textAlign: TextAlign.center,
                  style: wk(
                      size: 44,
                      weight: 800,
                      color: kBrandInk,
                      tracking: -0.035)),
              const SizedBox(height: 6),
              Text('Cobra en USDT, sin custodios',
                  textAlign: TextAlign.center,
                  style: wk(size: 15, weight: 600, color: kInkSoft)),
              const SizedBox(height: 20),
              Text(
                'El pago viaja directo de la billetera del cliente a la del comercio. '
                'Waliki solo lee la blockchain para confirmarlo — nunca toca el dinero.',
                textAlign: TextAlign.center,
                style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
              ),
              const SizedBox(height: 28),
              Text('¿CÓMO VAS A USAR WALIKI?',
                  textAlign: TextAlign.center,
                  style: wk(
                      size: 11, weight: 700, color: kInkSoft, tracking: 0.05)),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.storefront_rounded,
                title: 'Soy el dueño',
                subtitle:
                    'Registro mi comercio, vinculo cajeros y veo mis reportes.',
                note: 'Conectas tu billetera',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ConectarScreen(session: session))),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.point_of_sale_rounded,
                title: 'Soy cajero',
                subtitle:
                    'Cobro y verifico pagos con el código que me dio el dueño.',
                note: 'Sin billetera, solo un PIN',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CajeroSetupScreen(session: session))),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 14, color: kInkSoft),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Waliki nunca guarda tus llaves ni tus fondos.',
                      style: wk(size: 12, weight: 500, color: kInkSoft),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String note;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.note,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kBrandTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: kBrand, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: wk(size: 17, weight: 700, tracking: -0.02)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: wk(
                            size: 12.5,
                            weight: 500,
                            color: kInkSoft,
                            height: 1.4)),
                    const SizedBox(height: 8),
                    WChip(note, bg: kSurface2, fg: kInkSoft),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kInkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
