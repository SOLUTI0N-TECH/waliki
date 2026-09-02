# Guion del demo — ETH Bolivia Buildathon 2026

Dos minutos en vivo. **Todo lo que se muestra como funcional es real**: transacciones verdaderas
en Base Sepolia, verificables por el jurado en el explorador.

## Antes de subir al escenario (checklist)

- [ ] Web publicada y abierta en la laptop (`/caja`), sesión iniciada con el PIN
- [ ] App Waliki abierta en la tablet/teléfono del "comercio"
- [ ] Teléfono del "cliente" con: ETH de gas, tUSDT (ya prefinanciado), MetaMask cerrada pero logueada
- [ ] Datos móviles activos en el teléfono del cliente (no depender del WiFi del evento)
- [ ] Video de respaldo abierto en una pestaña, listo por si algo falla
- [ ] Explorador (sepolia.basescan.org) abierto en otra pestaña, con la dirección del comercio
- [ ] Volumen del equipo al máximo (la pantalla verde suena)

## Guion (2 minutos)

**0:00 — El problema (20 s).**
"En Bolivia el comercio ya cobra en dólares digitales. ¿Cómo verifica que le pagaron? Mirando una
captura de pantalla que el cliente le muestra — y las capturas se falsifican. Peor: para verificar
de verdad, el dueño tendría que darle su cuenta al empleado. **Ningún empleado va a tener la cuenta
del jefe.**"

**0:20 — La solución, en vivo (50 s).**
"Esto es Waliki. La cajera entra con un PIN — sin billetera, sin acceso a nada."
→ Ingresar `175` → COBRAR → aparece el QR.
"El cliente escanea con su cámara. No instala nada."
→ El teléfono escanea, conecta, aprueba y paga.
→ **La caja se pone verde sola, con sonido.**
"Y esto es lo importante: **el verde no lo disparó nada que el cliente me mostró**. Lo disparó la
blockchain. Waliki leyó la cadena por su cuenta."

**1:10 — La prueba (20 s).**
→ Mostrar el comprobante: hash, bloque, y abrir el explorador.
"Ahí está el pago, público y verificable. Y fíjense: el dinero fue **directo del cliente al dueño**.
Waliki nunca lo tocó — no somos custodios."

**1:30 — El producto y la visión (30 s).**
→ Mostrar en la app: historial on-chain, y pasar por los mockups.
"Cualquier negocio se da de alta en minutos, solo, sin integración: eso es una pasarela.
Sobre esta base vienen el Modo Fácil — billetera y saldo para quien no sabe de cripto — y el
Comercio, donde el delivery cobra al instante en el mismo pago. Y como cada venta queda verificada
en la cadena, el comercio construye un historial que hoy no existe: la puerta al crédito."

## Si algo falla (plan B, en orden)

1. **El pago tarda**: sigue hablando — la caja también consulta la cadena cada 3 s, el verde llega igual.
2. **El teléfono no conecta / MetaMask no vuelve**: paga con el segundo teléfono (ya prefinanciado).
3. **La red del evento falla**: datos móviles en el teléfono del cliente.
4. **Nada funciona**: pasa al **video de respaldo** sin disculparte — "aquí está el circuito
   completo grabado esta mañana" — y sigue con el explorador, que prueba que las transacciones son reales.

## Preguntas frecuentes del jurado

- **¿Por qué no Binance Pay?** Circuito cerrado (ambos con cuenta), sin modo empleado, sin
  contabilidad, y los fondos custodiados por un exchange extranjero.
- **¿Cuánto cuesta?** Recibir es gratis; el pagador gasta centavos de gas en una L2 (~USD 0,02).
- **¿Y si el cliente no tiene billetera?** Hoy le vendemos al segmento que ya usa USDT (que en
  Bolivia creció más de 500% este año). Incorporar al que no la tiene es exactamente la Fase 2.
- **¿Qué es real y qué es mockup?** Real: contratos, pago, caja, verde, historial — todo on-chain.
  Mockup declarado: Modo Fácil, Comercio y puntaje. Lo decimos de frente; es parte de la honestidad
  del pitch.
- **¿Están en testnet?** Sí, Base Sepolia — el mismo código corre en mainnet cambiando la red.
