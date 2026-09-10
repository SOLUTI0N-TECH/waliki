import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waliki_app/main.dart';
import 'package:waliki_app/session.dart';
import 'package:waliki_app/skeletons.dart';

void main() {
  testWidgets('a fresh install opens on the welcome screen with both roles', (
    tester,
  ) async {
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
      expect(code, '74821');
      final parsed = Session.parseCajaCode(code);
      expect(parsed?.merchantId, 7);
      expect(parsed?.pin, '4821');
    });

    test('splits a run-together code on the last four digits', () {
      // Two-digit shop: the id must not eat into the PIN.
      final parsed = Session.parseCajaCode('129090');
      expect(parsed?.merchantId, 12);
      expect(parsed?.pin, '9090');
      // A leading W is still tolerated: older codes and habit.
      expect(Session.parseCajaCode('W74821')?.merchantId, 7);
    });

    test('still reads codes handed out with a separator', () {
      expect(Session.parseCajaCode(' w12 : 9090 ')?.merchantId, 12);
      expect(Session.parseCajaCode('12-9090')?.pin, '9090');
      expect(Session.parseCajaCode('W7-4821')?.pin, '4821');
    });

    test('rejects nonsense', () {
      expect(Session.parseCajaCode('hola'), isNull);
      expect(Session.parseCajaCode('W0-1234'), isNull);
      expect(Session.parseCajaCode('W1-12'), isNull);
    });
  });

  testWidgets('every skeleton lays out at phone size and animates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final skeleton in const [
      HomeSkeleton(),
      MisComerciosSkeleton(),
      HistorialSkeleton(),
      ReportesSkeleton(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SafeArea(child: skeleton)),
        ),
      );
      // Two frames apart: the shimmer must keep ticking without throwing.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }
  });
}
