# Waliki — Handoff del equipo (01/09/2026)

Qué está hecho, cómo se corre, qué falta y dónde está cada cosa. **Este archivo es el punto de
entrada para cualquiera que se sume al proyecto.** Plan completo: Google Doc "Waliki — Plan de
Proyecto (v4)".

## 1. Estado en una pantalla

| Pieza | Estado | Dónde |
|-------|--------|-------|
| Contratos (TestUSDT + WalikiRouter) | ✅ desplegados y probados en Base Sepolia (7/7 tests) | `contracts/` |
| Página de pago del cliente | ✅ probada con wallets reales (PC + teléfono) | `web/src/pages/Pay.tsx` |
| Caja (cobro Bs→QR→verde) | ✅ circuito completo probado | `web/src/pages/Caja.tsx` |
| Alta autoservicio de comercios | ✅ implementada (falta probar con otra wallet) | `web/src/pages/Registro.tsx` |
| App Waliki (Flutter) | ✅ onboarding por rol, alta de comercio, vinculación de cajeros, caja, historial y reportes con CSV | `app/` |
| Mockups de todas las fases | ✅ canvas de diseño + fuentes en el repo | `design/` |
| Publicación en Vercel | ✅ en línea: **https://waliki-gules.vercel.app** | proyecto `waliki` (root: `web/`) |
| APK para teléfonos | ⏳ pendiente (requiere Android SDK) | — |
| Video de respaldo + ensayo | ⏳ pendiente | — |

**Direcciones on-chain (Base Sepolia, chainId 84532)** — en `contracts/deployments/baseSepolia.json`:
- WalikiRouter: `0xd98869ebf0231ce1a56b145cb83db0ab2b1d382a`
- TestUSDT: `0xc0934b34b2b1654ac5dc41b8a867e1227e03093d`
- Explorador: https://sepolia.basescan.org

## 2. Arrancar en 10 minutos

Prerequisitos: **Node 22+** · para la app, **FVM** (`dart pub global activate fvm`).
No necesitas claves privadas ni desplegar nada: los contratos ya viven en la testnet.

```bash
git clone https://github.com/SOLUTI0N-TECH/waliki.git && cd waliki

# 1) Web (caja + página de pago)
cd web
cp .env.example .env      # pega el VITE_REOWN_PROJECT_ID que circula en el grupo
npm install
npm run dev -- --host     # --host = un teléfono en tu WiFi puede pagar

# 2) App Flutter
cd ../app
fvm install               # baja el Flutter pineado en .fvmrc
fvm flutter run -d chrome

# 3) Contratos (tests locales)
cd ../contracts
npm install && npm test
```

Datos del demo: **PIN de caja `1234`** · comercio #1 "Tienda Demo CBBA" · en la app, el QR apunta
a `WalikiConfig.payBaseUrl` y se edita con el lápiz de la pantalla de cobro (pon la URL que
imprime Vite como "Network", o la de Vercel cuando exista).

### Problemas típicos al clonar
1. **"Falta VITE_REOWN_PROJECT_ID"** → no copiaste `web/.env.example` a `web/.env`.
2. **Vite no arranca** → Node 18 no sirve; usa 20.19+ o 22.
3. **Flutter no resuelve el pubspec** → usa FVM (`fvm install` dentro de `app/`), no tu Flutter global.
4. **El QR de la app no abre nada en el teléfono** → la URL base apunta a la IP de otra PC; cámbiala con el lápiz.
5. **El historial da error de cadena** → recuerda: `eth_getLogs` va en ventanas de ≤10.000 bloques (ya está resuelto en el código; no lo "simplifiques").

## 3. Probar el circuito completo (el demo)

**Ya no hace falta levantar nada ni compartir WiFi** — el sitio está publicado:

1. Abre **https://waliki-gules.vercel.app/caja** en cualquier dispositivo → PIN `1234`.
2. Monto `175` → **Cobrar** → aparece el QR.
3. Con otro teléfono (datos móviles sirven): escanea el QR con la cámara → conectar →
   (faucet si hace falta) → aprobar → pagar.
4. La caja se pone **verde sola, con sonido** — disparada por el evento on-chain.

Mismo circuito con la app: `cd app && fvm flutter run -d chrome` → PIN → Cobrar. El QR ya apunta
al sitio publicado; el lápiz de esa pantalla permite cambiarlo si trabajas contra un `npm run dev`
local.

## 4. Mapa del repo

```
contracts/   Solidity + Hardhat. Scripts: deploy, register-demo-merchant,
             prefund-demo (carga tUSDT a los teléfonos), export-abi (ABIs→web),
             check-activity (diagnóstico on-chain)
web/         Vite + React + wagmi v3 + Reown AppKit
             /caja · /pay/:saleId · /registro
app/         Flutter (FVM). Solo lecturas JSON-RPC: la app nunca firma
design/      Mockups .dc.html + canvas.json (fuente del canvas de diseño)
docs/        PASO-0.md (cuentas) · HANDOFF.md (este archivo)
```

## 5. Reglas del proyecto (no negociables)

1. **No-custodial**: el riel de pagos nunca retiene fondos. Si algo va a tocar custodia o dinero
   fiat, se discute con el equipo antes de escribir código.
2. **Secretos fuera del repo**: `.env` está en `.gitignore`. La clave privada del deployer no se
   comparte por chat; el Project ID de Reown y la URL de Alchemy no son secretos críticos, pero
   tampoco se commitean.
3. **Comentarios de código en inglés**; UI, documentación y comunicación en español.
4. **La pasarela es web** (el QR es una URL); la app es la vitrina del producto.
5. Antes de tocar `WalikiRouter`, coordinar con **Daniel** (frente de permisos/roles).

## 6. Lo que sigue (por orden de valor)

1. **Vercel**: publicar `web/` → URL pública (el QR deja de depender de la WiFi). Es el mayor
   desbloqueo pendiente: dejar `VITE_REOWN_PROJECT_ID` y `VITE_RPC_URL` como variables de entorno.
2. **APK** de la app (requiere Android Studio/SDK) → app instalada en los teléfonos del demo.
3. **Kit demo**: prefinanciar el teléfono #2 (falta su dirección), grabar el **video de respaldo**.
4. **Ensayos del pitch** (guion de 2 minutos en el Doc v4, §11).
5. Contrato de **permisos/roles** (Daniel) y ratificaciones pendientes del plan (stablecoin
   propia, microcrédito).

## 7. Trampas conocidas (aprendidas a golpes)

- **`eth_getLogs` = 10.000 bloques máximo** en el RPC público; el plan gratis de **Alchemy solo
  permite 10** — por eso el público va primero y Alchemy es únicamente respaldo.
- Pagar USDT son **dos firmas** (`approve` + `pay`); en el teléfono, MetaMask no siempre vuelve
  solo al navegador: hay que abrir la app a mano.
- El pagador necesita **ETH de gas** (faucet de Base Sepolia) además de tUSDT.
- El **sonido en móvil** exige un gesto previo del usuario (por eso se "arma" al tocar COBRAR).
- El verde **siempre** se dispara leyendo la cadena (evento + polling), nunca por una captura del
  cliente: eso es el producto, no un detalle.
