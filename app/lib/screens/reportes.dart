import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chain.dart';
import '../session.dart';
import '../ui.dart';
import 'historial.dart';
import '../skeletons.dart';

enum _Period { hoy, semana, mes, todo }

const _periodLabel = {
  _Period.hoy: 'Hoy',
  _Period.semana: '7 días',
  _Period.mes: '30 días',
  _Period.todo: 'Todo',
};

const _meses = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fecha(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

String _hora(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Register labels are typed by the owner, so a comma or a quote in one would
/// quietly shift every column to its right.
String _csv(String value) => value.contains(',') || value.contains('"')
    ? '"${value.replaceAll('"', '""')}"'
    : value;

/// Sales reporting, built entirely from on-chain events. This is the
/// "contabilidad automática" pillar: numbers nobody can edit, exportable.
class ReportesScreen extends StatefulWidget {
  final Session session;
  final int merchantId;
  const ReportesScreen({
    super.key,
    required this.session,
    required this.merchantId,
  });

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  late Future<List<Payment>> _future;
  _Period _period = _Period.semana;
  int? _selectedBar;

  /// Register labels, keyed by address. Best-effort: they live only in the
  /// event log, so a refused window costs a name, never a figure. Everything
  /// falls back to the short address.
  Map<String, String> _labels = const {};

  /// On a cashier's phone the useful default is their own takings — that is
  /// what they count at the end of a shift. The owner sees everything.
  late bool _soloMias = widget.session.role == Role.cajero;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadLabels();
  }

  void _reload() {
    _future = Chain.paymentsWithTime(merchantId: widget.merchantId);
  }

  Future<void> _loadLabels() async {
    try {
      final cashiers = await Chain.cashiers(widget.merchantId);
      if (!mounted) return;
      setState(() {
        _labels = {
          for (final c in cashiers)
            if (c.label.isNotEmpty) c.address: c.label,
        };
      });
    } catch (_) {
      // names are a nicety; the report never waits for them
    }
  }

  String _nombreCajero(String address) =>
      _labels[address] ?? 'Caja ${short(address)}';

  /// Pull to refresh; the builder below renders any failure on its own.
  Future<void> _refresh() async {
    setState(_reload);
    await _future.catchError((Object _) => <Payment>[]);
  }

  double get _rate {
    final v = double.tryParse(widget.session.rate.replaceAll(',', '.'));
    return (v != null && v > 0) ? v : 14.0;
  }

  DateTime? get _since {
    final now = DateTime.now();
    return switch (_period) {
      _Period.hoy => DateTime(now.year, now.month, now.day),
      _Period.semana => now.subtract(const Duration(days: 7)),
      _Period.mes => now.subtract(const Duration(days: 30)),
      _Period.todo => null,
    };
  }

  /// Everything this screen is currently about, before the period filter.
  List<Payment> _visible(List<Payment> all) {
    final mine = _soloMias
        ? widget.session.cashierAddress?.toLowerCase()
        : null;
    if (mine == null) return all;
    return all.where((p) => p.cashier == mine).toList();
  }

  List<Payment> _filter(List<Payment> all) {
    final since = _since;
    final mine = _soloMias
        ? widget.session.cashierAddress?.toLowerCase()
        : null;
    return all.where((p) {
      if (mine != null && p.cashier != mine) return false;
      if (since == null) return true;
      final d = p.date;
      return d != null && d.isAfter(since);
    }).toList();
  }

  /// The chain stores USDT, never bolivianos, so the Bs column is a
  /// reconstruction at the rate showing today — not the price the customer
  /// was actually charged. The header says so.
  Future<void> _exportCsv(List<Payment> rows) async {
    final buf = StringBuffer(
      'fecha,hora,venta,monto_usdt,monto_bs_estimado,pagador,'
      'cajero,cajero_etiqueta,bloque,transaccion\n',
    );
    for (final p in rows.reversed) {
      final d = p.date;
      final usdt = p.amount.toDouble() / 1e6;
      buf.writeln(
        [
          d == null ? '' : _dayKey(d),
          d == null ? '' : _hora(d),
          p.saleId,
          usdt.toStringAsFixed(2),
          (usdt * _rate).toStringAsFixed(2),
          p.payer,
          p.cashier,
          _csv(_labels[p.cashier] ?? ''),
          p.block.toString(),
          p.txHash,
        ].join(','),
      );
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${rows.length} ventas copiadas en formato CSV — '
          'pégalas en Excel o Google Sheets',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WalikiBar(title: 'Reportes', back: true),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: kBrand,
          child: FutureBuilder<List<Payment>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return ScrollableCenter(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Sin conexión con la cadena\nDesliza hacia abajo para reintentar',
                      textAlign: TextAlign.center,
                      style: wk(size: 13, weight: 500, color: kInkSoft),
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return const ReportesSkeleton();
              }
              final all = _visible(snap.data!);
              final rows = _filter(snap.data!);
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  if (widget.session.cashierAddress != null) ...[
                    _scopeToggle(),
                    const SizedBox(height: 10),
                  ],
                  _filters(),
                  const SizedBox(height: 16),
                  _kpis(rows),
                  const SizedBox(height: 18),
                  _chart(all),
                  const SizedBox(height: 18),
                  if (!_soloMias) ...[
                    _porCajero(rows),
                    const SizedBox(height: 18),
                  ],
                  _exportCard(rows),
                  const SizedBox(height: 14),
                  Text(
                    'Cada cifra sale de los eventos del contrato en la blockchain. '
                    'Nadie —ni Waliki— puede editarlas.',
                    textAlign: TextAlign.center,
                    style: wk(
                      size: 11.5,
                      weight: 500,
                      color: kInkSoft,
                      height: 1.5,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _scopeToggle() => Row(
    children: [
      for (final mine in [true, false]) ...[
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _soloMias = mine),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _soloMias == mine ? kBrandTint : kSurface,
                border: Border.all(color: _soloMias == mine ? kBrand : kLine),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                mine ? 'Mis ventas' : 'Todo el comercio',
                style: wk(
                  size: 12.5,
                  weight: 700,
                  color: _soloMias == mine ? kBrandInk : kInkSoft,
                ),
              ),
            ),
          ),
        ),
        if (mine) const SizedBox(width: 8),
      ],
    ],
  );

  /// Who took the money. The whole point of putting cashiers on-chain: the
  /// attribution comes from the sale id the router validated, so nobody —
  /// including whoever runs this app — can move a sale from one register to
  /// another after the fact.
  Widget _porCajero(List<Payment> rows) {
    final totals = <String, BigInt>{};
    final counts = <String, int>{};
    for (final p in rows) {
      totals[p.cashier] = (totals[p.cashier] ?? BigInt.zero) + p.amount;
      counts[p.cashier] = (counts[p.cashier] ?? 0) + 1;
    }
    if (totals.isEmpty) return const SizedBox.shrink();

    final ordered = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    final top = totals[ordered.first]!.toDouble();

    return WCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Por cajero', style: wk(size: 14, weight: 700)),
          const SizedBox(height: 4),
          Text(
            'Cada venta queda firmada con la caja que la emitió.',
            style: wk(size: 11.5, weight: 500, color: kInkSoft),
          ),
          const SizedBox(height: 12),
          for (final address in ordered) ...[
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HistorialScreen(
                    merchantId: widget.merchantId,
                    cashier: address,
                    titulo: _nombreCajero(address),
                  ),
                ),
              ),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _nombreCajero(address),
                            style: wk(size: 13, weight: 600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${fmtUsdt(totals[address]!)} tUSDT',
                          style: wk(size: 13, weight: 700, tabular: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: top == 0 ? 0 : totals[address]!.toDouble() / top,
                        minHeight: 7,
                        backgroundColor: kSurface2,
                        valueColor: const AlwaysStoppedAnimation(kBrand),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${counts[address]} ${counts[address] == 1 ? 'venta' : 'ventas'}',
                      style: wk(size: 11.5, weight: 500, color: kInkSoft),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filters() => Row(
    children: [
      for (final p in _Period.values) ...[
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _period = p),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _period == p ? kBrand : kSurface,
                border: Border.all(color: _period == p ? kBrand : kLine),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _periodLabel[p]!,
                style: wk(
                  size: 12.5,
                  weight: 700,
                  color: _period == p ? Colors.white : kInkSoft,
                ),
              ),
            ),
          ),
        ),
        if (p != _Period.todo) const SizedBox(width: 8),
      ],
    ],
  );

  Widget _kpis(List<Payment> rows) {
    final totalUnits = rows.fold<BigInt>(BigInt.zero, (a, p) => a + p.amount);
    final total = totalUnits.toDouble() / 1e6;
    final avg = rows.isEmpty ? 0.0 : total / rows.length;
    final payers = rows.map((p) => p.payer.toLowerCase()).toSet().length;

    return Column(
      children: [
        WCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'COBRADO · ${_periodLabel[_period]!.toUpperCase()}',
                style: wk(
                  size: 11,
                  weight: 700,
                  color: kInkSoft,
                  tracking: 0.05,
                ),
              ),
              const SizedBox(height: 7),
              Text('${fmtNum(total)} tUSDT', style: wkNum(size: 34)),
              const SizedBox(height: 3),
              Text(
                '≈ Bs ${fmtNum(total * _rate)}  ·  al cambio de hoy, ${_rate.toStringAsFixed(2)}',
                style: wk(size: 12.5, weight: 500, color: kInkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _tile(
                'Ventas',
                '${rows.length}',
                Icons.receipt_long_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _tile(
                'Ticket promedio',
                fmtNum(avg),
                Icons.trending_up_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _tile(
          'Pagadores distintos',
          '$payers',
          Icons.groups_rounded,
          note: 'Un historial sano tiene muchos pagadores, no uno solo.',
        ),
      ],
    );
  }

  Widget _tile(String label, String value, IconData icon, {String? note}) =>
      WCard(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: kBrand),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    style: wk(size: 12, weight: 600, color: kInkSoft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: wkNum(size: 24)),
            if (note != null) ...[
              const SizedBox(height: 5),
              Text(
                note,
                style: wk(size: 11, weight: 500, color: kInkSoft, height: 1.4),
              ),
            ],
          ],
        ),
      );

  /// Daily totals for a fixed 14-day window — labelled independently of the
  /// filter above so the axis never changes meaning under the reader.
  Widget _chart(List<Payment> all) {
    const days = 14;
    final today = DateTime.now();
    final buckets = <String, double>{};
    final labels = <DateTime>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: i));
      labels.add(d);
      buckets[_dayKey(d)] = 0;
    }
    for (final p in all) {
      final d = p.date;
      if (d == null) continue;
      final k = _dayKey(d);
      if (buckets.containsKey(k)) {
        buckets[k] = buckets[k]! + p.amount.toDouble() / 1e6;
      }
    }
    final values = labels.map((d) => buckets[_dayKey(d)]!).toList();
    final maxV = values.fold<double>(0, (a, b) => b > a ? b : a);

    return WCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ventas por día · últimos 14 días',
            style: wk(size: 14, weight: 700, tracking: -0.02),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedBar == null
                ? (maxV == 0
                      ? 'Sin ventas en este período'
                      : 'Toca una barra para ver el detalle')
                : '${_fecha(labels[_selectedBar!])} · ${fmtNum(values[_selectedBar!])} tUSDT',
            style: wk(size: 12, weight: 600, color: kInkSoft),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 2,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(
                        () => _selectedBar = _selectedBar == i ? null : i,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: maxV == 0
                                ? 2
                                : (values[i] / maxV * 84).clamp(2, 84),
                            decoration: BoxDecoration(
                              color: values[i] == 0
                                  ? kLine
                                  : (_selectedBar == i ? kBrandInk : kBrand),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: kLine,
            margin: const EdgeInsets.only(top: 4),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fecha(labels.first),
                style: wk(size: 10.5, weight: 500, color: kInkSoft),
              ),
              Text(
                _fecha(labels[days ~/ 2]),
                style: wk(size: 10.5, weight: 500, color: kInkSoft),
              ),
              Text('hoy', style: wk(size: 10.5, weight: 600, color: kInkSoft)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _exportCard(List<Payment> rows) => WCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.table_chart_rounded, size: 18, color: kBrand),
            const SizedBox(width: 8),
            Text('Exportar contabilidad', style: wk(size: 14, weight: 700)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Copia las ${rows.length} ventas del período en formato CSV, con su '
          'fecha, monto en Bs y USDT, pagador y número de transacción.',
          style: wk(size: 12.5, weight: 500, color: kInkSoft, height: 1.5),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            onPressed: rows.isEmpty ? null : () => _exportCsv(rows),
            icon: const Icon(Icons.copy_rounded, size: 17),
            label: Text(
              'Copiar CSV',
              style: wk(size: 14, weight: 700, color: kBrandInk),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: kBrandInk,
              side: const BorderSide(color: kBrand, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
