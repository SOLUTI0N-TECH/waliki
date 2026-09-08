import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../session.dart';
import '../ui.dart';
import 'mis_comercios.dart';

/// The owner links their wallet address to this device.
///
/// Reading needs only the public address, so that is all we ask for. Anything
/// that needs a signature (registering a shop) opens the real wallet on the
/// web app — Waliki never sees a private key or a seed phrase.
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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(_ctrl.text.trim());

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
      if (mounted) {
        setState(() => _error = 'No se pudo abrir el navegador.');
      }
    }
  }

  Future<void> _connect() async {
    if (!_valid) {
      setState(() => _error = 'Esa dirección no es válida (0x… de 42 caracteres).');
      return;
    }
    setState(() => _busy = true);
    final s = widget.session;
    s.role = Role.duenio;
    s.ownerAddress = _ctrl.text.trim().toLowerCase();
    await s.save();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MisComerciosScreen(session: s)),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      shape: BoxShape.circle, color: kBrandTint),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      size: 38, color: kBrand),
                ),
              ),
              const SizedBox(height: 16),
              Text('Tu billetera, tus llaves',
                  textAlign: TextAlign.center,
                  style: wk(size: 21, weight: 800, tracking: -0.03)),
              const SizedBox(height: 8),
              Text(
                'Para mostrarte tus comercios y tus ventas solo necesitamos tu '
                'dirección pública. Cuando haya que firmar algo, se abre tu '
                'billetera — Waliki nunca ve tu frase secreta.',
                textAlign: TextAlign.center,
                style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
              ),
              const SizedBox(height: 22),
              Text('TU DIRECCIÓN',
                  style: wk(
                      size: 11, weight: 700, color: kInkSoft, tracking: 0.05)),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                style: wk(size: 13, weight: 500, mono: true),
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  hintText: '0x…',
                  hintStyle: wk(size: 13, weight: 500, color: kInkSoft, mono: true),
                  filled: true,
                  fillColor: kSurface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                    icon: const Icon(Icons.content_paste_rounded,
                        size: 19, color: kInkSoft),
                    onPressed: _paste,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: kDangerTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(_error!,
                      style: wk(size: 13, weight: 600, color: kDanger)),
                ),
              ],
              const SizedBox(height: 16),
              PrimaryButton('Conectar', onTap: _busy ? null : _connect),
              const SizedBox(height: 20),
              WCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('¿No sabes cuál es tu dirección?',
                        style: wk(size: 14, weight: 700)),
                    const SizedBox(height: 6),
                    Text(
                      'Ábrela en MetaMask y toca el nombre de tu cuenta para copiarla, '
                      'o entra a Waliki web, conecta tu billetera y cópiala desde ahí.',
                      style: wk(
                          size: 12.5, weight: 500, color: kInkSoft, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _openWeb,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text('Abrir Waliki web',
                            style: wk(size: 14, weight: 700, color: kBrandInk)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kBrandInk,
                          side: const BorderSide(color: kBrand, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
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
