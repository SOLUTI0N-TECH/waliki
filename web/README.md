# Waliki — web (caja y página de pago)

Frontend de la Fase 1: **`/caja`** (cobro Bs → QR → pantalla verde) y **`/pay/:saleId`**
(página de pago del cliente). Vite + React + TypeScript · wagmi v3 + viem + Reown AppKit.

## Correr en desarrollo

1. Copia `.env.example` a `.env` y completa `VITE_REOWN_PROJECT_ID` (proyecto "Waliki" en
   dashboard.reown.com). `VITE_RPC_URL` es opcional (por defecto `https://sepolia.base.org`).
2. `npm install`
3. `npm run dev` → http://localhost:5173

## Build de producción

`npm run build` (tsc + vite) · `npm run preview` para servirlo localmente.

## Contratos

Red: **Base Sepolia** (chainId 84532). Los ABIs y direcciones llegan generados a
`src/contracts/waliki.json` — se regeneran desde `../contracts` con `npm run export-abi`
(corre solo después de cada deploy). No editar ese archivo a mano.
