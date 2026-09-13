import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'screens/cajero_setup.dart';
import 'screens/home.dart';
import 'screens/mis_comercios.dart';
import 'screens/welcome.dart';
import 'session.dart';
import 'ui.dart';
import 'vault.dart';
import 'wallet.dart';

void main() => runApp(const WalikiApp());

class WalikiApp extends StatelessWidget {
  const WalikiApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: rootNavigatorKey,
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
      color: const Color(0xFFE4E9F4),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          decoration: const BoxDecoration(
            boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 28)],
          ),
          child: child,
        ),
      ),
    ),
    home: const Bootstrap(),
  );
}

/// Decides where the app opens: welcome on a fresh install, the owner panel
/// for a linked owner, the PIN gate for a linked register.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

typedef _Boot = ({Session session, bool cashierReady});

class _BootstrapState extends State<Bootstrap> {
  late final Future<_Boot> _boot = _load();

  @override
  void initState() {
    super.initState();
    // An owner reopening the app lands straight on MisComercios, so neither
    // Welcome nor Conectar ever builds and nobody used to create the modal.
    // The WalletConnect session was still on disk the whole time; AppKit
    // restores it here, and until it finishes ensureConnected() covers.
    if (kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = await _boot;
      if (session.session.role != Role.duenio || !mounted) return;
      try {
        await Wallet.instance.init(context);
      } catch (_) {
        // Unsupported platform or a flaky relay: ensureConnected() retries on
        // the next signature instead of leaving the app degraded for good.
      }
    });
  }

  /// A linked register also has to still HAVE its identity. Android restores
  /// preferences from a backup but not the Keystore key that opens the vault,
  /// so without this check the app would open a register that believes it is
  /// linked, ask for a PIN, and then not be able to issue a single sale.
  static Future<_Boot> _load() async {
    final session = await Session.load();
    if (session.role != Role.cajero) {
      return (session: session, cashierReady: true);
    }
    final seed = await Vaults.instance.read(Vaults.cashierSeedKey);
    return (
      session: session,
      cashierReady: seed != null && session.cashierAddress != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Boot>(
      future: _boot,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(
              child: SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 3, color: kBrand),
              ),
            ),
          );
        }
        final s = snap.data!.session;
        if (s.role == Role.cajero) {
          if (!snap.data!.cashierReady) {
            return CajeroSetupScreen(
              session: s,
              notice:
                  'Esta caja perdió su vinculación con el comercio. '
                  'Vuelve a ingresar el código que te dio el dueño.',
            );
          }
          if (s.merchantId != null) {
            return PinGate(session: s, merchantId: s.merchantId!);
          }
        }
        if (s.role == Role.duenio && s.ownerAddress != null) {
          return MisComerciosScreen(session: s);
        }
        return WelcomeScreen(session: s);
      },
    );
  }
}

/// Employee mode: the cashier signs in with a PIN — never with a wallet.
class PinGate extends StatefulWidget {
  final Session session;
  final int merchantId;
  const PinGate({super.key, required this.session, required this.merchantId});

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
      final expected = widget.session.pin!;
      if (_pin.length >= expected.length) return;
      _pin += key;
      if (_pin.length == expected.length) {
        if (_pin == expected) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => HomeScreen(
                session: widget.session,
                merchantId: widget.merchantId,
              ),
            ),
          );
        } else {
          _pin = '';
          _error = true;
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Nothing to ask for: the register was linked before cashiers chose their
    // own PIN, or the choice was interrupted. An implicit 1234 is worse than
    // no lock -- it looks like one.
    if (widget.session.pin == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              session: widget.session,
              merchantId: widget.merchantId,
            ),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final len = widget.session.pin?.length ?? 4;
    return Scaffold(
      appBar: const WalikiBar(mark: false),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Image.asset(
                'assets/brand/lockup.png',
                width: 184,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(height: 8),
              Text(
                'La caja que verifica en la blockchain',
                style: wk(size: 13.5, weight: 500, color: kInkSoft),
              ),
              const SizedBox(height: 24),
              WChip('Caja del comercio #${widget.merchantId}'),
              const SizedBox(height: 20),
              Text(
                _error
                    ? 'PIN incorrecto — intenta de nuevo'
                    : 'Ingresa tu PIN de cajero',
                style: wk(
                  size: 15,
                  weight: 700,
                  color: _error ? kDanger : kInk,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < len; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 13,
                      height: 13,
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? kBrand : Colors.transparent,
                        border: Border.all(
                          color: i < _pin.length
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
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'El cajero cobra y verifica — nunca toca los fondos ni las llaves.',
                  textAlign: TextAlign.center,
                  style: wk(
                    size: 12.5,
                    weight: 500,
                    color: kInkSoft,
                    height: 1.45,
                  ),
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
