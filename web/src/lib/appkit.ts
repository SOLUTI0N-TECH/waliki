import { createAppKit } from '@reown/appkit/react'
import { WagmiAdapter } from '@reown/appkit-adapter-wagmi'
import { baseSepolia } from '@reown/appkit/networks'

// Reown project id lives in web/.env (VITE_REOWN_PROJECT_ID); never hardcode it.
const projectId = import.meta.env.VITE_REOWN_PROJECT_ID as string
if (!projectId) {
  throw new Error('Falta VITE_REOWN_PROJECT_ID en web/.env (ver web/.env.example)')
}

export const walikiNetwork = baseSepolia
const networks = [baseSepolia] as [typeof baseSepolia]

export const wagmiAdapter = new WagmiAdapter({
  networks,
  projectId,
  ssr: false,
})

// Module-scope init on purpose: importing this file once (main.tsx) boots the modal.
createAppKit({
  adapters: [wagmiAdapter],
  networks,
  defaultNetwork: baseSepolia,
  projectId,
  metadata: {
    name: 'Waliki',
    description: 'Cobros en USDT sin custodia (testnet)',
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
