import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/home.dart';
import 'ui.dart';

void main() => runApp(const WalikiApp());

class WalikiApp extends StatelessWidget {
  const WalikiApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Waliki',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'PlusJakartaSans',
          colorScheme: ColorScheme.fromSeed(
            seedColor: kBrand,
            primary: kBrand,
            surface: kSurface,
          ),
          scaffoldBackgroundColor: kPage,
          splashFactory: InkSparkle.splashFactory,
        ),
        // Phone-first app: on wide screens (web/desktop) render inside a
        // centered 430px frame; on phones this changes nothing.
        builder: (context, child) => ColoredBox(
          color: const Color(0xFFE7EBE7),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 430),
              decoration: const BoxDecoration(boxShadow: [
                BoxShadow(color: Color(0x1F000000), blurRadius: 28),
              ]),
              child: child,
            ),
          ),
        ),
        home: const PinGate(),
      );
}

/// Employee mode: the cashier signs in with a PIN — never with a wallet.
class PinGate extends StatefulWidget {
  const PinGate({super.key});

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  String _pin = '';
  bool _error = false;

  void _tap(String key) {
    setState(() {
      _error = false;
      if (key == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
        return;
      }
      if (_pin.length >= 4) return;
      _pin += key;
      if (_pin.length == 4) {
        if (_pin == WalikiConfig.cajaPin) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else {
          _pin = '';
          _error = true;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WalikiBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text('waliki',
                  style: wk(size: 40, weight: 800, color: kBrandInk, tracking: -0.035)),
              const SizedBox(height: 4),
              Text('La caja que verifica en la blockchain',
                  style: wk(size: 13.5, weight: 500, color: kInkSoft)),
              const SizedBox(height: 24),
              const WChip('Tienda Demo CBBA · Caja 1'),
              const SizedBox(height: 20),
              Text(_error ? 'PIN incorrecto — intenta de nuevo' : 'Ingresa tu PIN de cajero',
                  style: wk(size: 15, weight: 700, color: _error ? kDanger : kInk)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 13,
                      height: 13,
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? kBrand : Colors.transparent,
                        border: Border.all(
                            color: i < _pin.length ? kBrand : const Color(0xFFC6CEC8),
                            width: 2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 26),
              _Keypad(onKey: _tap),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'El cajero cobra y verifica — nunca toca los fondos ni las llaves.',
                  textAlign: TextAlign.center,
                  style: wk(size: 12.5, weight: 500, color: kInkSoft, height: 1.45),
                ),
              ),
              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final void Function(String) onKey;
  const _Keypad({required this.onKey});

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
        children: [
          for (final k in keys)
            k.isEmpty
                ? const SizedBox()
                : Material(
                    color: kSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: kLine),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onKey(k),
                      child: Center(
                        child: k == '<'
                            ? const Icon(Icons.backspace_outlined,
                                color: kInkSoft, size: 22)
                            : Text(k, style: wk(size: 25, weight: 600, tabular: true)),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
