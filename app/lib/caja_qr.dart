import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'ui.dart';

/// The register code as a QR, so the cashier's phone can read it off the
/// owner's screen instead of someone typing sixteen characters.
///
/// What travels inside is the code and nothing else -- `7-KWE3-MYSD-BT7G-9HN1`.
/// Not a URL, not a `waliki://` link: `parseCajaCode` already accepts this
/// exact string, the app handles no incoming deep links, and a stranger's
/// camera app shows harmless text rather than something inviting to tap.
class CajaQr extends StatelessWidget {
  final String code;
  final double size;

  /// Shown under the QR. Null hides it, for places that already say it.
  final String? caption;

  const CajaQr({
    super.key,
    required this.code,
    this.size = 184,
    this.caption = 'Tu cajero lo escanea desde su teléfono',
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          // The quiet zone has to be white even when the card behind is not:
          // QrImageView paints on a transparent background.
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: QrImageView(
          data: code,
          size: size,
          // Level M instead of the package default L: this one is read from
          // one screen to another, at an angle and with reflections. The
          // payload is twenty-one uppercase characters, so qr_flutter encodes
          // it in alphanumeric mode and the extra correction costs no version.
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          backgroundColor: Colors.white,
          // The package announces "qr code" by default, which helps nobody.
          // This says the code out loud instead -- and it is the only way the
          // payload is visible from outside the widget, which is what
          // caja_qr_test.dart holds on to.
          semanticsLabel: code,
        ),
      ),
      if (caption != null) ...[
        const SizedBox(height: 10),
        Text(
          caption!,
          textAlign: TextAlign.center,
          style: wk(size: 12, weight: 500, color: kInkSoft),
        ),
      ],
    ],
  );
}

/// Brings the code back after the owner left the "new register" screen.
///
/// Without this the QR is a single shot: a cashier who was not standing there
/// when the register was created ends up typing the code anyway.
Future<void> mostrarCajaQr(
  BuildContext context, {
  required String code,
  required String label,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: wk(size: 17, weight: 700, tracking: -0.02),
            ),
            const SizedBox(height: 14),
            CajaQr(code: code, caption: null),
            const SizedBox(height: 14),
            // Monospace on purpose: sixteen letters and digits read out loud
            // need a 0 that cannot be an O and a 1 that is not an l.
            Text(
              code,
              textAlign: TextAlign.center,
              style: wk(size: 16, weight: 800, color: kBrandInk, mono: true),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                    },
                    child: Text(
                      'Copiar código',
                      style: wk(size: 14, weight: 700, color: kBrandInk),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cerrar',
                      style: wk(size: 14, weight: 700, color: kInkSoft),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
