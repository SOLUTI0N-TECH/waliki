import 'dart:convert';

/// Minimal hand-rolled ABI encoding and decoding.
///
/// The app deliberately ships no ABI file: it builds calldata here and filters
/// `eth_getLogs` with the hexes written into [chain.dart] and [wallet.dart].
/// That only stays safe because `contracts/test/waliki.test.ts` asserts every
/// one of those selectors and topic0 against the compiled contract -- if a
/// signature ever moves, that test fails instead of this app going quiet.

/// A 32-byte word: 64 lowercase hex characters, no `0x`.
String abiWord(BigInt value) => value.toRadixString(16).padLeft(64, '0');

String abiWordInt(int value) => abiWord(BigInt.from(value));

/// Left-pads any hex value (an address, a bytes32) into a word.
String abiWordHex(String hex) =>
    hex.replaceFirst('0x', '').toLowerCase().padLeft(64, '0');

/// Tail of a dynamic string: length word, then the UTF-8 bytes right-padded
/// to a whole word.
String abiStringTail(String value) {
  final bytes = utf8.encode(value);
  final len = abiWordInt(bytes.length);
  final body = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final padded = body.padRight(((body.length + 63) ~/ 64) * 64, '0');
  return '$len$padded';
}

BigInt abiUint(String word) => BigInt.parse(word, radix: 16);

/// Last 20 bytes of a word, as a `0x` address.
String abiAddr(String word) => '0x${word.substring(24)}';

/// Decodes a dynamic string laid out as: length word, then UTF-8 bytes.
String abiString(String hexFromLength) {
  if (hexFromLength.length < 64) return '';
  final len = abiUint(hexFromLength.substring(0, 64)).toInt();
  if (len == 0 || hexFromLength.length < 64 + len * 2) return '';
  final bytesHex = hexFromLength.substring(64, 64 + len * 2);
  final bytes = <int>[
    for (var i = 0; i < bytesHex.length; i += 2)
      int.parse(bytesHex.substring(i, i + 2), radix: 16),
  ];
  return utf8.decode(bytes, allowMalformed: true);
}
