import 'package:flutter/material.dart';

import '../chain.dart';
import '../config.dart';
import '../ui.dart';
import 'cobrar.dart';
import 'concepto.dart';
import 'historial.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<String> _name;
  late Future<List<Payment>> _payments;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _name = Chain.merchantName(WalikiConfig.merchantId);
    _payments = Chain.payments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const TestnetBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('waliki',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: kGreenDark,
                                letterSpacing: -0.5)),
                        WChip('Caja 1 · Cajero',
                            bg: Colors.white, fg: kMuted),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<String>(
                      future: _name,
                      builder: (context, snap) => Text(
                        snap.data ?? 'Cargando comercio…',
                        style: const TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Text('leído de la blockchain · Base Sepolia',
                        style: TextStyle(color: kMuted, fontSize: 12)),
                    const SizedBox(height: 14),
                    WCard(
                      child: FutureBuilder<List<Payment>>(
                        future: _payments,
                        builder: (context, snap) {
                          final list = snap.data;
                          final total = list?.fold<BigInt>(
                                  BigInt.zero, (a, p) => a + p.amount) ??
                              BigInt.zero;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('VENTAS VERIFICADAS',
                                  style: TextStyle(
                                      color: kMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5)),
                              const SizedBox(height: 6),
                              Text(
                                list == null
                                    ? '…'
                                    : '${fmtUsdt(total)} tUSDT',
                                style: const TextStyle(
                                    fontSize: 32, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.check_circle,
                                    size: 15, color: kGreen),
                                const SizedBox(width: 5),
                                Text(
                                  list == null
                                      ? 'consultando la cadena…'
                                      : '${list.length} pagos on-chain, auditables por cualquiera',
                                  style: const TextStyle(
                                      color: kMuted, fontSize: 12),
                                ),
                              ]),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton('COBRAR', onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const CobrarScreen()));
                      setState(_reload);
                    }),
                    const SizedBox(height: 18),
                    const Text('MÁS DE WALIKI',
                        style: TextStyle(
                            color: kMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                      children: [
                        _ActionCard(
                          icon: Icons.history,
                          iconColor: kGreen,
                          title: 'Historial',
                          subtitle: 'Cada venta, verificada en la cadena',
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const HistorialScreen())),
                        ),
                        _ActionCard(
                          icon: Icons.storefront_outlined,
                          iconColor: kViolet,
                          title: 'Tienda',
                          subtitle: 'Tus productos, pagados igual',
                          tag: 'FASE 3',
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ComercioScreen())),
                        ),
                        _ActionCard(
                          icon: Icons.account_balance_wallet_outlined,
                          iconColor: kViolet,
                          title: 'Saldo y billetera',
                          subtitle: 'Compra saldo con QR o tarjeta',
                          tag: 'FASE 2',
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ModoFacilScreen())),
                        ),
                        _ActionCard(
                          icon: Icons.star_border,
                          iconColor: kViolet,
                          title: 'Puntaje',
                          subtitle: 'Tu historial vale: adelantos',
                          tag: 'PRONTO',
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const PuntajeScreen())),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Los fondos llegan directo a la wallet del dueño —\nWaliki nunca los toca.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kMuted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? tag;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: iconColor, size: 24),
                  if (tag != null)
                    WChip(tag!, bg: const Color(0xFFF1EBFC), fg: kViolet),
                ],
              ),
              const Spacer(),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kMuted, fontSize: 10.5)),
            ],
          ),
        ),
      ),
    );
  }
}
