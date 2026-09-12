import 'dart:math';
import 'dart:typed_data';

/// The short code the owner hands to a cashier: `7-K3NQ-7X2F-PM8T-QWRJ`.
///
/// It carries the shop id and the seed the cashier's app derives its identity
/// from ([cashier_identity.dart]). Nothing in here is a secret worth guessing:
/// the address it produces never holds funds, it only gets authorized on-chain
/// so the sales it issues can be attributed to a register.

/// Crockford base32. `I`, `L` and `O` are missing because they are read back
/// as `1`, `1` and `0`; `U` is missing so no code can spell something rude.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Bytes of entropy in a code. Ten is the only size that divides exactly into
/// 5-bit symbols (80 bits -> 16 characters), so there are no padding bits a
/// sloppy decoder could read two different ways.
const int cajaSeedBytes = 10;

/// 80 bits / 5 bits per symbol.
const int _codeChars = 16;

const int _groupSize = 4;

/// A fresh register seed.
Uint8List newCajaSeed() {
  final rnd = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(cajaSeedBytes, (_) => rnd.nextInt(256)),
  );
}

/// `<merchantId>-<four groups of four>`. The shop id stays in plain decimal:
/// it is the part people say out loud and the one the UI shows as `#7`.
String encodeCajaCode(int merchantId, Uint8List seed) {
  if (seed.length != cajaSeedBytes) {
    throw ArgumentError('La semilla debe tener $cajaSeedBytes bytes');
  }
  final symbols = _toBase32(seed);
  final groups = <String>[
    for (var i = 0; i < symbols.length; i += _groupSize)
      symbols.substring(i, i + _groupSize),
  ];
  return '$merchantId-${groups.join('-')}';
}

/// Reads a code back, tolerating how people actually type: any case, any
/// separator or none, `O` for `0` and `I`/`L` for `1`. Returns null for
/// anything else -- including the old digits-only codes, which should fail
/// loudly rather than parse into a shop id that means nothing now.
({int merchantId, Uint8List seed})? parseCajaCode(String raw) {
  final cleaned = _normalize(raw);
  // The blob is always exactly 16 symbols, so taking it off the end is what
  // makes the split unambiguous even when the separator is missing and the
  // seed happens to start with a digit.
  if (cleaned.length <= _codeChars) return null;
  final blob = cleaned.substring(cleaned.length - _codeChars);
  var idPart = cleaned.substring(0, cleaned.length - _codeChars);
  if (idPart.startsWith('W')) idPart = idPart.substring(1);
  if (idPart.isEmpty || !RegExp(r'^\d+$').hasMatch(idPart)) return null;

  final merchantId = int.tryParse(idPart);
  if (merchantId == null || merchantId <= 0) return null;
  final seed = _fromBase32(blob);
  if (seed == null || seed.length != cajaSeedBytes) return null;
  return (merchantId: merchantId, seed: seed);
}

/// Upper-cases and drops anything that could never belong to a code. Used by
/// the text field so what the cashier types looks like what the owner reads
/// out; the parser is the one that decides whether it is valid.
String formatCajaCodeInput(String raw) {
  final out = StringBuffer();
  for (final rune in raw.toUpperCase().runes) {
    final c = String.fromCharCode(rune);
    if (c == '-' || RegExp(r'^[0-9A-Z]$').hasMatch(c)) out.write(c);
  }
  return out.toString();
}

/// Big-endian bit stream, 5 bits per symbol. Spelled out rather than reusing
/// a "base32 of an integer" helper, which would drop leading zero bytes.
String _toBase32(Uint8List bytes) {
  var buffer = 0;
  var bits = 0;
  final out = StringBuffer();
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_alphabet[(buffer >> bits) & 0x1F]);
    }
  }
  return out.toString();
}

Uint8List? _fromBase32(String symbols) {
  var buffer = 0;
  var bits = 0;
  final out = <int>[];
  for (final rune in symbols.runes) {
    final value = _alphabet.indexOf(String.fromCharCode(rune));
    if (value < 0) return null; // covers U and everything outside the alphabet
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 0xFF);
    }
  }
  return Uint8List.fromList(out);
}

String _normalize(String raw) {
  final out = StringBuffer();
  for (final rune in raw.toUpperCase().runes) {
    final c = String.fromCharCode(rune);
    if (c == '-' || c == ' ' || c == ':' || c == '.' || c == '_') continue;
    // The confusions the alphabet drops these letters to avoid
    if (c == 'O') {
      out.write('0');
    } else if (c == 'I' || c == 'L') {
      out.write('1');
    } else {
      out.write(c);
    }
  }
  return out.toString();
}
