import { isAddress } from 'ethers';

/// Typed view of the .env. validate() returns this object and ConfigService
/// serves it, so every read downstream is already checked and normalized.
export interface EnvConfig {
  PORT: number;
  YESCA_API_BASE_URL: string;
  YESCA_API_TOKEN: string;
  RPC_URL: string;
  WALLET_PRIVATE_KEY: string;
  TUSDT_CONTRACT_ADDRESS: string;
  TUSDT_DECIMALS: number;
  WALIKI_ROUTER_ADDRESS: string;
}

const DEFAULT_YESCA_BASE_URL = 'https://dmb.miventa.dev/api';
/// contracts/deployments/baseSepolia.json. Defaulted so an existing .env keeps
/// working: only a contract redeploy needs this set by hand.
const DEFAULT_ROUTER = '0xd98869ebf0231ce1a56b145cb83db0ab2b1d382a';
const PRIVATE_KEY_RE = /^(0x)?[0-9a-fA-F]{64}$/;

/// Fail at boot instead of on the first request. Messages name the offending
/// variable and NEVER its value: this text lands in logs.
export function validate(raw: Record<string, unknown>): EnvConfig {
  // Values coming from a .env are always strings; anything else is "missing"
  const read = (key: string): string => {
    const value = raw[key];
    return typeof value === 'string' ? value.trim() : '';
  };

  const yescaToken = read('YESCA_API_TOKEN');
  const rpcUrl = read('RPC_URL');
  const privateKey = read('WALLET_PRIVATE_KEY');
  const tokenAddress = read('TUSDT_CONTRACT_ADDRESS');
  const routerAddress = read('WALIKI_ROUTER_ADDRESS') || DEFAULT_ROUTER;

  const missing = Object.entries({
    YESCA_API_TOKEN: yescaToken,
    RPC_URL: rpcUrl,
    WALLET_PRIVATE_KEY: privateKey,
    TUSDT_CONTRACT_ADDRESS: tokenAddress,
  })
    .filter(([, value]) => value === '')
    .map(([key]) => key);

  if (missing.length > 0) {
    throw new Error(
      `Faltan variables en backend/.env: ${missing.join(', ')}. ` +
        'Copia backend/.env.example y complétalas.',
    );
  }

  const invalid: string[] = [];
  if (!/^https?:\/\//i.test(rpcUrl)) {
    invalid.push('RPC_URL (debe ser una URL http/https completa)');
  }
  if (!PRIVATE_KEY_RE.test(privateKey)) {
    invalid.push(
      'WALLET_PRIVATE_KEY (64 caracteres hexadecimales, con o sin 0x)',
    );
  }
  if (!isAddress(tokenAddress)) {
    invalid.push(
      'TUSDT_CONTRACT_ADDRESS (no es una dirección Ethereum válida)',
    );
  }
  if (!isAddress(routerAddress)) {
    invalid.push(
      'WALIKI_ROUTER_ADDRESS (no es una dirección Ethereum válida)',
    );
  }
  if (invalid.length > 0) {
    throw new Error(
      `Variables inválidas en backend/.env: ${invalid.join(' · ')}`,
    );
  }

  return {
    PORT: Number.parseInt(read('PORT'), 10) || 3000,
    YESCA_API_BASE_URL: (
      read('YESCA_API_BASE_URL') || DEFAULT_YESCA_BASE_URL
    ).replace(/\/+$/, ''),
    YESCA_API_TOKEN: yescaToken,
    RPC_URL: rpcUrl,
    // MetaMask exports keys without the 0x prefix; ethers requires it
    WALLET_PRIVATE_KEY: privateKey.startsWith('0x')
      ? privateKey
      : `0x${privateKey}`,
    TUSDT_CONTRACT_ADDRESS: tokenAddress,
    TUSDT_DECIMALS: Number.parseInt(read('TUSDT_DECIMALS'), 10) || 6,
    WALIKI_ROUTER_ADDRESS: routerAddress,
  };
}
