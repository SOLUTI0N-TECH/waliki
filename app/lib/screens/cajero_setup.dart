import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chain.dart';
import '../session.dart';
import '../ui.dart';
import 'home.dart';

/// The cashier turns this device into a register by typing the code the owner
/// gave them (shop + PIN). No wallet, no keys, nothing to steal.
class CajeroSetupScreen extends StatefulWidget {
  final Session session;
  const CajeroSetupScreen({super.key, required this.session});

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
    final parsed = Session.parseCajaCode(_ctrl.text);
    if (parsed == null) {
      setState(() => _error = 'Código inválido. Debe verse así: 74821');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    // Verify the shop actually exists on-chain before linking the device
    try {
      final m = await Chain.merchant(parsed.merchantId);
      if (m.owner.isEmpty ||
          m.owner == '0x0000000000000000000000000000000000000000') {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error =
              'El comercio #${parsed.merchantId} no existe en la blockchain.';
        });
        return;
      }
      final s = widget.session;
      s.role = Role.cajero;
      s.merchantId = parsed.merchantId;
      s.pin = parsed.pin;
      await s.save();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => HomeScreen(session: s, merchantId: parsed.merchantId),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo verificar el comercio: $e';
      });
    }
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
                'Es el código que te dio el dueño del comercio. Se ve así: 74821',
                textAlign: TextAlign.center,
                style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _ctrl,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                // Strips the W and the dash off codes handed out earlier, which
                // is exactly what the parser wants anyway.
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: wk(
                  size: 30,
                  weight: 800,
                  tracking: -0.02,
                  tabular: true,
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _vincular(),
                decoration: InputDecoration(
                  hintText: '74821',
                  hintStyle: wk(
                    size: 30,
                    weight: 800,
                    color: const Color(0xFFC6CEC8),
                    tabular: true,
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
                        _ctrl.text = d!.text!.trim();
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
