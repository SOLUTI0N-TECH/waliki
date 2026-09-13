import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:waliki_app/caja_code.dart';
import 'package:waliki_app/caja_qr.dart';

void main() {
  const code = '7-KWE3-MYSD-BT7G-9HN1';

  testWidgets('el QR se anuncia con el código y ese código es escaneable', (
    tester,
  ) async {
    // The payload is a contract between two phones: this screen draws it and
    // escanear_caja.dart reads it back through cajaCodeFromScan. Wrapping it
    // in a URL or a waliki:// link would still render and stop linking, with
    // nothing gained -- the app handles no incoming deep links.
    //
    // QrImageView keeps its data private, so the semantics label is what makes
    // the payload observable from here.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CajaQr(code: code))),
    );

    expect(find.byType(QrImageView), findsOne);
    expect(find.bySemanticsLabel(code), findsOne);
    expect(cajaCodeFromScan(code), code);
  });

  testWidgets('el diálogo trae el QR de vuelta con el código legible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  mostrarCajaQr(context, code: code, label: 'Caja 1'),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // No semantics check here: a Material dialog merges its contents into one
    // node, so the QR's own label is swallowed by the title. The code sits
    // right under it in plain text, which is what gets read out anyway.
    expect(find.byType(QrImageView), findsOne);
    expect(find.text(code), findsOne);
    expect(find.text('Caja 1'), findsOne);
  });
}
