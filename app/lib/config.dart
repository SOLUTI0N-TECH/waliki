/// Static demo configuration.
/// Contract addresses come from contracts/deployments/baseSepolia.json.
class WalikiConfig {
  static const int chainId = 84532; // Base Sepolia
  static const String rpcUrl = 'https://sepolia.base.org';

  /// Optional private fallback RPC (event-day insurance), injected at build
  /// or run time: --dart-define=WALIKI_RPC=https://... Never committed.
  static const String rpcFallback = String.fromEnvironment('WALIKI_RPC');
  static const String router = '0x5b003974862aa4ad00e09dfcade43abde593bbdc';
  static const String explorer = 'https://sepolia.basescan.org';

  /// Reown (WalletConnect) project id for the in-app wallet connection.
  /// Injected at build time so it is never committed:
  ///   `--dart-define=WALIKI_REOWN_ID=<project id>`
  static const String reownProjectId = String.fromEnvironment(
    'WALIKI_REOWN_ID',
  );
  static const int quoteMinutes = 15;
  // Block the router was deployed in. Leave it behind and every history scan
  // reads thousands of blocks where the contract did not exist yet; leave it
  // ahead and sales go missing.
  static const int deployBlock = 46743512;

  /// Shows the phase 2/3 navigable mockups (Modo Facil, Tienda, Puntaje) on
  /// the home screen. Off while they do nothing; flip to true to walk the
  /// full product vision in the pitch.
  static const bool showVision = false;

  /// Base URL of the web payment page the QR points to: the public site, so
  /// any phone can pay over mobile data — no shared WiFi needed.
  /// Still editable at runtime from the charge screen (pencil icon).
  static String payBaseUrl = 'https://waliki-gules.vercel.app';
}
