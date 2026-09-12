import 'package:flutter/material.dart';

import '../ui.dart';

// Navigable mockups of the vision phases. Honest cut: every action here shows
// a "concept" notice — nothing is wired, exactly as declared in the pitch.

void _concepto(BuildContext context, String fase) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Concepto ($fase) — se construye en la siguiente fase'),
    ),
  );
}

Widget _screen(
  String chip,
  String title,
  String subtitle,
  List<Widget> children,
) => Builder(
  builder: (context) => Scaffold(
    appBar: WalikiBar(title: title, back: true, actions: [ConceptChip(chip)]),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: wk(size: 12.5, weight: 500, color: kInkSoft)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  ),
);

class ModoFacilScreen extends StatelessWidget {
  const ModoFacilScreen({super.key});

  @override
  Widget build(BuildContext context) => _screen(
    'Concepto · Fase 2',
    'Modo Fácil',
    'Tu billetera, sin saber nada de cripto',
    [
      Center(
        child: Container(
          width: 110,
          height: 110,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE7F4EC),
          ),
          child: const Icon(Icons.fingerprint, size: 62, color: kBrand),
        ),
      ),
      const SizedBox(height: 14),
      const Center(
        child: Text(
          'Crea tu billetera en 1 minuto',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 14),
      WCard(
        child: Column(
          children: const [
            _Bullet(
              Icons.lock_outline,
              'Passkey y biometría — nada que memorizar',
            ),
            SizedBox(height: 10),
            _Bullet(
              Icons.shield_outlined,
              'Las llaves son solo tuyas — Waliki nunca custodia',
            ),
            SizedBox(height: 10),
            _Bullet(
              Icons.restart_alt,
              'Recuperación con la cuenta de tu teléfono',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      PrimaryButton(
        'Crear mi billetera',
        onTap: () => _concepto(context, 'Fase 2'),
      ),
      const SizedBox(height: 20),
      const Text(
        'COMPRAR SALDO',
        style: TextStyle(
          color: kInkSoft,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 8),
      WCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bs 200,00',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const Text(
              'recibes ≈ 14,07 USDT · comisión de rampa 1,5%',
              style: TextStyle(color: kInkSoft, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MethodBox(
                    icon: Icons.qr_code_2,
                    label: 'QR bancario',
                    selected: true,
                    onTap: () => _concepto(context, 'Fase 2'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MethodBox(
                    icon: Icons.credit_card,
                    label: 'Tarjeta',
                    selected: false,
                    onTap: () => _concepto(context, 'Fase 2'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Operado por socios regulados — Waliki no procesa tu dinero fiat. KYC la primera vez.',
              style: TextStyle(color: kInkSoft, fontSize: 11),
            ),
          ],
        ),
      ),
    ],
  );
}

class ComercioScreen extends StatelessWidget {
  const ComercioScreen({super.key});

  @override
  Widget build(BuildContext context) => _screen(
    'Concepto · Fase 3',
    'Mi Tienda',
    'Pedidos con entrega · se paga igual que en caja',
    [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
        children: [
          _Product(
            'Salteña de pollo',
            'Bs 10,00',
            Icons.bakery_dining_outlined,
            const Color(0xFFF3E8D9),
            () => _concepto(context, 'Fase 3'),
          ),
          _Product(
            'Café americano',
            'Bs 12,00',
            Icons.coffee_outlined,
            const Color(0xFFE7EEF6),
            () => _concepto(context, 'Fase 3'),
          ),
          _Product(
            'Jugo de maracuyá',
            'Bs 15,00',
            Icons.local_drink_outlined,
            const Color(0xFFFBEFDD),
            () => _concepto(context, 'Fase 3'),
          ),
          _Product(
            'Sándwich de chola',
            'Bs 25,00',
            Icons.lunch_dining_outlined,
            const Color(0xFFEAF3EE),
            () => _concepto(context, 'Fase 3'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'PEDIDO #P-0456 · EN CAMINO',
        style: TextStyle(
          color: kInkSoft,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: kBrand, width: 1.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: const [
                Icon(Icons.shield_outlined, size: 17, color: kBrand),
                SizedBox(width: 7),
                Text(
                  'Pago dividido on-chain',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Retenido por el contrato — se libera al confirmar la entrega, en una sola transacción:',
              style: TextStyle(color: kInkSoft, fontSize: 11),
            ),
            const SizedBox(height: 10),
            const _SplitRow('Comercio', 'Bs 35,00 · 2,50 USDT'),
            const _SplitRow('Repartidor — AL INSTANTE', 'Bs 8,00 · 0,57 USDT'),
            const _SplitRow('Waliki (2%)', 'Bs 0,86 · 0,06 USDT'),
            const Divider(height: 18),
            const _SplitRow(
              'El cliente pagó',
              'Bs 43,86 · 3,13 USDT',
              bold: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      const Center(
        child: Text(
          'Sin liquidaciones semanales: el repartidor cobra al confirmar.',
          style: TextStyle(color: kInkSoft, fontSize: 11),
        ),
      ),
    ],
  );
}

class PuntajeScreen extends StatelessWidget {
  const PuntajeScreen({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => _screen('Concepto', 'Puntaje comercial', 'Mi Tienda', [
    Center(
      child: SizedBox(
        width: 160,
        height: 160,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CircularProgressIndicator(
              value: 0.87,
              strokeWidth: 13,
              color: kBrand,
              backgroundColor: kLine,
              strokeCap: StrokeCap.round,
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    '87',
                    style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700),
                  ),
                  Text('/100', style: TextStyle(color: kInkSoft, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    const Center(
      child: Text(
        'Sobre 1.240 ventas verificadas on-chain — auditable por cualquiera.',
        textAlign: TextAlign.center,
        style: TextStyle(color: kInkSoft, fontSize: 12),
      ),
    ),
    const SizedBox(height: 14),
    WCard(
      child: Column(
        children: const [
          _Factor('Volumen de ventas', 0.82),
          SizedBox(height: 12),
          _Factor('Consistencia diaria', 0.91),
          SizedBox(height: 12),
          _Factor('Antigüedad', 0.74),
          SizedBox(height: 12),
          _Factor('Diversidad de pagadores', 0.88),
        ],
      ),
    ),
    const SizedBox(height: 12),
    Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F4EC),
        border: Border.all(color: kBrand, width: 1.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adelanto de ventas disponible',
            style: TextStyle(fontWeight: FontWeight.w700, color: kBrandInk),
          ),
          const Text(
            'hasta Bs 3.500,00',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: kBrandInk,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Repago automático: 10% de cada venta hasta amortizar. Tu historial es tu garantía.',
            style: TextStyle(color: Color(0xFF33443B), fontSize: 12),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            'Simular adelanto',
            onTap: () => _concepto(context, 'visión'),
          ),
        ],
      ),
    ),
  ]);
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Bullet(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: kBrand),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _MethodBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MethodBox({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: selected ? kBrand : kLine,
        width: selected ? 2 : 1,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: selected ? kBrand : kInkSoft, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Product extends StatelessWidget {
  final String name;
  final String price;
  final IconData icon;
  final Color tint;
  final VoidCallback onAdd;
  const _Product(this.name, this.price, this.icon, this.tint, this.onAdd);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: kLine),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 34, color: kBrandInk),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              price,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: kBrand,
                ),
                child: const Icon(Icons.add, size: 17, color: Colors.white),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SplitRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _SplitRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _Factor extends StatelessWidget {
  final String label;
  final double value;
  const _Factor(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text(
            '${(value * 100).round()}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kInkSoft,
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 7,
          color: kBrand,
          backgroundColor: const Color(0xFFECEFEC),
        ),
      ),
    ],
  );
}
