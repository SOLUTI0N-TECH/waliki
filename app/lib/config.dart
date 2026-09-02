/// Static demo configuration.
/// Contract addresses come from contracts/deployments/baseSepolia.json.
class WalikiConfig {
  static const int chainId = 84532; // Base Sepolia
  static const String rpcUrl = 'https://sepolia.base.org';
  static const String router = '0xd98869ebf0231ce1a56b145cb83db0ab2b1d382a';
  static const String explorer = 'https://sepolia.basescan.org';
  static const int merchantId = 1; // "Tienda Demo CBBA"
  static const String cajaPin = '1234';
  static const int quoteMinutes = 15;
  static const int deployBlock = 46249000; // shortly before the router deploy

  /// Base URL of the web payment page the QR points to. Editable at runtime
  /// from the charge screen (until the site lives on a stable Vercel URL).
  /// Default: the demo PC's LAN address, so phones on the same WiFi can pay.
  static String payBaseUrl = 'http://192.168.100.29:5173';
}
