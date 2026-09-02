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
      appBar: const WalikiBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: FutureBuilder<String>(
                      future: _name,
                      builder: (context, snap) => Text(
                        snap.data ?? 'Cargando comercio…',
                        style: wk(size: 24, weight: 800, tracking: -0.03),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const WChip('Caja 1 · Cajero', bg: kSurface2, fg: kInkSoft),
                ],
              ),
              const SizedBox(height: 2),
              Text('Verificado en Base Sepolia',
                  style: wk(size: 12.5, weight: 500, color: kInkSoft)),
              const SizedBox(height: 16),
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
                        Text('VENTAS VERIFICADAS',
                            style: wk(
                                size: 11,
                                weight: 700,
                                color: kInkSoft,
                                tracking: 0.04)),
                        const SizedBox(height: 7),
                        Text(list == null ? '…' : '${fmtUsdt(total)} tUSDT',
                            style: wkNum(size: 33)),
                        const SizedBox(height: 5),
                        Row(children: [
                          const Icon(Icons.verified_rounded,
                              size: 15, color: kBrand),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              list == null
                                  ? 'consultando la cadena…'
                                  : '${list.length} pagos on-chain, auditables por cualquiera',
                              style: wk(size: 12.5, weight: 500, color: kInkSoft),
                            ),
                          ),
                        ]),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              PrimaryButton('Cobrar', onTap: () async {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CobrarScreen()));
                setState(_reload);
              }),
              const SizedBox(height: 22),
              Text('MÁS DE WALIKI',
                  style: wk(
                      size: 11, weight: 700, color: kInkSoft, tracking: 0.04)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.32,
                children: [
                  _ActionCard(
                    icon: Icons.receipt_long_rounded,
                    iconColor: kBrand,
                    title: 'Historial',
                    subtitle: 'Cada venta, verificada en la cadena',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const HistorialScreen())),
                  ),
                  _ActionCard(
                    icon: Icons.storefront_rounded,
                    iconColor: kViolet,
                    title: 'Tienda',
                    subtitle: 'Tus productos, pagados igual',
                    tag: 'Fase 3',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ComercioScreen())),
                  ),
                  _ActionCard(
                    icon: Icons.account_balance_wallet_rounded,
                    iconColor: kViolet,
                    title: 'Saldo y billetera',
                    subtitle: 'Compra saldo con QR o tarjeta',
                    tag: 'Fase 2',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ModoFacilScreen())),
                  ),
                  _ActionCard(
                    icon: Icons.trending_up_rounded,
                    iconColor: kViolet,
                    title: 'Puntaje',
                    subtitle: 'Tu historial vale: adelantos',
                    tag: 'Pronto',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PuntajeScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'Los fondos llegan directo a la wallet del dueño —\nWaliki nunca los toca.',
                  textAlign: TextAlign.center,
                  style: wk(size: 12, weight: 500, color: kInkSoft, height: 1.5),
                ),
              ),
            ],
          ),
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
      color: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: kLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: iconColor, size: 23),
                  if (tag != null)
                    WChip(tag!, bg: kVioletTint, fg: kViolet),
                ],
              ),
              const Spacer(),
              Text(title, style: wk(size: 14.5, weight: 700, tracking: -0.02)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: wk(size: 11, weight: 500, color: kInkSoft, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}
