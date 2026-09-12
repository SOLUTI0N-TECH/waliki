import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A parallel-market quote for the dollar.
///
/// Source: paralelo.bo, published under CC-BY-4.0. The licence asks for
/// credit, so [Rate.source] is named wherever the rate is shown.
class RateQuote {
  /// Bs to acquire one dollar. This is the side the register quotes: the shop
  /// takes USDT for merchandise, which is buying dollars by another route.
  final double buy;

  /// Bs received when selling a dollar — lower than [buy]. A shop that cashes
  /// its USDT straight back into Bs settles here, so the gap between the two
  /// is what that round trip costs.
  final double sell;
  final double median;

  /// When the source computed the quote, not when this device asked.
  final DateTime at;

  /// When this device last got it. Staleness is measured from here, because
  /// that is what the register can actually vouch for.
  final DateTime fetched;

  const RateQuote({
    required this.buy,
    required this.sell,
    required this.median,
    required this.at,
    required this.fetched,
  });

  static double? _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v');

  /// Returns null instead of throwing. A malformed payload must never take
  /// down a sale; it just leaves the previous quote standing.
  static RateQuote? _read(Object? decoded, DateTime fallbackFetched) {
    if (decoded is! Map) return null;
    final buy = _num(decoded['buy']);
    if (buy == null || !buy.isFinite || buy <= 0) return null;
    final fetched =
        DateTime.tryParse('${decoded['fetched']}') ?? fallbackFetched;
    return RateQuote(
      buy: buy,
      sell: _num(decoded['sell']) ?? buy,
      median: _num(decoded['median']) ?? buy,
      at: DateTime.tryParse('${decoded['timestamp']}')?.toLocal() ?? fetched,
      fetched: fetched,
    );
  }

  static RateQuote? parse(String body, DateTime fetched) {
    try {
      return _read(jsonDecode(body), fetched);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'buy': buy,
    'sell': sell,
    'median': median,
    'timestamp': at.toIso8601String(),
    'fetched': fetched.toIso8601String(),
  };

  Duration get age => DateTime.now().difference(fetched);
  bool get stale => age > Rate.freshFor;

  /// Short enough to sit under the rate field.
  String get ageLabel {
    final a = age;
    if (a.inMinutes < 1) return 'recién';
    if (a.inMinutes < 60) return 'hace ${a.inMinutes} min';
    if (a.inHours < 24) return 'hace ${a.inHours} h';
    return 'hace ${a.inDays} d';
  }
}

/// Keeps one parallel-market quote, cached on the device.
///
/// Deliberately not fetched per sale. The endpoint publishes
/// `Cache-Control: max-age=60`, so asking more often than once a minute cannot
/// return anything newer — it would only add latency with a customer waiting
/// at the counter, and turn a network hiccup into a failed sale. Equally not
/// fetched once a day: the parallel rate moves intraday, and the first sale of
/// the morning would be priced on yesterday's number.
///
/// So: serve the stored quote instantly, refresh behind it, never block.
class Rate {
  static const String source = 'paralelo.bo';
  static const String _url = 'https://paralelo.bo/api/v1/rate';
  static const String _key = 'waliki.rateQuote';

  /// Five minutes sits well inside the 15-minute window the QR quote already
  /// accepts, so a cached rate adds no error the design was not taking anyway.
  static const Duration freshFor = Duration(minutes: 5);

  /// Short on purpose: a slow network must not hold up a sale.
  static const Duration _timeout = Duration(seconds: 5);

  static RateQuote? _current;
  static Future<RateQuote?>? _inFlight;

  static RateQuote? get current => _current;

  /// The quote stored on this device. Instant, no network — this is what makes
  /// the register usable the moment it opens, and offline.
  static Future<RateQuote?> load() async {
    if (_current != null) return _current;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        _current = RateQuote._read(jsonDecode(raw), DateTime.now());
      }
    } catch (_) {
      // a corrupt entry is not worth a crash; the refresh below replaces it
    }
    return _current;
  }

  /// Fetches a newer quote, or returns null and leaves [current] untouched.
  /// Concurrent callers share the one request.
  static Future<RateQuote?> refresh({bool force = false}) {
    final have = _current;
    if (!force && have != null && !have.stale) return Future.value(have);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  static Future<RateQuote?> _fetch() async {
    try {
      final res = await http
          .get(Uri.parse(_url), headers: const {'accept': 'application/json'})
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final quote = RateQuote.parse(res.body, DateTime.now());
      if (quote == null) return null;
      _current = quote;
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(quote.toJson()));
      return quote;
    } catch (_) {
      // offline, timeout, rate-limited: the stored quote keeps working
      return null;
    }
  }
}
