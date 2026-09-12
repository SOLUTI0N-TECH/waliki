import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../caja_code.dart';
import '../cashier_identity.dart';
import '../chain.dart';
import '../session.dart';
import '../ui.dart';
import '../vault.dart';
import '../wallet.dart';

/// The owner creates a register: the phone generates the identity, the owner
/// authorizes it on-chain with `addCashier`, and out comes a short code.
///
/// The cashier never signs and never holds gas — the code is the whole handover.
class NuevaCajaScreen extends StatefulWidget {
  final Session session;
  final Merchant merchant;
  const NuevaCajaScreen({
    super.key,
    required this.session,
    required this.merchant,
  });

  @override
  State<NuevaCajaScreen> createState() => _NuevaCajaScreenState();
}

enum _Step { form, waiting, done }

class _NuevaCajaScreenState extends State<NuevaCajaScreen> {
  final _label = TextEditingController(text: 'Caja 1');
  _Step _step = _Step.form;
  String? _error;
  bool _copied = false;

  CashierIdentity? _identity;
  String? _code;
  Timer? _poll;
  int _seconds = 0;

  @override
  void dispose() {
    _label.dispose();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _crear() async {
    final label = _label.text.trim();
    final identity = deriveCashier(newCajaSeed());

    setState(() {
      _error = null;
      _identity = identity;
      _step = _Step.waiting;
      _seconds = 0;
    });

    // Written down BEFORE the signature. If the app dies while the wallet is
    // open and the transaction lands anyway, the address ends up authorized
    // on-chain with its seed nowhere: a register nobody could ever link.
    await _remember(identity, label, pending: true);

    try {
      await Wallet.instance.addCashier(
        merchantId: widget.merchant.id,
        cashier: identity.address,
        label: label,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.form;
        _error = 'No se pudo enviar la autorización: $e';
      });
      return;
    }

    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      setState(() => _seconds += 4);
      _buscar();
    });
  }

  /// Polls `isCashier`: one exact, cheap call, and the only answer that says
  /// the register is really usable. Showing the code before it comes back true
  /// would have the cashier typing it in and being told they are not
  /// authorized.
  Future<void> _buscar() async {
    final identity = _identity;
    if (identity == null) return;
    try {
      final ok = await Chain.isCashier(widget.merchant.id, identity.address);
      if (!ok || !mounted) return;
      _poll?.cancel();
      await _remember(identity, _label.text.trim(), pending: false);
      if (!mounted) return;
      setState(() {
        _code = encodeCajaCode(widget.merchant.id, identity.seed);
        _step = _Step.done;
      });
    } catch (_) {
      // transient RPC error: the next tick asks again
    }
  }

  /// Keeps the seed on the owner's device so the code can be shown again
  /// without paying for a second signature.
  Future<void> _remember(
    CashierIdentity identity,
    String label, {
    required bool pending,
  }) async {
    final vault = Vaults.instance;
    final key = pending
        ? Vaults.pendingCashierKey(widget.merchant.id)
        : Vaults.cashiersKey(widget.merchant.id);
    try {
      final entry = {
        'address': identity.address,
        'label': label,
        'seed': encodeCajaCode(widget.merchant.id, identity.seed),
      };
      if (pending) {
        await vault.write(key, jsonEncode(entry));
        return;
      }
      final raw = await vault.read(key);
      final list = <dynamic>[
        if (raw != null) ...(jsonDecode(raw) as List<dynamic>),
      ]..removeWhere((e) => (e as Map)['address'] == identity.address);
      list.add(entry);
      await vault.write(key, jsonEncode(list));
      await vault.delete(Vaults.pendingCashierKey(widget.merchant.id));
    } catch (_) {
      // The register still works: this only costs re-showing the code later.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const WalikiBar(title: 'Nueva caja', back: true),
    body: SafeArea(
      child: switch (_step) {
        _Step.form => _buildForm(),
        _Step.waiting => _buildWaiting(),
        _Step.done => _buildDone(),
      },
    ),
  );

  Widget _buildForm() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
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
          'Ponle un nombre a la caja para reconocerla en tus reportes. '
          'Después te damos el código que tu cajero escribe en su teléfono.',
          textAlign: TextAlign.center,
          style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _label,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 40,
          style: wk(size: 17, weight: 700),
          decoration: InputDecoration(
            labelText: 'Nombre de la caja',
            hintText: 'Mostrador, Barra, Caja 2…',
            counterText: '',
            filled: true,
            fillColor: kSurface,
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
        if (_error != null) ...[const SizedBox(height: 12), _ErrorBox(_error!)],
        const SizedBox(height: 18),
        PrimaryButton('Crear caja', onTap: _crear),
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(Icons.shield_outlined, size: 15, color: kBrand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Vas a firmar una transacción para autorizar esta caja. Tu '
                'cajero no firma nada y nunca puede mover tus fondos: lo único '
                'que hace la autorización es permitirle emitir cobros que te '
                'pagan a ti.',
                style: wk(size: 12, weight: 500, color: kInkSoft, height: 1.45),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildWaiting() => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 52,
          height: 52,
          child: CircularProgressIndicator(strokeWidth: 3.5, color: kBrand),
        ),
        const SizedBox(height: 24),
        Text(
          'Esperando tu firma…',
          style: wk(size: 20, weight: 800, tracking: -0.03),
        ),
        const SizedBox(height: 10),
        Text(
          'Aprueba la transacción en tu billetera. Cuando entre en un bloque, '
          'te mostramos el código de la caja.',
          textAlign: TextAlign.center,
          style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
        ),
        const SizedBox(height: 18),
        WChip(
          'consultando la cadena · ${_seconds}s',
          bg: kSurface2,
          fg: kInkSoft,
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 46,
          child: OutlinedButton(
            onPressed: _buscar,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBrand, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Ya firmé — buscar ahora',
              style: wk(size: 14, weight: 700, color: kBrandInk),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            _poll?.cancel();
            setState(() => _step = _Step.form);
          },
          child: Text(
            'Cancelar',
            style: wk(size: 14, weight: 600, color: kInkSoft),
          ),
        ),
      ],
    ),
  );

  Widget _buildDone() {
    final code = _code!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _label.text.trim().isEmpty ? 'Caja nueva' : _label.text.trim(),
            textAlign: TextAlign.center,
            style: wk(size: 19, weight: 800, tracking: -0.03),
          ),
          const SizedBox(height: 6),
          Text(
            'Dale este código a tu cajero. Con él, su teléfono se convierte en '
            'esta caja — sin billetera y sin acceso a tus fondos.',
            textAlign: TextAlign.center,
            style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
            decoration: BoxDecoration(
              color: kSurface,
              border: Border.all(color: kBrand, width: 1.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(
                  'CÓDIGO DE CAJA',
                  style: wk(
                    size: 11,
                    weight: 700,
                    color: kInkSoft,
                    tracking: 0.05,
                  ),
                ),
                const SizedBox(height: 10),
                // Monospace on purpose: sixteen letters and digits read out
                // loud need a 0 that cannot be an O and a 1 that is not an l.
                Text(
                  code,
                  textAlign: TextAlign.center,
                  style: wk(
                    size: 22,
                    weight: 800,
                    color: kBrandInk,
                    mono: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!mounted) return;
                setState(() => _copied = true);
              },
              icon: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 17,
              ),
              label: Text(
                _copied ? 'Copiado' : 'Copiar código',
                style: wk(size: 14, weight: 700, color: kBrandInk),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: kBrandInk,
                side: const BorderSide(color: kLine, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          WCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cómo lo usa el cajero', style: wk(size: 14, weight: 700)),
                const SizedBox(height: 10),
                _paso('1', 'Abre Waliki en su teléfono y elige "Soy cajero".'),
                _paso('2', 'Escribe el código $code.'),
                _paso('3', 'Elige su propio PIN y ya puede cobrar.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 15, color: kBrand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cada cobro de esta caja queda registrado a su nombre, y '
                  'puedes darla de baja cuando quieras desde "Cajeros".',
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
          const SizedBox(height: 18),
          PrimaryButton('Listo', onTap: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
  }

  Widget _paso(String n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: kBrandTint,
          ),
          child: Text(n, style: wk(size: 11, weight: 700, color: kBrandInk)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: wk(size: 12.5, weight: 500, color: kInkSoft, height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: kDangerTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(message, style: wk(size: 13, weight: 600, color: kDanger)),
  );
}
