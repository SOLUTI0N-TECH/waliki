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
          colorScheme: ColorScheme.fromSeed(seedColor: kGreen),
          scaffoldBackgroundColor: kBg,
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const TestnetBanner(),
              const SizedBox(height: 34),
              const Text('waliki',
                  style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      color: kGreenDark,
                      letterSpacing: -1)),
              const SizedBox(height: 6),
              const Text('La caja que verifica en la blockchain',
                  style: TextStyle(color: kMuted, fontSize: 13)),
              const SizedBox(height: 22),
              const WChip('Tienda Demo CBBA · Caja 1'),
              const SizedBox(height: 16),
              Text(_error ? 'PIN incorrecto — intenta de nuevo' : 'Ingresa tu PIN de cajero',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: _error ? kRed : kInk)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? kGreen : Colors.transparent,
                        border: Border.all(
                            color: i < _pin.length ? kGreen : const Color(0xFFC6CEC8),
                            width: 2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _Keypad(onKey: _tap),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'El cajero cobra y verifica — nunca toca los fondos ni las llaves.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMuted, fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
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
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: kLine),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => onKey(k),
                      child: Center(
                        child: k == '<'
                            ? const Icon(Icons.backspace_outlined, color: kMuted)
                            : Text(k,
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
