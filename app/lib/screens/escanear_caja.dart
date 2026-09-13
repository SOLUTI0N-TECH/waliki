import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../caja_code.dart';
import '../ui.dart';

/// Reads a register code QR and hands it back through `Navigator.pop`.
///
/// Returns the canonical code, or null when the cashier backed out -- which
/// includes backing out because the camera was refused. The caller always has
/// the typed field to fall back on, so this screen never has to insist.
class EscanearCajaScreen extends StatefulWidget {
  const EscanearCajaScreen({super.key});

  @override
  State<EscanearCajaScreen> createState() => _EscanearCajaScreenState();
}

class _EscanearCajaScreenState extends State<EscanearCajaScreen> {
  final _controller = MobileScannerController(
    // Only QRs, and only once per code: without noDuplicates the same frame
    // fires over and over while the phone is being held still.
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Detection keeps running while the pop animation plays, so without this
  /// the next frame pops a second time and takes the caller's screen with it.
  bool _handled = false;

  /// Set when something was read that is not a register code. Deliberately not
  /// a reason to close: a phone pointed at a counter reads price tags and the
  /// shop's own payment QR before it finds the right one.
  String? _rechazado;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    // Frames keep arriving from the platform after the screen is gone.
    if (_handled || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final code = cajaCodeFromScan(raw);
      if (code != null) {
        _handled = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
    if (mounted) {
      setState(() => _rechazado = 'Ese QR no es un código de caja.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBrandInk,
      appBar: WalikiBar(
        title: 'Escanear código',
        back: true,
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: on ? 'Apagar la luz' : 'Encender la luz',
                onPressed: _controller.toggleTorch,
                icon: Icon(
                  on
                      ? Icons.flashlight_on_rounded
                      : Icons.flashlight_off_rounded,
                  size: 19,
                  color: on ? kBrand : kInkSoft,
                ),
              );
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = (constraints.maxWidth * 0.72).clamp(180.0, 280.0);
          final window = Rect.fromCenter(
            center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
            width: side,
            height: side,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                // Only what is inside the frame is decoded, so the shop's own
                // QRs sitting next to the phone do not keep interrupting.
                scanWindow: window,
                errorBuilder: (context, error) => _SinCamara(error: error),
              ),
              _Marco(window: window),
              Positioned(
                left: 20,
                right: 20,
                bottom: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_rechazado != null) ...[
                      _Aviso(text: _rechazado!, danger: true),
                      const SizedBox(height: 10),
                    ],
                    const _Aviso(
                      text: 'Apunta al QR que te muestra el dueño del comercio.',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Dims everything outside the scan window and draws the frame on top.
class _Marco extends StatelessWidget {
  final Rect window;
  const _Marco({required this.window});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Color(0x99031740),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              // srcOut punches the second layer out of the first one.
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Positioned.fromRect(
                rect: window,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned.fromRect(
          rect: window,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: kBrandCyan, width: 2.5),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Aviso extends StatelessWidget {
  final String text;
  final bool danger;
  const _Aviso({required this.text, this.danger = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: danger ? kDanger : const Color(0xCC031740),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: wk(size: 13, weight: 600, color: Colors.white, height: 1.4),
    ),
  );
}

/// Shown instead of the preview when the camera is refused or missing.
///
/// The way out is explicit: nobody is left staring at a black rectangle
/// wondering whether the scanner is slow or broken, and the typed code is one
/// tap away.
class _SinCamara extends StatelessWidget {
  final MobileScannerException error;
  const _SinCamara({required this.error});

  String get _mensaje {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Waliki necesita permiso para usar la cámara. Puedes darlo '
            'desde los ajustes del teléfono, o escribir el código a mano.';
      case MobileScannerErrorCode.unsupported:
        return 'Este teléfono no puede escanear códigos. Escribe el código '
            'a mano.';
      default:
        return 'No se pudo abrir la cámara. Escribe el código a mano.';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    color: kBrandInk,
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.no_photography_outlined, size: 44, color: kBrandCyan),
        const SizedBox(height: 16),
        Text(
          _mensaje,
          textAlign: TextAlign.center,
          style: wk(size: 14, weight: 600, color: Colors.white, height: 1.5),
        ),
        const SizedBox(height: 22),
        PrimaryButton(
          'Escribir el código',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
