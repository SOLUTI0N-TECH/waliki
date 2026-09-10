import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waliki_app/main.dart';
import 'package:waliki_app/session.dart';

void main() {
  testWidgets('a fresh install opens on the welcome screen with both roles',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WalikiApp());
    await tester.pumpAndSettle();

    expect(find.text('Soy el dueño'), findsOneWidget);
    expect(find.text('Soy cajero'), findsOneWidget);
    // The test-phase marker must always be visible — honest, never loud
  });

  testWidgets('a linked register opens on the PIN gate', (tester) async {
    SharedPreferences.setMockInitialValues({
      'waliki.role': 'cajero',
      'waliki.merchantId': 1,
      'waliki.pin': '4821',
    });
    await tester.pumpWidget(const WalikiApp());
    await tester.pumpAndSettle();

    expect(find.text('Ingresa tu PIN de cajero'), findsOneWidget);
    expect(find.text('Caja del comercio #1'), findsOneWidget);
  });

  group('código de caja', () {
    test('builds and parses a round trip', () {
      final code = Session.buildCajaCode(7, '4821');
      expect(code, 'W7-4821');
      final parsed = Session.parseCajaCode(code);
      expect(parsed?.merchantId, 7);
      expect(parsed?.pin, '4821');
    });

    test('tolerates lowercase, spaces and a colon', () {
      expect(Session.parseCajaCode(' w12 : 9090 ')?.merchantId, 12);
      expect(Session.parseCajaCode('12-9090')?.pin, '9090');
    });

    test('rejects nonsense', () {
      expect(Session.parseCajaCode('hola'), isNull);
      expect(Session.parseCajaCode('W0-1234'), isNull);
      expect(Session.parseCajaCode('W1-12'), isNull);
    });
  });
}
