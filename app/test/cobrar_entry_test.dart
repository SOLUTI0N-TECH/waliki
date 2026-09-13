import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waliki_app/screens/cobrar.dart';
import 'package:waliki_app/session.dart';

void main() {
  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: CobrarScreen(
          session: Session(
            role: Role.cajero,
            merchantId: 1,
            cashierAddress: '0x${'11' * 20}',
            rate: '11.51',
          ),
          merchantId: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String keys) async {
    for (final k in keys.split('')) {
      await tester.tap(find.byKey(ValueKey('keypad-$k')));
      await tester.pump();
    }
  }

  // Two amount fields, the keypad and two charge buttons have to share the
  // screen: an overflow here fails the test on its own.
  for (final size in const [Size(412, 915), Size(360, 640)]) {
    testWidgets(
      'the charge screen fits a ${size.width.toInt()}x${size.height.toInt()} phone',
      (tester) async {
        await open(tester, size);
        expect(find.text('Cobrar USDT'), findsOneWidget);
        expect(find.text('Cobrar Bs'), findsOneWidget);
        expect(find.byIcon(Icons.swap_vert_rounded), findsOneWidget);
      },
    );
  }

  testWidgets('typing dollars fills in the bolivianos below', (tester) async {
    await open(tester, const Size(412, 915));
    await type(tester, '10');
    expect(find.text('10'), findsOneWidget);
    expect(find.text('115,10'), findsOneWidget);
  });

  testWidgets('swapping puts bolivianos on top and types into them', (
    tester,
  ) async {
    await open(tester, const Size(412, 915));
    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pump();
    await type(tester, '100');
    expect(find.text('100'), findsOneWidget);
    expect(find.text('8,69'), findsOneWidget);
  });

  testWidgets('a price typed in dollars goes on-chain with no deadline', (
    tester,
  ) async {
    await open(tester, const Size(412, 915));
    await type(tester, '5');
    await tester.tap(find.text('Cobrar USDT'));
    await tester.pump();
    expect(find.text('Esperando el pago…'), findsOneWidget);
    expect(find.textContaining('vence en'), findsNothing);
    // Disposing the screen cancels its polling timer.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a price typed in bolivianos goes on-chain with a deadline', (
    tester,
  ) async {
    await open(tester, const Size(412, 915));
    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pump();
    await type(tester, '100');
    await tester.tap(find.text('Cobrar USDT'));
    await tester.pump();
    expect(find.textContaining('vence en'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
