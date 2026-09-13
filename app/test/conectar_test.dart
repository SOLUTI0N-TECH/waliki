import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waliki_app/screens/conectar.dart';
import 'package:waliki_app/session.dart';
import 'package:waliki_app/ui.dart';
import 'package:waliki_app/vault.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Vaults.instance = MemoryVault();
  });

  testWidgets('en el teléfono no se puede entrar pegando una dirección', (
    tester,
  ) async {
    // The paste field used to sit one tap below the WalletConnect button.
    // Whoever took it got a shop they could never sign for: no session, every
    // signature bounced to the browser, and nothing said so. On web it is the
    // only option there is, so the check is platform-dependent.
    await tester.pumpWidget(
      MaterialApp(home: ConectarScreen(session: Session())),
    );
    await tester.pump();

    // Twice: the app bar title and the button itself.
    expect(find.text('Conectar billetera'), findsNWidgets(2));
    expect(find.widgetWithText(PrimaryButton, 'Conectar billetera'), findsOne);
    expect(find.text('Usar esta dirección'), findsNothing);
    expect(find.text('o pega tu dirección'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  }, skip: kIsWeb);

  test('conectar deja la dirección del dueño también como su caja', () async {
    // cobrar.dart stamps cashierAddress into every sale id and the router
    // rejects a sale whose cashier is not authorized. The owner is a cashier
    // of their own shops, so these two must never drift apart.
    final session = Session();
    const address = '0xBE5D6249EF221495DB1469348E694F824BD7E22D';

    session.role = Role.duenio;
    session.ownerAddress = address.toLowerCase();
    session.cashierAddress = session.ownerAddress;
    await session.save();

    final reloaded = await Session.load();
    expect(reloaded.ownerAddress, address.toLowerCase());
    expect(reloaded.cashierAddress, reloaded.ownerAddress);
  });
}
