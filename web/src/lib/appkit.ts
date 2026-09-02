import { createAppKit } from '@reown/appkit/react'
import { WagmiAdapter } from '@reown/appkit-adapter-wagmi'
import { fallback, http } from 'wagmi'
import { network } from './network'

// Reown project id lives in web/.env (VITE_REOWN_PROJECT_ID); never hardcode it.
const projectId = import.meta.env.VITE_REOWN_PROJECT_ID as string
if (!projectId) {
  throw new Error('Falta VITE_REOWN_PROJECT_ID en web/.env (ver web/.env.example)')
}

export const walikiNetwork = network.appkitNetwork
const networks = [walikiNetwork] as [typeof walikiNetwork]

// Public RPC first (it allows wide eth_getLogs, which the history needs);
// the private endpoint from VITE_RPC_URL is an automatic fallback if the
// public one degrades — event-day insurance. Note: Alchemy's free tier caps
// eth_getLogs at 10 blocks, so it must never be the primary for logs.
const rpcFallback = (import.meta.env.VITE_RPC_URL as string | undefined) || undefined

export const wagmiAdapter = new WagmiAdapter({
  networks,
  projectId,
  ssr: false,
  transports: {
    [walikiNetwork.id]: rpcFallback ? fallback([http(), http(rpcFallback)]) : http(),
  },
})

// Module-scope init on purpose: importing this file once (main.tsx) boots the modal.
createAppKit({
  adapters: [wagmiAdapter],
  networks,
  defaultNetwork: walikiNetwork,
  projectId,
  metadata: {
    name: 'Waliki',
    description: 'Cobros en USDT sin custodia',
    url: window.location.origin,
    icons: [],
  },
  features: {
    analytics: false,
    email: false,
    socials: false,
    swaps: false,
    onramp: false,
  },
})
