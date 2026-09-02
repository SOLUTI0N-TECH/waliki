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
    final id =
        '0x${List.generate(32, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
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
      appBar: WalikiBar(
        title: _phase == _Phase.entry ? 'Cobrar' : 'Cobro en curso',
        back: true,
      ),
      body: SafeArea(
        child: _phase == _Phase.entry ? _buildEntry() : _buildQr(),
      ),
    );
  }

  Widget _buildEntry() {
    final bs = _bs;
    final rate = _rate;
    final usdt = (bs != null && rate != null)
        ? BigInt.from((bs / rate * 1e6).round())
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: kSurface,
              border: Border.all(color: kLine),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Tasa  Bs',
                    style: wk(size: 13, weight: 500, color: kInkSoft)),
                SizedBox(
                  width: 62,
                  child: TextField(
                    controller: _rateCtrl,
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: wk(size: 14.5, weight: 700, tabular: true),
                    decoration: const InputDecoration(
                        isDense: true, border: InputBorder.none),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Text('= 1 USDT',
                    style: wk(size: 13, weight: 500, color: kInkSoft)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('MONTO EN BOLIVIANOS',
              style:
                  wk(size: 11, weight: 700, color: kInkSoft, tracking: 0.04)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Text('Bs ',
                    style: wk(size: 26, weight: 600, color: kInkSoft)),
              ),
              Text(_amount.isEmpty ? '0' : _amount, style: wkNum(size: 58)),
            ],
          ),
          const SizedBox(height: 4),
          Text(usdt != null ? '≈ ${fmtUsdt(usdt)} tUSDT' : ' ',
              style: wk(size: 16.5, weight: 700, color: kBrandInk, tabular: true)),
          const Spacer(),
          _AmountKeypad(onKey: _key),
          const SizedBox(height: 16),
          PrimaryButton('Cobrar — generar QR', onTap: usdt != null ? _cobrar : null),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          Text('Bs ${fmtNum(sale.bs)}', style: wkNum(size: 34)),
          Text('${fmtUsdt(sale.amountUnits)} tUSDT',
              style: wk(size: 15, weight: 700, color: kBrandInk, tabular: true)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: kLine),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1A0E1A15),
                    blurRadius: 24,
                    offset: Offset(0, 8)),
              ],
            ),
            child: QrImageView(data: url, size: 232),
          ),
          const SizedBox(height: 12),
          Text('El cliente escanea con su cámara — se abre la página de pago',
              textAlign: TextAlign.center,
              style: wk(size: 12.5, weight: 500, color: kInkSoft, height: 1.45)),
          const SizedBox(height: 14),
          WCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const _PulseDot(),
                const SizedBox(width: 11),
                Expanded(
                    child: Text('Esperando el pago…',
                        style: wk(size: 14.5, weight: 700))),
                expired
                    ? const WChip('cotización vencida',
                        bg: kDangerTint, fg: kDanger)
                    : WChip(
                        'vence en ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                        bg: kAmberTint,
                        fg: kAmber),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('El verde lo dispara el evento en la blockchain — no una captura.',
              textAlign: TextAlign.center,
              style: wk(size: 11.5, weight: 500, color: kInkSoft, height: 1.45)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text('QR → ${WalikiConfig.payBaseUrl}',
                    overflow: TextOverflow.ellipsis,
                    style: wk(size: 11, weight: 500, color: kInkSoft, mono: true)),
              ),
              IconButton(
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, color: kInkSoft),
                onPressed: _editBaseUrl,
              ),
            ],
          ),
          if (expired) ...[
            const SizedBox(height: 4),
            PrimaryButton('Generar un QR nuevo', onTap: _reset),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                foregroundColor: kDanger,
                side: const BorderSide(color: kLine, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Cancelar venta',
                  style: wk(size: 14.5, weight: 700, color: kDanger)),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kSuccessTop, kBrand, kSuccessBottom],
            stops: [0, 0.62, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.7, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Color(0x59000000),
                            blurRadius: 30,
                            offset: Offset(0, 10)),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 62, color: kBrand),
                  ),
                ),
                const SizedBox(height: 20),
                Text('¡Pago recibido!',
                    style: wk(size: 26, weight: 800, color: Colors.white, tracking: -0.03)),
                const SizedBox(height: 6),
                Text('Bs ${fmtNum(sale.bs)}',
                    style: wkNum(size: 46, color: Colors.white)),
                Text(
                    '${fmtUsdt(sale.amountUnits)} tUSDT · venta ${short(sale.id)}',
                    style: wk(
                        size: 13.5,
                        weight: 500,
                        color: Colors.white.withValues(alpha: 0.9))),
                if (_late) ...[
                  const SizedBox(height: 10),
                  WChip('pago fuera de plazo',
                      bg: Colors.white.withValues(alpha: 0.18), fg: Colors.white),
                ],
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _receiptRow('Pagó',
                          p != null ? short(p.payer) : 'verificado on-chain'),
                      const SizedBox(height: 9),
                      _receiptRow('Transacción',
                          p != null ? short(p.txHash) : 'confirmada'),
                      const SizedBox(height: 9),
                      _receiptRow(
                          'Bloque', p != null ? p.block.toString() : '—'),
                    ],
                  ),
                ),
                const Spacer(),
                PrimaryButton('Nueva venta',
                    color: Colors.white, fg: kBrandInk, onTap: _reset),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: wk(
                  size: 12.5,
                  weight: 500,
                  color: Colors.white.withValues(alpha: 0.78))),
          Text(value,
              style: wk(size: 13, weight: 600, color: Colors.white, mono: true)),
        ],
      );

  Future<void> _editBaseUrl() async {
    final ctrl = TextEditingController(text: WalikiConfig.payBaseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('URL de la página de pago',
            style: wk(size: 17, weight: 700)),
        content: TextField(
          controller: ctrl,
          style: wk(size: 14, weight: 500),
          decoration: const InputDecoration(
              hintText: 'http://192.168.x.x:5173 o https://waliki.vercel.app'),
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

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kBrand,
            boxShadow: [
              BoxShadow(
                color: kBrand.withValues(alpha: 0.22 - _c.value * 0.18),
                blurRadius: 0,
                spreadRadius: 3 + _c.value * 6,
              ),
            ],
          ),
        ),
      );
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
      childAspectRatio: 1.9,
      children: [
        for (final k in keys)
          Material(
            color: kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: const BorderSide(color: kLine),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () => onKey(k),
              child: Center(
                child: k == '<'
                    ? const Icon(Icons.backspace_outlined,
                        color: kInkSoft, size: 21)
                    : Text(k, style: wk(size: 23, weight: 600, tabular: true)),
              ),
            ),
          ),
      ],
    );
  }
}
