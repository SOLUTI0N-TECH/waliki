import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chain.dart';
import '../session.dart';
import '../ui.dart';

/// The owner turns any device into a register for one shop: it produces a
/// short code (shop + PIN) the cashier types in. No keys travel — the code
/// only unlocks the charging UI, which can never move funds.
class VincularCajaScreen extends StatefulWidget {
  final Session session;
  final Merchant merchant;
  const VincularCajaScreen({
    super.key,
    required this.session,
    required this.merchant,
  });

  @override
  State<VincularCajaScreen> createState() => _VincularCajaScreenState();
}

class _VincularCajaScreenState extends State<VincularCajaScreen> {
  late String _pin = (Random.secure().nextInt(9000) + 1000).toString();
  bool _copied = false;

  String get _code => Session.buildCajaCode(widget.merchant.id, _pin);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WalikiBar(title: 'Vincular cajero', back: true),
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
                'Dale este código a tu cajero. Con él, su teléfono se convierte en '
                'una caja de este comercio — sin billetera y sin acceso a tus fondos.',
                textAlign: TextAlign.center,
                style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22),
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
                    Text(
                      _code,
                      style: wk(
                        size: 40,
                        weight: 800,
                        color: kBrandInk,
                        tracking: -0.02,
                        tabular: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _code));
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
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 46,
                    width: 52,
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _pin = (Random.secure().nextInt(9000) + 1000)
                            .toString();
                        _copied = false;
                      }),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kLine, width: 1.5),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Icon(
                        Icons.autorenew_rounded,
                        size: 19,
                        color: kInkSoft,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              WCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cómo lo usa el cajero',
                      style: wk(size: 14, weight: 700),
                    ),
                    const SizedBox(height: 10),
                    _paso(
                      '1',
                      'Abre Waliki en su teléfono y elige "Soy cajero".',
                    ),
                    _paso('2', 'Escribe el código $_code.'),
                    _paso(
                      '3',
                      'Listo: cobra con el PIN $_pin cada vez que abra la app.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 15, color: kBrand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aunque alguien más vea el código, solo podría generar cobros '
                      'que pagan a TU dirección. Nadie puede mover tus fondos.',
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
