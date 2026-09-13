import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chain.dart';
import '../session.dart';
import '../ui.dart';
import '../vault.dart';
import '../wallet.dart';
import '../wallet_gate.dart';
import 'nueva_caja.dart';

/// The owner's list of registers: which ones can charge, which were revoked,
/// and the code for the ones this phone created.
class CajerosScreen extends StatefulWidget {
  final Session session;
  final Merchant merchant;
  const CajerosScreen({
    super.key,
    required this.session,
    required this.merchant,
  });

  @override
  State<CajerosScreen> createState() => _CajerosScreenState();
}

class _Caja {
  final String address;
  final String label;
  final bool? active; // null while it is still being confirmed
  final String? code; // only for registers created on this device

  const _Caja({
    required this.address,
    required this.label,
    this.active,
    this.code,
  });

  String get displayName => label.isEmpty ? 'Caja ${short(address)}' : label;

  _Caja copyWith({bool? active, String? label}) => _Caja(
    address: address,
    label: label ?? this.label,
    active: active ?? this.active,
    code: code,
  );
}

class _CajerosScreenState extends State<CajerosScreen> {
  List<_Caja> _cajas = const [];
  bool _scanning = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Local first, chain second.
  ///
  /// A full log scan is ~47 `eth_getLogs` windows — the same cost as the whole
  /// history. Making the owner wait that out to see three registers would be
  /// unusable, so what this phone already knows paints immediately, `isCashier`
  /// confirms it, and the scan (which finds registers created from another
  /// device of theirs) catches up behind.
  Future<void> _load() async {
    final local = await _loadLocal();
    if (mounted && local.isNotEmpty) setState(() => _cajas = local);

    await _confirm(local);

    try {
      final onChain = await Chain.cashiers(widget.merchant.id);
      if (!mounted) return;
      final byAddress = {for (final c in _cajas) c.address: c};
      final merged = <_Caja>[];
      for (final c in onChain) {
        final known = byAddress.remove(c.address);
        merged.add(
          _Caja(
            address: c.address,
            // The chain label wins: the owner may have renamed the register
            // from another phone.
            label: c.label.isNotEmpty ? c.label : (known?.label ?? ''),
            active: c.active,
            code: known?.code,
          ),
        );
      }
      // Anything local the scan did not see: a window the RPC refused, or an
      // addCashier still waiting for its block. Keep it, do not hide it.
      merged.addAll(byAddress.values);
      setState(() {
        _cajas = merged;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = 'No se pudo leer la lista completa desde la cadena.';
      });
      debugPrint('cajeros: $e');
    }
  }

  Future<List<_Caja>> _loadLocal() async {
    final out = <_Caja>[];
    // The owner charges from their own wallet, so they are a register too
    final owner = widget.merchant.owner.toLowerCase();
    if (owner.isNotEmpty) {
      out.add(_Caja(address: owner, label: 'Tú (dueño)'));
    }
    try {
      final raw = await Vaults.instance.read(
        Vaults.cashiersKey(widget.merchant.id),
      );
      if (raw == null) return out;
      for (final entry in jsonDecode(raw) as List<dynamic>) {
        final map = entry as Map<String, dynamic>;
        final address = (map['address'] as String?)?.toLowerCase();
        if (address == null || address == owner) continue;
        out.add(
          _Caja(
            address: address,
            label: map['label'] as String? ?? '',
            code: map['seed'] as String?,
          ),
        );
      }
    } catch (_) {
      // A corrupt vault entry costs the codes, not the list
    }
    return out;
  }

  Future<void> _confirm(List<_Caja> cajas) async {
    for (var i = 0; i < cajas.length; i += 8) {
      final end = (i + 8 > cajas.length) ? cajas.length : i + 8;
      final slice = cajas.sublist(i, end);
      final results = await Future.wait([
        for (final c in slice) _isCashierSafe(c.address),
      ]);
      if (!mounted) return;
      final updates = <String, bool?>{
        for (var k = 0; k < slice.length; k++) slice[k].address: results[k],
      };
      setState(() {
        _cajas = [
          for (final c in _cajas) c.copyWith(active: updates[c.address]),
        ];
      });
    }
  }

  Future<bool?> _isCashierSafe(String address) async {
    try {
      return await Chain.isCashier(widget.merchant.id, address);
    } catch (_) {
      return null;
    }
  }

  Future<void> _quitar(_Caja caja) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dar de baja ${caja.displayName}', style: wk(weight: 700)),
        content: Text(
          'Deja de poder cobrar al instante. Si tiene un QR en pantalla que '
          'nadie pagó todavía, ese cobro ya no se va a poder pagar.',
          style: wk(size: 13.5, weight: 500, color: kInkSoft, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', style: wk(weight: 600, color: kInkSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Dar de baja', style: wk(weight: 700, color: kDanger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final problema = await requireWallet(context, widget.session);
    if (problema != null) {
      if (mounted) setState(() => _error = problema);
      return;
    }

    try {
      await Wallet.instance.removeCashier(
        merchantId: widget.merchant.id,
        cashier: caja.address,
      );
      if (!mounted) return;
      setState(() => _error = null);
      await _confirm([caja]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = walletErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WalikiBar(title: 'Cajeros', back: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.merchant.displayName,
                textAlign: TextAlign.center,
                style: wk(size: 19, weight: 800, tracking: -0.03),
              ),
              const SizedBox(height: 6),
              Text(
                'Cada caja cobra a tu nombre y queda registrada en sus ventas. '
                'Ninguna puede tocar tus fondos.',
                textAlign: TextAlign.center,
                style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: kDangerTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _error!,
                    style: wk(size: 13, weight: 600, color: kDanger),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              for (final caja in _cajas) ...[
                _CajaTile(
                  caja: caja,
                  esDuenio: caja.address == widget.merchant.owner.toLowerCase(),
                  onQuitar: () => _quitar(caja),
                ),
                const SizedBox(height: 10),
              ],
              if (_scanning) ...[
                const SizedBox(height: 6),
                Center(
                  child: WChip(
                    'buscando cajas en la cadena…',
                    bg: kSurface2,
                    fg: kInkSoft,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              PrimaryButton(
                'Nueva caja',
                onTap: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => NuevaCajaScreen(
                        session: widget.session,
                        merchant: widget.merchant,
                      ),
                    ),
                  );
                  if (created == true && mounted) {
                    setState(() => _scanning = true);
                    await _load();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CajaTile extends StatelessWidget {
  final _Caja caja;
  final bool esDuenio;
  final VoidCallback onQuitar;

  const _CajaTile({
    required this.caja,
    required this.esDuenio,
    required this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    final active = caja.active;
    return WCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  caja.displayName,
                  style: wk(size: 15, weight: 700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (active == null)
                WChip('verificando…', bg: kSurface2, fg: kInkSoft)
              else if (active)
                WChip('activa')
              else
                WChip('dada de baja', bg: kDangerTint, fg: kDanger),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            short(caja.address),
            style: wk(size: 12, weight: 500, color: kInkSoft, mono: true),
          ),
          if (caja.code != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    caja.code!,
                    style: wk(
                      size: 13,
                      weight: 700,
                      color: kBrandInk,
                      mono: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar código',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: caja.code!)),
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 17,
                    color: kInkSoft,
                  ),
                ),
              ],
            ),
          ],
          if (!esDuenio && active == true) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onQuitar,
                child: Text(
                  'Dar de baja',
                  style: wk(size: 13, weight: 700, color: kDanger),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
