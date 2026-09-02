import 'package:flutter/material.dart';

import '../chain.dart';
import '../ui.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  late Future<List<Payment>> _future;

  @override
  void initState() {
    super.initState();
    _future = Chain.payments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: kBg,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = Chain.payments()),
          ),
        ],
      ),
      body: Column(
        children: [
          const TestnetBanner(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              'Leído directamente de la blockchain — contabilidad que no depende de confiar en nadie.',
              style: TextStyle(color: kMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Payment>>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                      child: Text('Sin conexión con la cadena\n${snap.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kMuted)));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snap.data!.reversed.toList();
                if (list.isEmpty) {
                  return const Center(
                      child: Text('Todavía no hay ventas',
                          style: TextStyle(color: kMuted)));
                }
                final total =
                    list.fold<BigInt>(BigInt.zero, (a, p) => a + p.amount);
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3EE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${list.length} ventas · ${fmtUsdt(total)} tUSDT',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: kGreenDark),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final p in list) ...[
                      WCard(
                        padding: const EdgeInsets.all(13),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${fmtUsdt(p.amount)} tUSDT',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    'de ${short(p.payer)} · bloque ${p.block} · tx ${short(p.txHash)}',
                                    style: const TextStyle(
                                        color: kMuted, fontSize: 11),
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
        ],
      ),
    );
  }
}
