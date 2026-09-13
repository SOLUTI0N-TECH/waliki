import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waliki_app/screens/cajero_setup.dart';
import 'package:waliki_app/session.dart';
import 'package:waliki_app/ui.dart';
import 'package:waliki_app/vault.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Vaults.instance = MemoryVault();
  });

  testWidgets('en el teléfono se puede escanear, y también escribir', (
    tester,
  ) async {
    // Sixteen characters copied by eye from one phone to another is what this
    // screen used to demand. Scanning is now the loud option -- but the typed
    // code has to survive it: it is the only way in when the camera is refused
    // or the owner is reading the code over the phone.
    //
    // Mounting this screen does not touch the camera: the scanner lives behind
    // a push, so this runs on a machine with no device attached.
    await tester.pumpWidget(
      MaterialApp(home: CajeroSetupScreen(session: Session())),
    );
    await tester.pump();

    expect(
      find.widgetWithText(PrimaryButton, 'Escanear código QR'),
      findsOne,
    );
    expect(find.text('o escríbelo'), findsOne);
    expect(find.byType(TextField), findsOne);
    expect(find.text('Vincular caja'), findsOne);
    expect(find.text('Pegar'), findsOne);
  }, skip: kIsWeb);
}
