import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
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
  Timer? _poll;

  @override
  void initState() {
    super.initState();
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
    _poll?.cancel();
    _ctrl.dispose();
    super.dispose();
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

  Future<void> _openWeb() async {
    final uri = Uri.parse('${WalikiConfig.payBaseUrl}/registro');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) setState(() => _error = 'No se pudo abrir el navegador.');
    }
  }

  /// Opens the wallet chooser and waits for a session to appear.
  Future<void> _conectarBilletera() async {
    setState(() {
      _error = null;
      _waitingWallet = true;
    });
    // A session can outlive the app's own: "Desconectar" used to clear only
    // Waliki's side, and WalletConnect also restores itself on relaunch. Drop
    // it first so the chooser always comes up and the poll below can only see
    // an address the user just approved.
    await Wallet.instance.disconnect();
    if (!mounted) return;
    try {
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
    // The modal reports its result asynchronously; watch for the address.
    var waited = Duration.zero;
    const tick = Duration(milliseconds: 600);
    _poll = Timer.periodic(tick, (t) {
      if (!mounted) return t.cancel();
      final addr = Wallet.instance.address;
      if (addr != null) {
        t.cancel();
        _finish(addr);
        return;
      }
      // Nothing came back. Release the button instead of leaving it stuck on
      // "Esperando…": either the sheet is gone (dismissed, or the wallet never
      // came back to us) or the wallet simply never answered.
      waited += tick;
      final dismissed =
          waited > const Duration(seconds: 2) && !Wallet.instance.isModalOpen;
      if (dismissed || waited >= const Duration(minutes: 3)) {
        t.cancel();
        setState(() => _waitingWallet = false);
      }
    });
  }

  Future<void> _finish(String address) async {
    _poll?.cancel();
    setState(() => _busy = true);
    final s = widget.session;
    s.role = Role.duenio;
    s.ownerAddress = address.toLowerCase();
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
              const SizedBox(height: 20),
              WCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¿No sabes cuál es tu dirección?',
                      style: wk(size: 14, weight: 700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ábrela en MetaMask y toca el nombre de tu cuenta para copiarla, '
                      'o entra a Waliki web, conecta tu billetera y cópiala desde ahí.',
                      style: wk(
                        size: 12.5,
                        weight: 500,
                        color: kInkSoft,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _openWeb,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(
                          'Abrir Waliki web',
                          style: wk(size: 14, weight: 700, color: kBrandInk),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kBrandInk,
                          side: const BorderSide(color: kBrand, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
