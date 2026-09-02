import 'package:flutter_test/flutter_test.dart';
import 'package:waliki_app/main.dart';

void main() {
  testWidgets('PIN gate renders and asks for the cashier PIN', (tester) async {
    await tester.pumpWidget(const WalikiApp());
    expect(find.text('Ingresa tu PIN de cajero'), findsOneWidget);
    expect(find.text('waliki'), findsOneWidget);
    // Wrong PIN shows the error and never unlocks
    await tester.ensureVisible(find.text('9'));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('9'));
      await tester.pump();
    }
    expect(find.text('PIN incorrecto — intenta de nuevo'), findsOneWidget);
  });
}
