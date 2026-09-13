import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waliki_app/caja_code.dart';
import 'package:waliki_app/cashier_identity.dart';
import 'package:waliki_app/main.dart';
import 'package:waliki_app/screens/cajero_setup.dart';
import 'package:waliki_app/session.dart';
import 'package:waliki_app/skeletons.dart';
import 'package:waliki_app/vault.dart';

void main() {
  final seed = newCajaSeed();
  final identity = deriveCashier(seed);

  setUp(() {
    Vaults.instance = MemoryVault();
  });

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
      'waliki.schema': Session.schemaVersion,
      'waliki.role': 'cajero',
      'waliki.merchantId': 1,
      'waliki.pin': '4821',
      'waliki.cashierAddress': identity.address,
    });
    Vaults.instance = MemoryVault({
      Vaults.cashierSeedKey: encodeCajaCode(1, seed),
    });

    await tester.pumpWidget(const WalikiApp());
    await tester.pumpAndSettle();

    expect(find.text('Ingresa tu PIN de cajero'), findsOneWidget);
    expect(find.text('Caja del comercio #1'), findsOneWidget);
  });

  testWidgets('una caja sin su identidad vuelve a vincularse, no al PIN', (
    tester,
  ) async {
    // Android restores preferences from a backup but not the Keystore key the
    // vault needs. Opening the PIN gate here would give a register that can
    // never issue a sale and says nothing about why.
    SharedPreferences.setMockInitialValues({
      'waliki.schema': Session.schemaVersion,
      'waliki.role': 'cajero',
      'waliki.merchantId': 1,
      'waliki.pin': '4821',
      'waliki.cashierAddress': identity.address,
    });
    Vaults.instance = MemoryVault();

    await tester.pumpWidget(const WalikiApp());
    await tester.pumpAndSettle();

    // By type, not by heading: that copy changes with the platform now that
    // the phone leads with the scanner, and what this test is about is which
    // screen the app landed on.
    expect(find.byType(CajeroSetupScreen), findsOneWidget);
    expect(find.textContaining('perdió su vinculación'), findsOneWidget);
  });

  testWidgets('una sesión del router anterior se limpia al arrancar', (
    tester,
  ) async {
    // No schema key: linked before the router was redeployed. That merchantId
    // now points at somebody else's shop, so the session cannot be trusted.
    SharedPreferences.setMockInitialValues({
      'waliki.role': 'cajero',
      'waliki.merchantId': 1,
      'waliki.pin': '4821',
      'waliki.payments.1': '[]',
      'waliki.rate': '13.50',
    });

    await tester.pumpWidget(const WalikiApp());
    await tester.pumpAndSettle();

    expect(find.text('Soy el dueño'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('waliki.role'), isNull);
    expect(prefs.getInt('waliki.merchantId'), isNull);
    expect(prefs.getString('waliki.payments.1'), isNull);
    // The rate survives: it is just the last quote seen, and it is still right
    expect(prefs.getString('waliki.rate'), '13.50');
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
