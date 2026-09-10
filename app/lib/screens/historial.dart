import 'package:flutter/material.dart';

import '../chain.dart';
import '../ui.dart';
import '../skeletons.dart';

class HistorialScreen extends StatefulWidget {
  final int merchantId;
  const HistorialScreen({super.key, required this.merchantId});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  late Future<List<Payment>> _future;

  @override
  void initState() {
    super.initState();
    _future = Chain.payments(merchantId: widget.merchantId);
  }

  /// Pull to refresh; the builder below renders any failure on its own.
  Future<void> _refresh() async {
    setState(() => _future = Chain.payments(merchantId: widget.merchantId));
    await _future.catchError((Object _) => <Payment>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WalikiBar(title: 'Historial', back: true),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text(
                'Leído directamente de la blockchain — contabilidad que no depende de confiar en nadie.',
                style: wk(
                  size: 12.5,
                  weight: 500,
                  color: kInkSoft,
                  height: 1.45,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: kBrand,
                child: FutureBuilder<List<Payment>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return ScrollableCenter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Sin conexión con la cadena\nDesliza hacia abajo para reintentar',
                            textAlign: TextAlign.center,
                            style: wk(size: 13, weight: 500, color: kInkSoft),
                          ),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const HistorialSkeleton();
                    }
                    final list = snap.data!.reversed.toList();
                    if (list.isEmpty) {
                      return ScrollableCenter(
                        child: Text(
                          'Todavía no hay ventas',
                          style: wk(size: 14, weight: 500, color: kInkSoft),
                        ),
                      );
                    }
                    final total = list.fold<BigInt>(
                      BigInt.zero,
                      (a, p) => a + p.amount,
                    );
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: kBrandTint,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '${list.length} ventas · ${fmtUsdt(total)} tUSDT',
                            style: wk(
                              size: 14,
                              weight: 700,
                              color: kBrandInk,
                              tabular: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final p in list) ...[
                          WCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${fmtUsdt(p.amount)} tUSDT',
                                        style: wk(
                                          size: 15.5,
                                          weight: 700,
                                          tabular: true,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'de ${short(p.payer)} · bloque ${p.block}',
                                        style: wk(
                                          size: 11,
                                          weight: 500,
                                          color: kInkSoft,
                                          mono: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const WChip('Verificada'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
