import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../caja_code.dart';
import '../cashier_identity.dart';
import '../chain.dart';
import '../session.dart';
import '../ui.dart';
import '../vault.dart';
import 'cajero_pin.dart';

/// The cashier turns this device into a register by typing the code the owner
/// handed them.
///
/// The code carries the shop id and the seed this phone derives its identity
/// from. That identity is checked against `isCashier` before anything is
/// saved: typing a shop number no longer gets you a register, which is exactly
/// what it used to do.
class CajeroSetupScreen extends StatefulWidget {
  final Session session;

  /// Shown above the field when the register was sent back here because its
  /// identity is gone (uninstall, restored backup, cleared app data).
  final String? notice;

  const CajeroSetupScreen({super.key, required this.session, this.notice});

  @override
  State<CajeroSetupScreen> createState() => _CajeroSetupScreenState();
}

class _CajeroSetupScreenState extends State<CajeroSetupScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _vincular() async {
    final parsed = parseCajaCode(_ctrl.text);
    if (parsed == null) {
      setState(
        () => _error = 'Código inválido. Debe verse así: 7-K3NQ-7X2F-PM8T-QWRJ',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final merchant = await Chain.merchant(parsed.merchantId);
      if (merchant.owner.isEmpty ||
          merchant.owner == '0x0000000000000000000000000000000000000000') {
        _fail('El comercio #${parsed.merchantId} no existe en la blockchain.');
        return;
      }

      final identity = deriveCashier(parsed.seed);
      final authorized = await Chain.isCashier(
        parsed.merchantId,
        identity.address,
      );
      if (!authorized) {
        // Covers both a typo and a register the owner already revoked, and
        // there is no way to tell them apart from here -- nor any need to.
        _fail(
          'Este código no está autorizado en ${merchant.displayName}. '
          'Pídele al dueño que genere una caja nueva.',
        );
        return;
      }

      await Vaults.instance.write(
        Vaults.cashierSeedKey,
        encodeCajaCode(parsed.merchantId, parsed.seed),
      );
      final s = widget.session;
      s.role = Role.cajero;
      s.merchantId = parsed.merchantId;
      s.cashierAddress = identity.address;
      s.pin = null;
      await s.save();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              CajeroPinScreen(session: s, merchantId: parsed.merchantId),
        ),
        (route) => false,
      );
    } catch (e) {
      _fail('No se pudo verificar el código. Revisa tu conexión.');
      debugPrint('cajero_setup: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WalikiBar(title: 'Vincular esta caja', back: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: kBrandTint,
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    size: 38,
                    color: kBrand,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ingresa el código de caja',
                textAlign: TextAlign.center,
                style: wk(size: 21, weight: 800, tracking: -0.03),
              ),
              const SizedBox(height: 8),
              Text(
                'Es el código que te dio el dueño del comercio. '
                'Se ve así: 7-K3NQ-7X2F-PM8T-QWRJ',
                textAlign: TextAlign.center,
                style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
              ),
              if (widget.notice != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: kSurface2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    widget.notice!,
                    style: wk(
                      size: 12.5,
                      weight: 600,
                      color: kInkSoft,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _ctrl,
                textAlign: TextAlign.center,
                // Letters AND digits now: the old digits-only formatter would
                // make this code literally impossible to type.
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (_, next) => next.copyWith(
                      text: formatCajaCodeInput(next.text),
                      selection: TextSelection.collapsed(
                        offset: formatCajaCodeInput(
                          next.text.substring(0, next.selection.baseOffset),
                        ).length,
                      ),
                    ),
                  ),
                ],
                style: wk(size: 21, weight: 800, mono: true),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _vincular(),
                decoration: InputDecoration(
                  hintText: '7-K3NQ-7X2F-PM8T-QWRJ',
                  hintStyle: wk(
                    size: 19,
                    weight: 700,
                    color: const Color(0xFFC6CEC8),
                    mono: true,
                  ),
                  filled: true,
                  fillColor: kSurface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kLine, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kBrand, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    if (d?.text != null) {
                      setState(() {
                        _ctrl.text = formatCajaCodeInput(d!.text!);
                        _error = null;
                      });
                    }
                  },
                  icon: const Icon(
                    Icons.content_paste_rounded,
                    size: 16,
                    color: kInkSoft,
                  ),
                  label: Text(
                    'Pegar',
                    style: wk(size: 13, weight: 600, color: kInkSoft),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
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
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                _busy ? 'Verificando…' : 'Vincular caja',
                onTap: _busy ? null : _vincular,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 15, color: kBrand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Como cajero cobras y verificas, pero nunca tocas los fondos '
                      'ni las llaves del dueño.',
                      style: wk(
                        size: 12,
                        weight: 500,
                        color: kInkSoft,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
