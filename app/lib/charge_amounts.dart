/// The two currencies the register shows side by side.
enum Money { usd, bs }

/// One amount, seen in both currencies.
///
/// The cashier types into one field and the other is always derived from it
/// at the market rate. [source] remembers which one was typed, so a
/// conversion is never fed back into itself: swapping the fields or reading
/// the derived figure cannot make the price drift by a centavo.
class ChargeAmounts {
  /// Which field holds what the cashier typed. Null before the first key.
  final Money? source;

  /// What was typed into [source], with a comma as the decimal mark.
  final String text;

  /// Bolivianos per USDT.
  final double? rate;

  const ChargeAmounts({this.source, this.text = '', this.rate});

  /// The typed figure, or null while it is not a positive number yet.
  double? get typed {
    final v = double.tryParse(text.replaceAll(',', '.'));
    return (v != null && v > 0) ? v : null;
  }

  bool get isEmpty => source == null || typed == null;

  double? get _rate => (rate != null && rate! > 0) ? rate : null;

  /// USDT in micro-units. On-chain it is what the customer pays; through the
  /// bank QR it is what the shop receives.
  BigInt? get units {
    final t = typed;
    if (t == null) return null;
    final double usd;
    if (source == Money.usd) {
      usd = t;
    } else {
      final r = _rate;
      if (r == null) return null;
      usd = t / r;
    }
    final u = BigInt.from((usd * 1e6).round());
    return u > BigInt.zero ? u : null;
  }

  /// Bolivianos, with at most two decimals: the precision a bank QR accepts.
  double? get bs {
    final t = typed;
    if (t == null) return null;
    if (source == Money.bs) return t;
    final r = _rate;
    if (r == null) return null;
    return (t * r * 100).round() / 100;
  }

  /// Applies one keypad press to [text]: digits, a single decimal comma that
  /// never opens the amount, and `<` for backspace. Money has two decimals,
  /// so a third is refused here instead of being silently rounded away later.
  static String press(String text, String key) {
    if (key == '<') {
      return text.isEmpty ? text : text.substring(0, text.length - 1);
    }
    if (key == ',') {
      return (text.isEmpty || text.contains(',')) ? text : '$text,';
    }
    if (text.length >= 9) return text;
    final comma = text.indexOf(',');
    if (comma >= 0 && text.length - comma > 2) return text;
    // A lone zero before the comma means nothing: "05" is 5.
    if (text == '0') return key;
    return '$text$key';
  }
}
