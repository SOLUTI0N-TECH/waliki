import 'package:flutter/material.dart';

import '../session.dart';
import '../ui.dart';
import 'home.dart';

/// The cashier chooses the PIN that locks this device.
///
/// It used to come inside the linking code, which meant the owner knew it and
/// it was the same on every register. Now it is a local lock and nothing else:
/// what authorizes the register is its on-chain identity, not this number.
class CajeroPinScreen extends StatefulWidget {
  final Session session;
  final int merchantId;
  const CajeroPinScreen({
    super.key,
    required this.session,
    required this.merchantId,
  });

  @override
  State<CajeroPinScreen> createState() => _CajeroPinScreenState();
}

class _CajeroPinScreenState extends State<CajeroPinScreen> {
  static const _length = 4;

  String _first = '';
  String _current = '';
  String? _error;

  bool get _confirming => _first.isNotEmpty;

  Future<void> _tap(String key) async {
    if (key == '<') {
      setState(() {
        _error = null;
        if (_current.isNotEmpty) {
          _current = _current.substring(0, _current.length - 1);
        }
      });
      return;
    }
    if (_current.length >= _length) return;

    setState(() {
      _error = null;
      _current += key;
    });
    if (_current.length < _length) return;

    if (!_confirming) {
      setState(() {
        _first = _current;
        _current = '';
      });
      return;
    }

    if (_current != _first) {
      setState(() {
        _error = 'Los PIN no coinciden. Empecemos otra vez.';
        _first = '';
        _current = '';
      });
      return;
    }

    final s = widget.session;
    s.pin = _current;
    await s.save();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomeScreen(session: s, merchantId: widget.merchantId),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WalikiBar(mark: false),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 36),
              WChip('Caja del comercio #${widget.merchantId}'),
              const SizedBox(height: 20),
              Text(
                _confirming ? 'Repite tu PIN' : 'Elige tu PIN',
                style: wk(size: 21, weight: 800, tracking: -0.03),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _error ??
                      'Cuatro dígitos para abrir la caja en este teléfono. '
                          'Es tuyo: el dueño no lo necesita.',
                  textAlign: TextAlign.center,
                  style: wk(
                    size: 13,
                    weight: 500,
                    color: _error != null ? kDanger : kInkSoft,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 13,
                      height: 13,
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _current.length
                            ? kBrand
                            : Colors.transparent,
                        border: Border.all(
                          color: i < _current.length
                              ? kBrand
                              : const Color(0xFFC6CEC8),
                          width: 2,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 26),
              Keypad(onKey: _tap),
              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
    );
  }
}
