import { base, baseSepolia, bsc } from '@reown/appkit/networks'
import { deployment } from '../contracts/waliki'

// Single source of truth for "which chain and which token are we on".
// Going live is a config change, not a code change: set these in web/.env
// (or as Vercel environment variables) and the whole app follows.
const env = import.meta.env

const CHAINS = {
  84532: { appkit: baseSepolia, explorer: 'https://sepolia.basescan.org' },
  8453: { appkit: base, explorer: 'https://basescan.org' },
  56: { appkit: bsc, explorer: 'https://bscscan.com' },
} as const

type ChainId = keyof typeof CHAINS

const chainId = Number(env.VITE_CHAIN_ID ?? 84532) as ChainId
const chain = CHAINS[chainId]
if (!chain) {
  throw new Error(
    `VITE_CHAIN_ID=${chainId} no está soportado. Redes válidas: ${Object.keys(CHAINS).join(', ')}`
  )
}

export const network = {
  chainId,
  appkitNetwork: chain.appkit,
  explorer: (env.VITE_EXPLORER as string | undefined) ?? chain.explorer,
  router: ((env.VITE_ROUTER as string | undefined) ?? deployment.walikiRouter) as `0x${string}`,
  token: ((env.VITE_TOKEN as string | undefined) ?? deployment.testUSDT) as `0x${string}`,
  tokenSymbol: (env.VITE_TOKEN_SYMBOL as string | undefined) ?? 'tUSDT',
  tokenDecimals: Number(env.VITE_TOKEN_DECIMALS ?? 6),
  /// Testnet-only affordances (the faucet button on the payment page)
  isTestnet: (env.VITE_IS_TESTNET as string | undefined) !== 'false' && chainId === 84532,
}
