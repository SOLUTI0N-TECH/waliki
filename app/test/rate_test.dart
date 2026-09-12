import 'package:flutter_test/flutter_test.dart';
import 'package:waliki_app/rate.dart';

void main() {
  // The exact shape paralelo.bo returns, captured 2026-09-12.
  const real =
      '{"timestamp":"2026-09-12T03:07:07.874Z","buy":11.51,"sell":11.32,'
      '"median":11.41,"spreadPct":-1.6728,"sourceCount":4,'
      '"methodologyVersion":"ec2-backend"}';

  test('reads the live payload', () {
    final q = RateQuote.parse(real, DateTime.now())!;
    expect(q.buy, 11.51);
    expect(q.sell, 11.32);
    expect(q.median, 11.41);
    expect(q.at.toUtc().hour, 3);
  });

  test('buy is the side the register charges on', () {
    final q = RateQuote.parse(real, DateTime.now())!;
    // Bs 100 of merchandise, priced at the rate to acquire a dollar.
    final units = BigInt.from((100 / q.buy * 1e6).round());
    expect(units, BigInt.from(8688097));
    // Cashing that straight back to Bs settles at the lower sell side, which
    // is what the spread costs a shop that does not hold its USDT.
    expect(units.toDouble() / 1e6 * q.sell, lessThan(100));
  });

  test('a broken payload leaves the previous quote standing', () {
    final now = DateTime.now();
    expect(RateQuote.parse('not json', now), isNull);
    expect(RateQuote.parse('{"buy":0}', now), isNull);
    expect(RateQuote.parse('{"buy":-3}', now), isNull);
    expect(RateQuote.parse('{"sell":11.3}', now), isNull);
    expect(RateQuote.parse('[]', now), isNull);
  });

  test('a quote missing its siblings still works off buy alone', () {
    final q = RateQuote.parse('{"buy":11.5}', DateTime.now())!;
    expect(q.sell, 11.5);
    expect(q.median, 11.5);
  });

  test('staleness is measured from when this device fetched it', () {
    RateQuote at(Duration ago) => RateQuote(
      buy: 11.5,
      sell: 11.3,
      median: 11.4,
      at: DateTime.now(),
      fetched: DateTime.now().subtract(ago),
    );
    expect(at(const Duration(minutes: 1)).stale, isFalse);
    expect(at(Rate.freshFor + const Duration(seconds: 30)).stale, isTrue);
    expect(at(const Duration(seconds: 20)).ageLabel, 'recién');
    expect(at(const Duration(minutes: 7)).ageLabel, 'hace 7 min');
    expect(at(const Duration(hours: 3)).ageLabel, 'hace 3 h');
  });
}
