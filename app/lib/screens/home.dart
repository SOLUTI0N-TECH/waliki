import 'package:flutter/material.dart';

import '../chain.dart';
import '../config.dart';
import '../session.dart';
import '../ui.dart';
import '../skeletons.dart';
import '../wallet.dart';
import 'cobrar.dart';
import 'concepto.dart';
import 'historial.dart';
import 'reportes.dart';
import 'cajeros.dart';
import 'welcome.dart';

class HomeScreen extends StatefulWidget {
  final Session session;
  final int merchantId;
  const HomeScreen({
    super.key,
    required this.session,
    required this.merchantId,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Merchant> _merchant;
  late Future<List<Payment>> _payments;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _merchant = Chain.merchant(widget.merchantId);
    _payments = Chain.payments(merchantId: widget.merchantId);
  }

  /// Pull to refresh. Errors are swallowed here on purpose: each builder below
  /// renders its own failure, and this await only holds the spinner until the
  /// reads settle.
  Future<void> _refresh() async {
    setState(_reload);
    await Future.wait<dynamic>([_merchant, _payments])
        .catchError((Object _) => <dynamic>[]);
  }

  Future<void> _menu(String value) async {
    switch (value) {
      case 'cajeros':
        final m = await _merchant;
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CajerosScreen(session: widget.session, merchant: m),
          ),
        );
      case 'salir':
        // No-op for a cashier: that role never connects a wallet.
        await Wallet.instance.disconnect();
        await widget.session.clear();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => WelcomeScreen(session: widget.session),
          ),
          (route) => false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esDuenio = widget.session.role == Role.duenio;
    return Scaffold(
      appBar: WalikiBar(
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              size: 20,
              color: kInkSoft,
            ),
            onSelected: _menu,
            itemBuilder: (context) => [
              if (esDuenio)
                PopupMenuItem(
                  value: 'cajeros',
                  child: Text('Cajeros', style: wk(size: 14, weight: 600)),
                ),
              PopupMenuItem(
                value: 'salir',
                child: Text(
                  esDuenio ? 'Desconectar' : 'Desvincular caja',
                  style: wk(size: 14, weight: 600),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: kBrand,
          child: FutureBuilder<Merchant>(
            future: _merchant,
            builder: (context, mSnap) {
              // The shop name is one eth_call: show the page's own shape until
              // it lands, then let the slower log scan fill the card below.
              if (!mSnap.hasData && !mSnap.hasError) {
                return const HomeSkeleton();
              }
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            // mSnap already resolved (data or error), so there is
                            // no "loading" case left to render here.
                            mSnap.data?.displayName ??
                                'Comercio #${widget.merchantId}',
                            style: wk(size: 24, weight: 800, tracking: -0.03),
                          ),
                        ),
                        const SizedBox(width: 10),
                        WChip(
                          esDuenio ? 'Dueño' : 'Cajero',
                          bg: kSurface2,
                          fg: kInkSoft,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Verificado en la blockchain',
                      style: wk(size: 12.5, weight: 500, color: kInkSoft),
                    ),
                    const SizedBox(height: 16),
                    WCard(
                      child: FutureBuilder<List<Payment>>(
                        future: _payments,
                        builder: (context, snap) {
                          final list = snap.data;
                          final failed = snap.hasError;
                          final total =
                              list?.fold<BigInt>(
                                BigInt.zero,
                                (a, p) => a + p.amount,
                              ) ??
                              BigInt.zero;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VENTAS VERIFICADAS',
                                style: wk(
                                  size: 11,
                                  weight: 700,
                                  color: kInkSoft,
                                  tracking: 0.04,
                                ),
                              ),
                              const SizedBox(height: 7),
                              if (failed)
                                Text(
                                  '—',
                                  style: wkNum(size: 33, color: kInkSoft),
                                )
                              else if (list == null)
                                const Shimmer(
                                  child: SkLine(widthFactor: 0.62, height: 30),
                                )
                              else
                                Text(
                                  '${fmtUsdt(total)} tUSDT',
                                  style: wkNum(size: 33),
                                ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Icon(
                                    failed
                                        ? Icons.cloud_off_rounded
                                        : Icons.verified_rounded,
                                    size: 15,
                                    color: failed ? kAmber : kBrand,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      failed
                                          ? 'Sin conexión con la cadena — desliza hacia abajo para reintentar'
                                          : list == null
                                          ? 'consultando la cadena…'
                                          : '${list.length} pagos on-chain, auditables por cualquiera',
                                      style: wk(
                                        size: 12.5,
                                        weight: 500,
                                        color: kInkSoft,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(
                      'Cobrar',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CobrarScreen(
                              session: widget.session,
                              merchantId: widget.merchantId,
                            ),
                          ),
                        );
                        setState(_reload);
                      },
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'TU COMERCIO',
                      style: wk(
                        size: 11,
                        weight: 700,
                        color: kInkSoft,
                        tracking: 0.04,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // A grid (not a Row): _ActionCard uses a Spacer, which needs a
                    // bounded height. Inside a scroll view a Row leaves the height
                    // unbounded and layout throws.
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
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => HistorialScreen(
                                merchantId: widget.merchantId,
                              ),
                            ),
                          ),
                        ),
                        _ActionCard(
                          icon: Icons.insights_rounded,
                          iconColor: kBrand,
                          title: 'Reportes',
                          subtitle: 'Totales, ticket promedio y CSV',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReportesScreen(
                                session: widget.session,
                                merchantId: widget.merchantId,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (WalikiConfig.showVision) ...[
                      const SizedBox(height: 22),
                      Text(
                        'WALIKI COMPLETO',
                        style: wk(
                          size: 11,
                          weight: 700,
                          color: kInkSoft,
                          tracking: 0.04,
                        ),
                      ),
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
                            icon: Icons.account_balance_wallet_rounded,
                            iconColor: kConcept,
                            title: 'Saldo y billetera',
                            subtitle: 'Compra saldo con QR o tarjeta',
                            tag: 'Fase 2',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ModoFacilScreen(),
                              ),
                            ),
                          ),
                          _ActionCard(
                            icon: Icons.storefront_rounded,
                            iconColor: kConcept,
                            title: 'Tienda',
                            subtitle: 'Tus productos, pagados igual',
                            tag: 'Fase 3',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ComercioScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ActionCard(
                        icon: Icons.trending_up_rounded,
                        iconColor: kConcept,
                        title: 'Puntaje comercial',
                        subtitle: 'Tu historial de ventas te abre la puerta a un adelanto',
                        tag: 'Pronto',
                        wide: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PuntajeScreen(),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        'Los fondos llegan directo a la wallet del dueño —\nWaliki nunca los toca.',
                        textAlign: TextAlign.center,
                        style: wk(
                          size: 12,
                          weight: 500,
                          color: kInkSoft,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
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
  final bool wide;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
    this.wide = false,
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
          child: wide
              ? Row(
                  children: [
                    Icon(icon, color: iconColor, size: 23),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: wk(size: 14.5, weight: 700, tracking: -0.02),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: wk(
                              size: 11,
                              weight: 500,
                              color: kInkSoft,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tag != null)
                      WChip(tag!, bg: kConceptTint, fg: kConcept),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(icon, color: iconColor, size: 23),
                        if (tag != null)
                          WChip(tag!, bg: kConceptTint, fg: kConcept),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      title,
                      style: wk(size: 14.5, weight: 700, tracking: -0.02),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: wk(
                        size: 11,
                        weight: 500,
                        color: kInkSoft,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
