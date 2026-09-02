import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../chain.dart';
import '../config.dart';
import '../ui.dart';

enum _Phase { entry, qr, paid }

class _Sale {
  final String id;
  final BigInt amountUnits;
  final double bs;
  final double rate;
  final int exp;
  const _Sale(this.id, this.amountUnits, this.bs, this.rate, this.exp);
}

/// The charge flow: amount in Bs -> QR -> green screen driven by the chain.
/// Read-only by design: the customer pays on the web page the QR opens.
class CobrarScreen extends StatefulWidget {
  const CobrarScreen({super.key});

  @override
  State<CobrarScreen> createState() => _CobrarScreenState();
}

class _CobrarScreenState extends State<CobrarScreen> {
  _Phase _phase = _Phase.entry;
  String _amount = '';
  final _rateCtrl = TextEditingController(text: '14.00');
  _Sale? _sale;
  Payment? _payment;
  bool _late = false;
  Timer? _clock;
  Timer? _poll;
  int _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void dispose() {
    _clock?.cancel();
    _poll?.cancel();
    _rateCtrl.dispose();
    super.dispose();
  }

  double? get _bs {
    final v = double.tryParse(_amount.replaceAll(',', '.'));
    return (v != null && v > 0) ? v : null;
  }

  double? get _rate {
    final v = double.tryParse(_rateCtrl.text.replaceAll(',', '.'));
    return (v != null && v > 0) ? v : null;
  }

  void _key(String k) {
    setState(() {
      if (k == '<') {
        if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
      } else if (k == ',') {
        if (!_amount.contains(',') && _amount.isNotEmpty) _amount += ',';
      } else if (_amount.length < 9) {
        _amount += k;
      }
    });
  }

  void _cobrar() {
    final bs = _bs;
    final rate = _rate;
    if (bs == null || rate == null) return;
    final rnd = Random.secure();
    final id = '0x${List.generate(32, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final units = BigInt.from((bs / rate * 1e6).round());
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        WalikiConfig.quoteMinutes * 60;
    _sale = _Sale(id, units, bs, rate, exp);
    _phase = _Phase.qr;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now().millisecondsSinceEpoch ~/ 1000);
    });
    // Green by polling paidAmount — same double-road philosophy as the web caja
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    setState(() {});
  }

  Future<void> _check() async {
    final sale = _sale;
    if (sale == null || _phase != _Phase.qr) return;
    try {
      final paid = await Chain.paidAmount(WalikiConfig.merchantId, sale.id);
      if (paid > BigInt.zero && mounted && _phase == _Phase.qr) {
        _late = DateTime.now().millisecondsSinceEpoch ~/ 1000 > sale.exp;
        _phase = _Phase.paid;
        _poll?.cancel();
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        setState(() {});
        // Backfill payer/tx from the event log (best-effort)
        try {
          final logs = await Chain.payments(saleId: sale.id);
          if (logs.isNotEmpty && mounted) setState(() => _payment = logs.first);
        } catch (_) {
          // details are optional; the green screen never waits for them
        }
      }
    } catch (_) {
      // transient RPC errors: keep polling
    }
  }

  void _reset() {
    _clock?.cancel();
    _poll?.cancel();
    setState(() {
      _phase = _Phase.entry;
      _amount = '';
      _sale = null;
      _payment = null;
      _late = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.paid) return _buildPaid();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const TestnetBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_phase == _Phase.entry ? 'Cobrar' : 'Cobro en curso',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const Text('Caja 1 · Tienda Demo CBBA',
                          style: TextStyle(color: kMuted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
                child: _phase == _Phase.entry ? _buildEntry() : _buildQr()),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry() {
    final bs = _bs;
    final rate = _rate;
    final usdt =
        (bs != null && rate != null) ? BigInt.from((bs / rate * 1e6).round()) : null;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Tasa: Bs ', style: TextStyle(color: kMuted, fontSize: 13)),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _rateCtrl,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const Text(' = 1 USDT', style: TextStyle(color: kMuted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 18),
          const Text('MONTO EN BOLIVIANOS',
              style: TextStyle(
                  color: kMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Bs ',
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w600, color: kMuted)),
              ),
              Text(_amount.isEmpty ? '0' : _amount,
                  style: const TextStyle(
                      fontSize: 56, fontWeight: FontWeight.w700, letterSpacing: -2)),
            ],
          ),
          Text(usdt != null ? '≈ ${fmtUsdt(usdt)} tUSDT' : ' ',
              style: const TextStyle(
                  color: kGreen, fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          _AmountKeypad(onKey: _key),
          const SizedBox(height: 14),
          PrimaryButton('GENERAR QR DE COBRO',
              onTap: usdt != null ? _cobrar : null),
        ],
      ),
    );
  }

  Widget _buildQr() {
    final sale = _sale!;
    final expired = _now >= sale.exp;
    final left = (sale.exp - _now).clamp(0, 1 << 31);
    final bsParam = sale.bs.toStringAsFixed(2);
    final url =
        '${WalikiConfig.payBaseUrl}/pay/${sale.id}?m=${WalikiConfig.merchantId}&a=${sale.amountUnits}&bs=$bsParam&r=${sale.rate.toStringAsFixed(2)}&exp=${sale.exp}';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('Bs ${fmtNum(sale.bs)} · ${fmtUsdt(sale.amountUnits)} tUSDT',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: kLine),
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(data: url, size: 244),
          ),
          const SizedBox(height: 8),
          const Text('El cliente escanea con su cámara — se abre la página de pago',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 12),
          WCard(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: kGreen),
                ),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('Esperando el pago…',
                        style: TextStyle(fontWeight: FontWeight.w700))),
                expired
                    ? WChip('cotización vencida',
                        bg: const Color(0xFFFDECEC), fg: kRed)
                    : WChip(
                        'vence en ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                        bg: kAmberBg,
                        fg: kAmber),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('El verde lo dispara el evento en la blockchain — no una captura.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, fontSize: 11)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text('QR → ${WalikiConfig.payBaseUrl}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMuted, fontSize: 11)),
              ),
              IconButton(
                iconSize: 16,
                icon: const Icon(Icons.edit, color: kMuted),
                onPressed: _editBaseUrl,
              ),
            ],
          ),
          if (expired) ...[
            const SizedBox(height: 6),
            PrimaryButton('Generar un QR nuevo', onTap: _reset),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                foregroundColor: kRed,
                side: const BorderSide(color: Color(0xFFE4C7C7), width: 1.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Cancelar venta',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaid() {
    final sale = _sale!;
    final p = _payment;
    return Scaffold(
      backgroundColor: kGreenBright,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white),
                child: const Icon(Icons.check, size: 64, color: kGreenBright),
              ),
              const SizedBox(height: 18),
              const Text('¡Pago recibido!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Bs ${fmtNum(sale.bs)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1)),
              Text('${fmtUsdt(sale.amountUnits)} tUSDT · venta ${short(sale.id)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              if (_late) ...[
                const SizedBox(height: 8),
                WChip('pago fuera de plazo (cotización vencida)',
                    bg: Colors.white24, fg: Colors.white),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _receiptRow('Pagó', p != null ? short(p.payer) : 'verificado on-chain'),
                    const SizedBox(height: 8),
                    _receiptRow('Transacción', p != null ? short(p.txHash) : 'confirmada'),
                    const SizedBox(height: 8),
                    _receiptRow('Bloque', p != null ? p.block.toString() : '—'),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryButton('NUEVA VENTA',
                  color: Colors.white, fg: const Color(0xFF0B7D4A), onTap: _reset),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      );

  Future<void> _editBaseUrl() async {
    final ctrl = TextEditingController(text: WalikiConfig.payBaseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('URL de la página de pago'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              hintText: 'http://192.168.0.X:5173 o https://waliki.vercel.app'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) {
      setState(() => WalikiConfig.payBaseUrl = value);
    }
  }
}

class _AmountKeypad extends StatelessWidget {
  final void Function(String) onKey;
  const _AmountKeypad({required this.onKey});

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '0', '<'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.85,
      children: [
        for (final k in keys)
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: kLine),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onKey(k),
              child: Center(
                child: k == '<'
                    ? const Icon(Icons.backspace_outlined, color: kMuted)
                    : Text(k,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ],
    );
  }
}
