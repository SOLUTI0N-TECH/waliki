import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session.dart';
import '../ui.dart';
import '../wallet.dart';
import 'mis_comercios.dart';

/// The owner links their wallet to this device.
///
/// On mobile this opens the real wallet over WalletConnect. On web (where the
/// AppKit package has no implementation) it falls back to pasting the public
/// address — enough to read, since signing always happens in the wallet.
class ConectarScreen extends StatefulWidget {
  final Session session;
  const ConectarScreen({super.key, required this.session});

  @override
  State<ConectarScreen> createState() => _ConectarScreenState();
}

class _ConectarScreenState extends State<ConectarScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _waitingWallet = false;
  bool _walletReady = false;
  bool _walletFailed = false;

  @override
  void initState() {
    super.initState();
    Wallet.instance.connection.addListener(_onWalletConnection);
    if (!kIsWeb) {
      // Warm the modal up so the first tap is instant
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await Wallet.instance.init(context);
          if (mounted) setState(() => _walletReady = true);
        } catch (_) {
          // no wallet support on this platform: the paste flow still works
          if (mounted) setState(() => _walletFailed = true);
        }
      });
    }
  }

  @override
  void dispose() {
    Wallet.instance.connection.removeListener(_onWalletConnection);
    _ctrl.dispose();
    super.dispose();
  }

  /// AppKit reports the session the moment it exists, before its sheet has
  /// finished closing — so the owner moves on without waiting for animations.
  void _onWalletConnection() {
    final address = Wallet.instance.connection.value;
    if (address != null && mounted) _finish(address);
  }

  bool get _valid => RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(_ctrl.text.trim());

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() {
        _ctrl.text = text;
        _error = null;
      });
    }
  }

  /// Opens the wallet chooser and waits for the sheet to close.
  Future<void> _conectarBilletera() async {
    setState(() {
      _error = null;
      _waitingWallet = true;
    });
    // A session can outlive the app's own: "Desconectar" used to clear only
    // Waliki's side, and WalletConnect also restores itself on relaunch. Drop
    // it first so the chooser always comes up.
    await Wallet.instance.disconnect();
    if (!mounted) return;
    try {
      // AppKit awaits its own bottom sheet, so this returns once the sheet is
      // gone — approved or dismissed.
      await Wallet.instance.openModal(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _waitingWallet = false;
          _error = e is StateError
              ? e.message
              : 'No se pudo abrir la billetera: $e';
        });
      }
      return;
    }
    if (!mounted) return;
    final address = Wallet.instance.address;
    if (address != null) {
      _finish(address);
      return;
    }
    // Closed with no session: hand the button back immediately instead of
    // waiting on a timer to notice.
    setState(() => _waitingWallet = false);
  }

  Future<void> _finish(String address) async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = widget.session;
    s.role = Role.duenio;
    s.ownerAddress = address.toLowerCase();
    // The owner is a cashier of their own shops (registerMerchant signs them up),
    // so this is the address their sales are issued under when they charge from
    // this phone.
    s.cashierAddress = s.ownerAddress;
    await s.save();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MisComerciosScreen(session: s)),
    );
  }

  void _connectPasted() {
    if (!_valid) {
      setState(
        () => _error = 'Esa dirección no es válida (0x… de 42 caracteres).',
      );
      return;
    }
    _finish(_ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    // Show the button as soon as we know the platform supports it; it stays
    // disabled for the second or two WalletConnect needs to start up, instead
    // of the layout jumping from "paste an address" to a button.
    final showWalletButton = !kIsWeb && !_walletFailed;
    final walletUsable = _walletReady || Wallet.instance.available;
    return Scaffold(
      appBar: const WalikiBar(title: 'Conectar billetera', back: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
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
                    Icons.account_balance_wallet_rounded,
                    size: 38,
                    color: kBrand,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tu billetera, tus llaves',
                textAlign: TextAlign.center,
                style: wk(size: 21, weight: 800, tracking: -0.03),
              ),
              const SizedBox(height: 8),
              Text(
                'Waliki nunca ve tu frase secreta. Conectas para identificarte y '
                'firmas dentro de tu propia billetera.',
                textAlign: TextAlign.center,
                style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
              ),
              const SizedBox(height: 22),
              if (showWalletButton) ...[
                PrimaryButton(
                  _waitingWallet
                      ? 'Esperando tu billetera…'
                      : (walletUsable ? 'Conectar billetera' : 'Preparando…'),
                  onTap: _waitingWallet || _busy || !walletUsable
                      ? null
                      : _conectarBilletera,
                ),
                if (_waitingWallet) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Aprueba la conexión en tu billetera y vuelve a Waliki.',
                    textAlign: TextAlign.center,
                    style: wk(size: 12, weight: 500, color: kInkSoft),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider(color: kLine)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'o pega tu dirección',
                        style: wk(size: 12, weight: 600, color: kInkSoft),
                      ),
                    ),
                    const Expanded(child: Divider(color: kLine)),
                  ],
                ),
                const SizedBox(height: 16),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'TU DIRECCIÓN',
                    style: wk(
                      size: 11,
                      weight: 700,
                      color: kInkSoft,
                      tracking: 0.05,
                    ),
                  ),
                ),
              TextField(
                controller: _ctrl,
                style: wk(size: 13, weight: 500, mono: true),
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  hintText: '0x…',
                  hintStyle: wk(
                    size: 13,
                    weight: 500,
                    color: kInkSoft,
                    mono: true,
                  ),
                  filled: true,
                  fillColor: kSurface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: kLine, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: kBrand, width: 1.5),
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Pegar',
                    icon: const Icon(
                      Icons.content_paste_rounded,
                      size: 19,
                      color: kInkSoft,
                    ),
                    onPressed: _paste,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
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
              const SizedBox(height: 14),
              if (showWalletButton)
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _connectPasted,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kLine, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Usar esta dirección',
                      style: wk(size: 14, weight: 700, color: kBrandInk),
                    ),
                  ),
                )
              else
                PrimaryButton('Conectar', onTap: _busy ? null : _connectPasted),
            ],
          ),
        ),
      ),
    );
  }
}
