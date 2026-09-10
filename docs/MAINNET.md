# Pasar Waliki a dinero real (USDT/USDC de verdad)

**La idea en una frase:** el código no cambia. Pasar a dinero real es cambiar la red y el token
en la configuración, desplegar el mismo contrato y apagar el faucet. Una hora de trabajo y unos
pocos dólares de gas.

Por qué es tan simple: `WalikiRouter` **no emite ni custodia** el token — solo mueve el que le
digas, del cliente al comercio. En la testnet le dijimos "usa tUSDT"; en producción le decimos
"usa el USDT real". Nada más.

---

## 1. La única decisión de fondo: en qué red

Esto no es un detalle técnico, es estratégico: define **si un cliente boliviano puede pagarte**.
Datos verificados en cadena (01/09/2026):

| Red | Token | Decimales | Gas por pago | Situación |
| :-- | :-- | :-- | :-- | :-- |
| **Base** | USDT `0xfde4C9…9bb2` | **6** | ~USD 0,001 | Mismo formato que nuestro token de prueba → **cero cambios de código** |
| **Base** | USDC `0x833589…2913` | **6** | ~USD 0,001 | La moneda dominante en Base (~4.200 M en circulación) |
| **BSC** | USDT (BEP20) `0x55d398…7955` | **18** ⚠️ | ~USD 0,10 | Donde vive buena parte del USDT boliviano, pero **18 decimales**: hay que ajustar el formato |
| TRON | USDT (TRC20) | 6 | ~USD 1 | El más usado en Bolivia, pero **no es EVM**: habría que reescribir contratos y frontend |

**La tensión real:** Base es técnicamente perfecta (gas casi gratis, nuestro código funciona tal
cual), pero el boliviano promedio tiene su USDT en **TRON o BSC**, porque es lo que Binance ofrece
por defecto. En Base tendría que hacer un puente primero.

**Recomendación para el piloto:** **Base + USDT**. El cliente del piloto lo elegimos nosotros (un
comercio amigo y sus clientes), así que la fricción del puente es manejable; a cambio, el gas es
casi cero y no tocamos una línea de código. Si el piloto demuestra demanda y la fricción del
puente resulta ser el freno, se despliega **el mismo contrato** en BSC (es EVM) ajustando los
decimales — el contrato ya está preparado para cualquier token ERC-20.

⚠️ **La trampa de los 18 decimales**: la app y la web formatean importes asumiendo 6 decimales.
En BSC, sin ajustar `VITE_TOKEN_DECIMALS`, todos los montos se verían mal por un factor de un
billón. Por eso los decimales son configuración, no una constante en el código.

## 2. Qué hay que hacer (la receta)

```bash
# 1) Desplegar el router apuntando al token real (NO se despliega TestUSDT)
cd contracts
TOKEN_ADDRESS=0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2 npx hardhat run scripts/deploy.ts --network base
# imprime la direccion del router y confirma simbolo/decimales del token
```

```bash
# 2) Configurar la web (web/.env, o variables de entorno en Vercel)
VITE_CHAIN_ID=8453
VITE_ROUTER=0x...        # la que imprimio el paso 1
VITE_TOKEN=0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2
VITE_TOKEN_SYMBOL=USDT
VITE_TOKEN_DECIMALS=6
VITE_IS_TESTNET=false    # apaga el faucet de tUSDT de la página de pago
```

```bash
# 3) La app Flutter: mismos valores en app/lib/config.dart
#    (chainId, rpcUrl, router, explorer)
```

3. El dueño **registra su comercio** en `/registro` (una firma) — ahora en la red real.
4. Listo: el QR ya cobra dinero real.

## 3. Qué cambia para las personas

| | Testnet (hoy) | Dinero real |
| :-- | :-- | :-- |
| Conseguir saldo | Botón de faucet, gratis | El cliente compra USDT (banco, exchange, P2P) |
| Gas del pagador | ETH de faucet | ETH real — centavos en Base |
| Si el comercio pierde su frase semilla | No pasa nada | **Pierde su dinero** — esto se vuelve serio |
| Un error en la tasa | Anécdota | Pérdida real |

## 4. Riesgos honestos antes de tocar dinero real

1. **El contrato no está auditado.** Mitigante fuerte de diseño: `WalikiRouter` **nunca retiene
   fondos** (el token va del pagador al comercio en la misma transacción) y no tiene función de
   retiro ni administrador. El peor caso no es robo, es una venta que no se registra.
2. **Custodia de llaves del comerciante**: si pierde su frase, pierde su dinero. Para el piloto:
   ayudar al dueño a respaldarla bien. Es exactamente el problema que resuelve la Fase 2
   (billetera sin frase semilla).
3. **Regulatorio**: software no-custodial, sin fiat — exposición mínima. Aun así, la **consulta
   legal formal antes de comercializar** sigue pendiente en el plan (v4 §6.2).
4. **Empieza pequeño**: primer piloto con montos bajos (Bs 10-50) y un comercio amigo. La primera
   venta real es un hito, no una prueba de estrés.

## 5. Cómo explicarlo en la presentación

> "Lo que ven corre en una red de pruebas para que nadie arriesgue dinero durante el demo. El
> mismo código, sin cambiar una línea, funciona con USDT real: solo le decimos al contrato qué
> moneda usar. La diferencia entre este demo y producción es un archivo de configuración."

Y si preguntan por qué no lo mostramos en producción directamente: porque un demo en vivo con
dinero real de terceros es irresponsable, y porque en la testnet cualquiera del jurado puede
pedir fondos gratis y **pagar él mismo** en 30 segundos.
