# Paso 0 — Cuentas y preparación (antes de escribir código)

> ~30–40 min. Son acciones **tuyas** (crear cuentas, instalar wallets, pedir fondos de prueba).
> Yo no puedo crear cuentas ni instalar extensiones por ti, pero te guío en cada una.
> Hazlas ahora porque los faucets son lentos/limitados y bloquean si se piden apurado.

## Checklist

### 1. Reown (WalletConnect) — Project ID
- Entra a **https://cloud.reown.com**, crea una cuenta gratis.
- Crea un proyecto → tipo **AppKit**.
- Copia el **Project ID** (lo usa la web para el modal de conexión y el deep link a MetaMask móvil).
- Guárdalo; irá en `web/.env` como `VITE_REOWN_PROJECT_ID`.

### 2. MetaMask
- Extensión en tu **PC** (navegador de desarrollo): https://metamask.io
- App de MetaMask en **1–2 teléfonos** (para probar el flujo real del cliente que escanea el QR).
- Agrega la red **Base Sepolia** (o deja que la web la agregue sola en el Paso 3):
  - Nombre: `Base Sepolia`
  - RPC: `https://sepolia.base.org`
  - Chain ID: `84532`
  - Símbolo: `ETH`
  - Explorador: `https://sepolia.basescan.org`

### 3. ETH de prueba (gas) — Base Sepolia, para ~3 direcciones
Necesitas ETH de testnet para pagar gas (del dueño, y de los teléfonos que pagarán en el demo).
- Faucet de Coinbase: **https://portal.cdp.coinbase.com/products/faucet** (Base Sepolia)
- Alternativa: **https://www.alchemy.com/faucets/base-sepolia**
- Pide para: (a) tu dirección de PC (dueño/deployer), (b) teléfono #1, (c) teléfono #2.
- Nota: algunos faucets exigen un saldo mínimo en mainnet o login. Si uno falla, usa el otro.

### 4. (Opcional pero recomendado) RPC propio
Los RPC públicos limitan consultas de eventos y cortan WebSocket. Para el listener del navegador:
- Crea una app gratis en **Alchemy** o **QuickNode** para **Base Sepolia** y copia la URL HTTPS/WSS.
- Irá en `web/.env` como `VITE_RPC_URL`.

## Cuando termines
Anota estos valores (los pega el que arme la web; NO subir el `.env` al repo):
```
VITE_REOWN_PROJECT_ID=...
VITE_RPC_URL=...              # opcional; si no, se usa https://sepolia.base.org
Dirección deployer (PC):     0x...
Dirección teléfono #1:       0x...
Dirección teléfono #2:       0x...
```

Con esto listo pasamos al **Paso 1** (scaffolding de `contracts/` y `web/`) y al **Paso 2**
(contratos `TestUSDT` + `WalikiRouter`).
