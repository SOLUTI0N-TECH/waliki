import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chain.dart';
import '../config.dart';
import '../session.dart';
import '../ui.dart';
import '../wallet.dart';

enum _Step { form, waiting, done }

/// Registering a shop is the one action that needs the owner's signature, so
/// it happens in their real wallet: the app hands the prefilled form to the
/// web page and then watches the chain until the new shop shows up.
/// Returns the new merchantId via Navigator.pop.
class CrearComercioScreen extends StatefulWidget {
  final Session session;
  const CrearComercioScreen({super.key, required this.session});

  @override
  State<CrearComercioScreen> createState() => _CrearComercioScreenState();
}

class _CrearComercioScreenState extends State<CrearComercioScreen> {
  final _name = TextEditingController();
  late final TextEditingController _payout = TextEditingController(
    text: widget.session.ownerAddress ?? '',
  );

  _Step _step = _Step.form;
  Set<int> _before = {};
  bool _inApp = false;
  Merchant? _created;
  String? _error;
  Timer? _poll;
  int _seconds = 0;

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    _payout.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().length >= 3 &&
      RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(_payout.text.trim());

  Future<void> _firmar() async {
    final owner = widget.session.ownerAddress ?? '';
    setState(() {
      _error = null;
      _step = _Step.waiting;
      _seconds = 0;
    });

    try {
      _before = (await Chain.merchantsOf(owner)).map((m) => m.id).toSet();
    } catch (_) {
      _before = {};
    }

    // With a wallet connected we sign right here; otherwise we hand the
    // prefilled form to the web page, which is already proven to work.
    _inApp = Wallet.instance.isConnected;
    if (_inApp) {
      try {
        await Wallet.instance.registerMerchant(
          payout: _payout.text.trim(),
          name: _name.text.trim(),
        );
      } catch (e) {
        if (mounted) {
          setState(() {
            _step = _Step.form;
            _error = 'La billetera rechazo o no pudo firmar: $e';
          });
        }
        return;
      }
    } else {
      final uri = Uri.parse('${WalikiConfig.payBaseUrl}/registro').replace(
        queryParameters: {'n': _name.text.trim(), 'p': _payout.text.trim()},
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      setState(() => _seconds += 4);
      _buscar();
    });
  }

  Future<void> _buscar() async {
    final owner = widget.session.ownerAddress ?? '';
    try {
      final list = await Chain.merchantsOf(owner);
      final nuevo = list.where((m) => !_before.contains(m.id)).toList();
      if (nuevo.isNotEmpty && mounted) {
        _poll?.cancel();
        setState(() {
          _created = nuevo.last;
          _step = _Step.done;
        });
      }
    } catch (_) {
      // transient RPC errors: keep polling
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WalikiBar(
        title: _step == _Step.done ? 'Comercio creado' : 'Crear comercio',
        back: _step != _Step.waiting,
      ),
      body: SafeArea(
        child: switch (_step) {
          _Step.form => _buildForm(),
          _Step.waiting => _buildWaiting(),
          _Step.done => _buildDone(),
        },
      ),
    );
  }

  Widget _buildForm() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tu comercio queda registrado en la blockchain con una sola firma. '
          'La dirección de cobro queda candada a tu billetera: ningún empleado '
          'puede desviar los pagos.',
          style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
        ),
        const SizedBox(height: 20),
        Text(
          'NOMBRE DEL COMERCIO',
          style: wk(size: 11, weight: 700, color: kInkSoft, tracking: 0.05),
        ),
        const SizedBox(height: 8),
        _field(
          _name,
          'Como lo conocen tus clientes',
          mono: false,
          maxLength: 48,
        ),
        const SizedBox(height: 18),
        Text(
          'DIRECCIÓN DE COBRO',
          style: wk(size: 11, weight: 700, color: kInkSoft, tracking: 0.05),
        ),
        const SizedBox(height: 8),
        _field(_payout, '0x…', mono: true),
        const SizedBox(height: 6),
        Text(
          'Por defecto, tu propia billetera. Aquí llega cada venta.',
          style: wk(size: 12, weight: 500, color: kInkSoft),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
        const SizedBox(height: 22),
        PrimaryButton('Firmar en mi billetera', onTap: _valid ? _firmar : null),
        const SizedBox(height: 10),
        Text(
          Wallet.instance.isConnected
              ? 'Tu billetera te pedirá aprobar la transacción. Al confirmarse, '
                    'la app detecta tu comercio sola.'
              : 'Se abrirá Waliki web con estos datos ya cargados. Firmas ahí con '
                    'tu billetera y vuelves: la app detecta tu comercio sola.',
          textAlign: TextAlign.center,
          style: wk(size: 12, weight: 500, color: kInkSoft, height: 1.5),
        ),
      ],
    ),
  );

  Widget _buildWaiting() => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 52,
          height: 52,
          child: CircularProgressIndicator(strokeWidth: 3.5, color: kBrand),
        ),
        const SizedBox(height: 24),
        Text(
          'Esperando tu firma…',
          style: wk(size: 20, weight: 800, tracking: -0.03),
        ),
        const SizedBox(height: 10),
        Text(
          _inApp
              ? 'Aprueba la transacción en tu billetera. Cuando entre en un '
                    'bloque, la app lo detecta sola.'
              : 'Completa el registro en la ventana que se abrió. Cuando la '
                    'transacción entre en un bloque, la app lo detecta sola.',
          textAlign: TextAlign.center,
          style: wk(size: 13, weight: 500, color: kInkSoft, height: 1.55),
        ),
        const SizedBox(height: 18),
        WChip(
          'consultando la cadena · ${_seconds}s',
          bg: kSurface2,
          fg: kInkSoft,
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 46,
          child: OutlinedButton(
            onPressed: _buscar,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBrand, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Ya firmé — buscar ahora',
              style: wk(size: 14, weight: 700, color: kBrandInk),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            _poll?.cancel();
            setState(() => _step = _Step.form);
          },
          child: Text(
            'Cancelar',
            style: wk(size: 14, weight: 600, color: kInkSoft),
          ),
        ),
      ],
    ),
  );

  Widget _buildDone() {
    final m = _created!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: kBrandTint,
            ),
            child: const Icon(Icons.check_rounded, size: 52, color: kBrand),
          ),
          const SizedBox(height: 20),
          Text(
            '¡Comercio registrado!',
            textAlign: TextAlign.center,
            style: wk(size: 24, weight: 800, tracking: -0.03),
          ),
          const SizedBox(height: 8),
          Text(
            m.displayName,
            textAlign: TextAlign.center,
            style: wk(size: 17, weight: 700, color: kBrandInk),
          ),
          const SizedBox(height: 16),
          WCard(
            child: Column(
              children: [
                _row('Número de comercio', '#${m.id}'),
                const SizedBox(height: 9),
                _row('Cobra en', short(m.payout)),
                const SizedBox(height: 9),
                _row('Dirección de cobro', 'candada a tu billetera'),
              ],
            ),
          ),
          const Spacer(),
          PrimaryButton(
            'Abrir la caja',
            onTap: () => Navigator.of(context).pop(m.id),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: wk(size: 12.5, weight: 500, color: kInkSoft)),
      Flexible(
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: wk(size: 13, weight: 600),
        ),
      ),
    ],
  );

  Widget _field(
    TextEditingController c,
    String hint, {
    bool mono = false,
    int? maxLength,
  }) => TextField(
    controller: c,
    maxLength: maxLength,
    style: wk(size: mono ? 13 : 15, weight: mono ? 500 : 600, mono: mono),
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      hintText: hint,
      counterText: '',
      hintStyle: wk(
        size: mono ? 13 : 15,
        weight: 500,
        color: kInkSoft,
        mono: mono,
      ),
      filled: true,
      fillColor: kSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kLine, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBrand, width: 1.5),
      ),
    ),
  );
}
