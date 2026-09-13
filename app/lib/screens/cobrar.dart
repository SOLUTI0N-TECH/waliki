import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../chain.dart';
import '../charge_amounts.dart';
import '../config.dart';
import '../qr_service.dart';
import '../rate.dart';
import '../session.dart';
import '../ui.dart';

enum _Phase { entry, qr, paid }

class _Sale {
  final String id;
  final BigInt amountUnits;

  /// Null when the sale was priced straight in USDT: there is no Bs figure
  /// and no quote sitting behind it.
  final double? bs;
  final double? rate;

  /// Null for USDT prices. The countdown exists because a Bs quote goes
  /// stale; 8,69 USDT is 8,69 USDT an hour later, so nothing expires.
  final int? exp;
  const _Sale(this.id, this.amountUnits, this.bs, this.rate, this.exp);
}

/// The charge flow: one amount seen in dollars and bolivianos, then one of
/// two rails — the customer's wallet on-chain, or a bank QR in Bs — then the
/// green screen once the shop actually has the dollars.
class CobrarScreen extends StatefulWidget {
  final Session session;
  final int merchantId;
  const CobrarScreen({
    super.key,
    required this.session,
    required this.merchantId,
  });

  @override
  State<CobrarScreen> createState() => _CobrarScreenState();
}

class _CobrarScreenState extends State<CobrarScreen> {
  _Phase _phase = _Phase.entry;
  _Sale? _sale;
  Payment? _payment;

  /// What the chain actually received. Never below the price asked (the
  /// green screen waits for that), but it can be above it if the customer
  /// overpaid, and that is the figure the cashier has to see.
  BigInt? _paidUnits;

  /// Set for a sale charged in Bs: the bank QR the backend issued, and the
  /// image it came with. Null for the on-chain USDT rail.
  FiatQr? _fiat;
  Uint8List? _qrImage;
  bool _creating = false;
  String? _error;
  Merchant? _merchant;

  /// The field on top is the one the keypad types into. Every visit starts
  /// with dollars there — the common case — and the swap button brings
  /// bolivianos up for shops that price in Bs.
  Money _top = Money.usd;

  /// Which field holds what the cashier typed; the other is derived from it.
  Money? _source;
  String _text = '';
  bool _late = false;
  Timer? _clock;
  Timer? _poll;
  int _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void initState() {
    super.initState();
    _syncRate();
    _loadMerchant();
  }

  /// Shows the stored quote at once, then refreshes behind it. A sale never
  /// waits on the network.
  /// The payout address the shop registered on-chain, warmed up so pressing
  /// Cobrar does not also have to wait for a round trip.
  Future<void> _loadMerchant() async {
    try {
      final merchant = await Chain.merchant(widget.merchantId);
      if (mounted) _merchant = merchant;
    } catch (_) {
      // not fatal: _cobrar fetches it again when it needs it
    }
  }

  Future<void> _syncRate() async {
    final cached = await Rate.load();
    if (!mounted) return;
    if (cached != null) {
      _applyQuote(cached);
      setState(() {});
    }
    final fresh = await Rate.refresh();
    if (!mounted || fresh == null) return;
    _applyQuote(fresh);
    setState(() {});
  }

  /// Stores the market rate. Kept on the device so the register still prices
  /// a sale when the quote cannot be reached.
  void _applyQuote(RateQuote q) {
    final v = q.buy.toStringAsFixed(2);
    if (widget.session.rate == v) return;
    widget.session.rate = v;
    widget.session.save();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  double? get _rate {
    final v = double.tryParse(widget.session.rate.replaceAll(',', '.'));
    return (v != null && v > 0) ? v : null;
  }

  ChargeAmounts get _amounts =>
      ChargeAmounts(source: _source, text: _text, rate: _rate);

  void _key(String k) {
    setState(() {
      if (_source != _top) {
        // The top field was showing a conversion. Typing replaces it the way
        // a selected text field would, and makes it the figure that counts.
        _source = _top;
        _text = k == '<' ? '' : ChargeAmounts.press('', k);
      } else {
        _text = ChargeAmounts.press(_text, k);
      }
      _error = null;
    });
  }

  /// Swaps which currency sits on top. The typed figure keeps counting until
  /// the cashier types again, so a swap never re-derives an amount from its
  /// own rounding.
  void _swap() =>
      setState(() => _top = _top == Money.usd ? Money.bs : Money.usd);

  /// The sale id carries the register that issued it, and the router refuses
  /// to settle a sale whose register is not authorized. Without an identity
  /// the QR would still look perfect, the customer would sign, and the
  /// payment would revert: they would believe they paid and this screen
  /// would wait forever.
  String? _newSaleId() {
    final cashier = widget.session.cashierAddress;
    if (cashier == null || cashier.isEmpty) {
      setState(
        () => _error =
            'Esta caja no está vinculada al comercio. Vuelve a ingresar '
            'el código que te dio el dueño.',
      );
      return null;
    }
    return buildSaleId(cashier);
  }

  /// On-chain rail: the QR is a link to the payment page and the customer's
  /// wallet pays the USDT straight to the shop. Nothing has to be issued.
  void _cobrarOnchain() {
    if (_creating) return;
    final amounts = _amounts;
    final units = amounts.units;
    if (units == null) return;
    final id = _newSaleId();
    if (id == null) return;
    // A price typed in dollars is final. One typed in bolivianos became
    // dollars at today's rate, so it travels with that quote and a deadline.
    _sale = amounts.source == Money.bs
        ? _Sale(
            id,
            units,
            amounts.bs,
            amounts.rate,
            DateTime.now().millisecondsSinceEpoch ~/ 1000 +
                WalikiConfig.quoteMinutes * 60,
          )
        : _Sale(id, units, null, null, null);
    _startWaiting();
  }

  /// Bank rail: the backend issues a QR in bolivianos and, once the bank
  /// confirms it, releases the dollars to the shop's own wallet.
  Future<void> _cobrarBs() async {
    if (_creating) return;
    final amounts = _amounts;
    final units = amounts.units;
    final bs = amounts.bs;
    if (units == null || bs == null || bs < 0.01) return;
    final id = _newSaleId();
    if (id == null) return;

    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final merchant = _merchant ?? await Chain.merchant(widget.merchantId);
      if (!mounted) return;
      _merchant = merchant;
      final (qr, image) = await QrService.create(
        bs: bs,
        units: units,
        destinationWallet: merchant.payout,
        merchantId: widget.merchantId,
        saleId: id,
        description: merchant.displayName,
      );
      if (!mounted) return;
      _fiat = qr;
      _qrImage = image;
      // The gateway sets the deadline; fall back to ours if it does not.
      final expiry =
          qr.expiresAt ??
          DateTime.now().add(
            const Duration(minutes: WalikiConfig.quoteMinutes),
          );
      _sale = _Sale(
        id,
        units,
        bs,
        amounts.rate,
        expiry.millisecondsSinceEpoch ~/ 1000,
      );
      _startWaiting();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error is QrServiceException
            ? error.message
            : 'No se pudo generar el QR.';
      });
    }
  }

  void _startWaiting() {
    _creating = false;
    _phase = _Phase.qr;
    if (_sale?.exp != null) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _now = DateTime.now().millisecondsSinceEpoch ~/ 1000);
      });
    }
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    setState(() {});
  }

  Future<void> _check() async {
    final sale = _sale;
    if (sale == null || _phase != _Phase.qr) return;

    final fiat = _fiat;
    if (fiat != null) {
      try {
        final next = await QrService.status(fiat.id);
        if (!mounted || _phase != _Phase.qr) return;
        // Green only once the tUSDT actually reached the shop. A `completed`
        // on its own means the bank has the bolivianos and Waliki still owes
        // the dollars — not a sale the cashier should wave through.
        if (next.transferred) {
          final exp = sale.exp;
          _late =
              exp != null &&
              DateTime.now().millisecondsSinceEpoch ~/ 1000 > exp;
          _phase = _Phase.paid;
          _poll?.cancel();
          _clock?.cancel();
          HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
        }
        setState(() => _fiat = next);
      } catch (_) {
        // transient: the backend retries the settlement on the next poll
      }
      return;
    }

    try {
      final paid = await Chain.paidAmount(widget.merchantId, sale.id);
      // The amount travels in the QR url, so a customer can lower it before
      // signing. Anything short of the price asked is not a paid sale.
      if (paid >= sale.amountUnits && mounted && _phase == _Phase.qr) {
        _paidUnits = paid;
        final exp = sale.exp;
        _late =
            exp != null && DateTime.now().millisecondsSinceEpoch ~/ 1000 > exp;
        _phase = _Phase.paid;
        _poll?.cancel();
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        setState(() {});
        // Backfill payer/tx from the event log (best-effort)
        try {
          final logs = await Chain.payments(
            merchantId: widget.merchantId,
            saleId: sale.id,
          );
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
      _text = '';
      _source = null;
      _sale = null;
      _payment = null;
      _paidUnits = null;
      _fiat = null;
      _qrImage = null;
      _error = null;
      _creating = false;
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
    final amounts = _amounts;
    final units = amounts.units;
    final bs = amounts.bs;
    final canOnchain = !_creating && units != null;
    final canBs = !_creating && units != null && bs != null && bs >= 0.01;
    final bottom = _top == Money.usd ? Money.bs : Money.usd;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: kSurface,
              border: Border.all(color: kLine),
              borderRadius: BorderRadius.circular(999),
            ),
            // Read-only: the rate comes from the market on its own, so there
            // is nothing for the cashier to decide here.
            child: Text(
              'Tasa  Bs ${_rate?.toStringAsFixed(2) ?? '—'}  =  1 USDT',
              style: wk(size: 13.5, weight: 600, tabular: true),
            ),
          ),
          const SizedBox(height: 14),
          Stack(
            alignment: Alignment.center,
            children: [
              Column(
                children: [
                  _AmountField(
                    money: _top,
                    value: _shown(_top, amounts),
                    active: true,
                    derived: amounts.source != _top,
                  ),
                  const SizedBox(height: 10),
                  _AmountField(
                    money: bottom,
                    value: _shown(bottom, amounts),
                    active: false,
                    derived: amounts.source != bottom,
                    onTap: _swap,
                  ),
                ],
              ),
              _SwapButton(onTap: _swap),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(child: _AmountKeypad(onKey: _key)),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: wk(size: 12.5, weight: 600, color: kDanger, height: 1.35),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _RailButton(
                  title: 'Cobrar USDT',
                  subtitle: 'Billetera del cliente',
                  icon: Icons.account_balance_wallet_rounded,
                  onTap: canOnchain ? _cobrarOnchain : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RailButton(
                  title: _creating ? 'Generando…' : 'Cobrar Bs',
                  subtitle: 'QR bancario',
                  icon: Icons.account_balance_rounded,
                  solid: true,
                  busy: _creating,
                  onTap: canBs ? _cobrarBs : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What a field shows: the figure as typed, or its conversion. A dash means
  /// the conversion needs a rate the register does not have yet.
  String _shown(Money money, ChargeAmounts amounts) {
    if (money == amounts.source && amounts.text.isNotEmpty) {
      return amounts.text;
    }
    if (amounts.isEmpty) return '0';
    if (money == Money.bs) {
      final bs = amounts.bs;
      return bs == null ? '—' : fmtNum(bs);
    }
    final units = amounts.units;
    return units == null ? '—' : fmtUsdt(units);
  }

  Widget _buildQr() {
    final sale = _sale!;
    final exp = sale.exp;
    final expired = exp != null && _now >= exp;
    final left = exp == null ? 0 : (exp - _now).clamp(0, 1 << 31);
    final bs = sale.bs;
    final rate = sale.rate;
    // The link carries only what the sale actually has: a USDT price travels
    // without a rate and without a deadline.
    final url = StringBuffer(
      '${WalikiConfig.payBaseUrl}/pay/${sale.id}'
      '?m=${widget.merchantId}&a=${sale.amountUnits}',
    );
    if (bs != null && rate != null) {
      url.write('&bs=${bs.toStringAsFixed(2)}&r=${rate.toStringAsFixed(2)}');
    }
    if (exp != null) url.write('&exp=$exp');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          if (bs != null) ...[
            Text('Bs ${fmtNum(bs)}', style: wkNum(size: 34)),
            Text(
              '${fmtUsdt(sale.amountUnits)} tUSDT',
              style: wk(size: 15, weight: 700, color: kBrandInk, tabular: true),
            ),
          ] else
            Text('${fmtUsdt(sale.amountUnits)} tUSDT', style: wkNum(size: 34)),
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
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: _qrImage != null
                ? Image.memory(
                    _qrImage!,
                    width: 232,
                    height: 232,
                    gaplessPlayback: true,
                  )
                : QrImageView(data: url.toString(), size: 232),
          ),
          const SizedBox(height: 12),
          Text(
            _fiat != null
                ? 'El cliente escanea con la app de su banco'
                : 'El cliente escanea con su cámara',
            textAlign: TextAlign.center,
            style: wk(size: 12.5, weight: 500, color: kInkSoft),
          ),
          const SizedBox(height: 14),
          WCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const _PulseDot(),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    // Between the bank confirming and the tUSDT landing there
                    // is a real gap: say so instead of leaving it as waiting.
                    _fiat?.completed == true
                        ? 'Pago recibido — liberando USDT…'
                        : 'Esperando el pago…',
                    style: wk(size: 14.5, weight: 700),
                  ),
                ),
                if (expired)
                  const WChip(
                    'cotización vencida',
                    bg: kDangerTint,
                    fg: kDanger,
                  )
                else if (exp != null)
                  WChip(
                    'vence en ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                    bg: kAmberTint,
                    fg: kAmber,
                  ),
              ],
            ),
          ),
          if (_fiat?.lastError != null) ...[
            const SizedBox(height: 10),
            Text(
              'Reintentando la liquidación…',
              textAlign: TextAlign.center,
              style: wk(size: 11.5, weight: 600, color: kAmber),
            ),
          ],
          if (expired) ...[
            const SizedBox(height: 14),
            PrimaryButton('Generar un QR nuevo', onTap: _reset),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                foregroundColor: kDanger,
                side: const BorderSide(color: kLine, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Cancelar venta',
                style: wk(size: 14.5, weight: 700, color: kDanger),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaid() {
    final sale = _sale!;
    final p = _payment;
    final received = _paidUnits ?? sale.amountUnits;
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        // Light icons: this screen fills the status bar with deep green.
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: kSuccessBottom,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kSuccessTop, kSuccessMid, kSuccessBottom],
              stops: [0, 0.55, 1],
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
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 62,
                        color: kBrand,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '¡Pago recibido!',
                    style: wk(
                      size: 26,
                      weight: 800,
                      color: Colors.white,
                      tracking: -0.03,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sale.bs != null
                        ? 'Bs ${fmtNum(sale.bs!)}'
                        : '${fmtUsdt(received)} tUSDT',
                    style: wkNum(size: 46, color: Colors.white),
                  ),
                  Text(
                    sale.bs != null
                        ? '${fmtUsdt(received)} tUSDT · venta ${short(sale.id)}'
                        : 'venta ${short(sale.id)}',
                    style: wk(
                      size: 13.5,
                      weight: 500,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  if (_late) ...[
                    const SizedBox(height: 10),
                    WChip(
                      'pago fuera de plazo',
                      bg: Colors.white.withValues(alpha: 0.18),
                      fg: Colors.white,
                    ),
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
                        _receiptRow(
                          'Pagó',
                          p != null
                              ? short(p.payer)
                              : _fiat != null
                              ? 'QR bancario'
                              : 'verificado on-chain',
                        ),
                        const SizedBox(height: 9),
                        _receiptRow(
                          'Transacción',
                          p != null
                              ? short(p.txHash)
                              : _fiat?.txHash != null
                              ? short(_fiat!.txHash!)
                              : 'confirmada',
                        ),
                        const SizedBox(height: 9),
                        _receiptRow(
                          'Bloque',
                          p != null ? p.block.toString() : '—',
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  PrimaryButton(
                    'Nueva venta',
                    color: Colors.white,
                    fg: kBrandInk,
                    onTap: _reset,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: wk(
          size: 12.5,
          weight: 500,
          color: Colors.white.withValues(alpha: 0.78),
        ),
      ),
      Text(
        value,
        style: wk(size: 13, weight: 600, color: Colors.white, mono: true),
      ),
    ],
  );
}

/// One currency of the amount. The top field is the one the keypad types
/// into; tapping the other brings it up.
class _AmountField extends StatelessWidget {
  final Money money;
  final String value;
  final bool active;

  /// Showing a conversion rather than what the cashier typed.
  final bool derived;
  final VoidCallback? onTap;
  const _AmountField({
    required this.money,
    required this.value,
    required this.active,
    required this.derived,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final usd = money == Money.usd;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: active ? kSurface : kSurface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? kBrand : kLine,
            width: active ? 1.6 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: kBrand.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? kBrandTint : kSurface,
                shape: BoxShape.circle,
              ),
              child: Text(
                usd ? '\$' : 'Bs',
                style: wk(size: usd ? 17 : 13.5, weight: 800, color: kBrandInk),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              usd ? 'USDT' : 'Bolivianos',
              style: wk(
                size: 13.5,
                weight: 700,
                color: active ? kInk : kInkSoft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  maxLines: 1,
                  style: wkNum(
                    size: active ? 32 : 24,
                    color: derived ? kInkSoft : kInk,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SwapButton({required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Intercambiar monedas',
    child: Material(
      color: kSurface,
      shape: const CircleBorder(side: BorderSide(color: kLine)),
      elevation: 2,
      shadowColor: const Color(0x220B1220),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.swap_vert_rounded, color: kBrand, size: 22),
        ),
      ),
    ),
  );
}

/// One way to charge. Both rails end in dollars for the shop; what changes is
/// how the customer pays — from their own wallet, or in bolivianos by bank QR.
class _RailButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  /// Navy instead of the brand gradient, so the two rails read apart.
  final bool solid;
  final bool busy;
  final VoidCallback? onTap;
  const _RailButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.solid = false,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final radius = BorderRadius.circular(14);
    final ink = enabled ? Colors.white : kDisabledInk;
    return SizedBox(
      height: 64,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: enabled && !solid ? kActionGradient : null,
          color: !enabled ? kDisabled : (solid ? kBrandInk : null),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: (solid ? kBrandInk : kBrandIndigo).withValues(
                      alpha: 0.28,
                    ),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (busy)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: ink,
                      ),
                    )
                  else
                    Icon(icon, color: ink, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: wk(size: 15, weight: 700, color: ink),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: wk(
                            size: 11,
                            weight: 500,
                            color: ink.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    [',', '0', '<'],
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 10.0;
      // Keys take the height the screen leaves, within reason: big enough to
      // hit on a small phone, never slabs on a tall one.
      final keyHeight = ((constraints.maxHeight - gap * 3) / 4).clamp(
        38.0,
        62.0,
      );
      return Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < _rows.length; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              SizedBox(
                height: keyHeight,
                child: Row(
                  children: [
                    for (var c = 0; c < 3; c++) ...[
                      if (c > 0) const SizedBox(width: gap),
                      Expanded(child: _keyButton(_rows[r][c])),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _keyButton(String k) => Material(
    key: ValueKey('keypad-$k'),
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
            ? const Icon(Icons.backspace_outlined, color: kInkSoft, size: 21)
            : Text(k, style: wk(size: 23, weight: 600, tabular: true)),
      ),
    ),
  );
}
