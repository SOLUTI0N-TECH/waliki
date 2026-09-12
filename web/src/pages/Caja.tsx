import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { QRCodeSVG } from 'qrcode.react'
import { useBlockNumber, usePublicClient, useReadContract, useWatchContractEvent } from 'wagmi'
import { formatUnits, parseUnits } from 'viem'
import { walikiRouterAbi } from '../contracts/waliki'
import { network } from '../lib/network'
import { fetchQuote, isStale, storedQuote, type RateQuote } from '../lib/rate'

const CHAIN_ID = network.chainId
const ROUTER = network.router
const EXPLORER = network.explorer
const SYMBOL = network.tokenSymbol
const DECIMALS = network.tokenDecimals
const LOG_RANGE = 9900n // public RPCs cap eth_getLogs at 10,000 blocks
const CAJA_PIN = (import.meta.env.VITE_CAJA_PIN as string | undefined) ?? '1234'
const QUOTE_MINUTES = 15
const ZERO_SALE = ('0x' + '0'.repeat(64)) as `0x${string}`
const ZERO_ADDR = ('0x' + '0'.repeat(40)) as `0x${string}`

const nf = new Intl.NumberFormat('es-BO', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

function fmtUsdt(units: bigint): string {
  return nf.format(Number(formatUnits(units, DECIMALS)))
}

function short(v: string): string {
  return `${v.slice(0, 6)}…${v.slice(-4)}`
}

function parseLocalNumber(raw: string): number {
  // Accept both "175,50" and "175.50"
  const n = Number(raw.replace(',', '.'))
  return Number.isFinite(n) && n > 0 ? n : NaN
}

/// A sale id is `cashier (20 bytes) || 12 random bytes`. The router reads the
/// cashier out of it and rejects the payment unless that address is an
/// authorized cashier of the shop, so the payer cannot forge the attribution.
/// Nobody signs from this register, so its sales go under the owner.
function saleIdFor(cashier: `0x${string}`): `0x${string}` {
  const tail = new Uint8Array(12)
  crypto.getRandomValues(tail)
  const hex = Array.from(tail, (b) => b.toString(16).padStart(2, '0')).join('')
  return (cashier.toLowerCase() + hex) as `0x${string}`
}

// Sound must be armed by a user gesture (mobile requirement): COBRAR arms it.
let audioCtx: AudioContext | null = null
function armSound() {
  try {
    audioCtx ??= new AudioContext()
    if (audioCtx.state === 'suspended') void audioCtx.resume()
  } catch {
    audioCtx = null
  }
}
function playGreenSound() {
  if (!audioCtx) return
  try {
    const t0 = audioCtx.currentTime
    const freqs = [880, 1318]
    for (let i = 0; i < freqs.length; i++) {
      const osc = audioCtx.createOscillator()
      const gain = audioCtx.createGain()
      osc.type = 'sine'
      osc.frequency.value = freqs[i]
      const t = t0 + i * 0.18
      gain.gain.setValueAtTime(0.0001, t)
      gain.gain.exponentialRampToValueAtTime(0.35, t + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.4)
      osc.connect(gain).connect(audioCtx.destination)
      osc.start(t)
      osc.stop(t + 0.45)
    }
  } catch {
    // sound is best-effort
  }
}

type Sale = {
  id: `0x${string}`
  amountUnits: bigint
  // Absent when the sale was priced straight in USDT: no Bs figure, no
  // quote behind it, and so nothing that can go stale.
  bs?: number
  rate?: number
  exp?: number
}
type PaidInfo = { payer?: string; txHash?: string; block?: bigint; received?: bigint; late: boolean }
type HistItem = { sale: Sale; status: 'pagada' | 'vencida'; txHash?: string; late: boolean }
type View = { mode: 'entry' } | { mode: 'qr'; sale: Sale } | { mode: 'paid'; sale: Sale; info: PaidInfo }

export default function Caja() {
  // Which shop this register charges for: ?m=<id> from the owner's own link,
  // or typed at the gate. There is no fallback shop — a register can only be
  // opened against one that is actually registered on-chain.
  const [search] = useSearchParams()
  const [shopInput, setShopInput] = useState(() => {
    const fromUrl = search.get('m')
    if (fromUrl) return fromUrl
    try {
      return sessionStorage.getItem('waliki.cajaShop') ?? ''
    } catch {
      return ''
    }
  })
  const merchantId = useMemo(() => {
    const m = shopInput.trim()
    return /^\d+$/.test(m) && BigInt(m) > 0n ? BigInt(m) : null
  }, [shopInput])
  const MERCHANT_ID = merchantId ?? 0n

  const [unlocked, setUnlocked] = useState(() => {
    try {
      return sessionStorage.getItem('waliki.caja') === '1'
    } catch {
      return false
    }
  })
  const [pin, setPin] = useState('')
  const [pinError, setPinError] = useState(false)

  const [rate, setRate] = useState(() => {
    try {
      return localStorage.getItem('waliki.rate') ?? '14.00'
    } catch {
      return '14.00'
    }
  })
  const [amountInput, setAmountInput] = useState('')
  const [usdt, setUsdt] = useState(() => {
    try {
      return localStorage.getItem('waliki.usdtMode') === '1'
    } catch {
      return false
    }
  })
  const [quote, setQuote] = useState<RateQuote | null>(() => storedQuote())

  // The stored quote is already on screen; this only refreshes behind it.
  useEffect(() => {
    if (!isStale(storedQuote())) return
    let alive = true
    void fetchQuote().then((q) => {
      if (alive && q) setQuote(q)
    })
    return () => {
      alive = false
    }
  }, [])

  useEffect(() => {
    if (!quote) return
    const v = quote.buy.toFixed(2)
    setRate(v)
    try {
      localStorage.setItem('waliki.rate', v)
    } catch {
      // persistence is optional
    }
  }, [quote])
  const [view, setView] = useState<View>({ mode: 'entry' })
  const [history, setHistory] = useState<HistItem[]>([])

  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000))
  useEffect(() => {
    const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000)
    return () => clearInterval(t)
  }, [])

  // Connection health: a fresh block number is the caja's heartbeat
  const lastBeat = useRef(Date.now())
  const blockNumber = useBlockNumber({ watch: true, chainId: CHAIN_ID })
  useEffect(() => {
    if (blockNumber.data !== undefined) lastBeat.current = Date.now()
  }, [blockNumber.data])
  const connectionOk = Date.now() - lastBeat.current < 20000

  const merchantRead = useReadContract({
    address: ROUTER,
    abi: walikiRouterAbi,
    functionName: 'merchants',
    args: [MERCHANT_ID],
    chainId: CHAIN_ID,
    query: { enabled: merchantId !== null },
  })
  // An unregistered id reads back with a zero owner: that is the check that
  // keeps a register from opening against a shop that does not exist.
  const merchantExists = Boolean(merchantRead.data && merchantRead.data[0] !== ZERO_ADDR)
  const merchantName =
    merchantExists && merchantRead.data
      ? merchantRead.data[2]
      : `Comercio #${String(MERCHANT_ID)}`

  const activeSale = view.mode === 'qr' ? view.sale : null
  const publicClient = usePublicClient({ chainId: CHAIN_ID })

  function markPaid(sale: Sale, info: Omit<PaidInfo, 'late'>) {
    setView((current) => {
      if (current.mode !== 'qr' || current.sale.id !== sale.id) return current
      const late = sale.exp ? Math.floor(Date.now() / 1000) > sale.exp : false
      playGreenSound()
      setHistory((h) => [{ sale, status: 'pagada' as const, txHash: info.txHash, late }, ...h].slice(0, 8))
      return { mode: 'paid', sale, info: { ...info, late } }
    })
  }

  // Road 1 to green: the PaymentReceived event, filtered by this exact sale
  useWatchContractEvent({
    address: ROUTER,
    abi: walikiRouterAbi,
    eventName: 'PaymentReceived',
    args: { merchantId: MERCHANT_ID, saleId: activeSale?.id ?? ZERO_SALE },
    chainId: CHAIN_ID,
    enabled: Boolean(activeSale),
    onLogs: (logs) => {
      const log = logs[0]
      if (!log || !activeSale) return
      // The amount travels in the QR url, so a customer can lower it before
      // signing. Anything short of the price asked is not a paid sale.
      const amount = log.args.amount
      if (amount == null || amount < activeSale.amountUnits) return
      markPaid(activeSale, {
        payer: log.args.payer,
        txHash: log.transactionHash ?? undefined,
        block: log.blockNumber ?? undefined,
        received: amount,
      })
    },
  })

  // Road 2 to green: poll paidAmount — the caja never hangs on a missed event
  const paidRead = useReadContract({
    address: ROUTER,
    abi: walikiRouterAbi,
    functionName: 'paidAmount',
    args: [MERCHANT_ID, activeSale?.id ?? ZERO_SALE],
    chainId: CHAIN_ID,
    query: { enabled: Boolean(activeSale), refetchInterval: 3000 },
  })
  useEffect(() => {
    if (!activeSale || paidRead.data == null || paidRead.data < activeSale.amountUnits) return
    const sale = activeSale
    const received = paidRead.data
    // Backfill tx details from the event log (best-effort)
    void (async () => {
      let info: Omit<PaidInfo, 'late'> = { received }
      try {
        // A live sale just got paid: the recent window is enough (RPC log cap)
        const latest = (await publicClient?.getBlockNumber()) ?? 0n
        const logs = await publicClient?.getContractEvents({
          address: ROUTER,
          abi: walikiRouterAbi,
          eventName: 'PaymentReceived',
          args: { merchantId: MERCHANT_ID, saleId: sale.id },
          fromBlock: latest > LOG_RANGE ? latest - LOG_RANGE : 0n,
          toBlock: 'latest',
        })
        const log = logs?.[0]
        if (log) {
          info = {
            ...info,
            payer: log.args.payer,
            txHash: log.transactionHash ?? undefined,
            block: log.blockNumber ?? undefined,
          }
        }
      } catch {
        // details are optional; green must not wait for them
      }
      markPaid(sale, info)
    })()
  }, [activeSale, paidRead.data, publicClient])

  function cobrar() {
    const typed = parseLocalNumber(amountInput)
    const r = parseLocalNumber(rate)
    if (!Number.isFinite(typed) || typed <= 0) return
    if (!usdt && (!Number.isFinite(r) || r <= 0)) return
    const amountUnits = parseUnits((usdt ? typed : typed / r).toFixed(DECIMALS), DECIMALS)
    if (amountUnits <= 0n) return
    // Without the owner there is no cashier to stamp into the sale id, and the
    // router would reject the payment after the customer already signed.
    const owner = merchantRead.data?.[0]
    if (!owner || owner === ZERO_ADDR) return
    armSound()
    const id = saleIdFor(owner)
    const sale: Sale = usdt
      ? { id, amountUnits }
      : {
          id,
          amountUnits,
          bs: typed,
          rate: r,
          // Only a Bs sale carries a quote, so only a Bs sale gets a deadline.
          exp: Math.floor(Date.now() / 1000) + QUOTE_MINUTES * 60,
        }
    setView({ mode: 'qr', sale })
  }

  function switchCurrency(next: boolean) {
    // Bs 100 is not $100: clear rather than reinterpret the figure.
    setUsdt(next)
    setAmountInput('')
    try {
      localStorage.setItem('waliki.usdtMode', next ? '1' : '0')
    } catch {
      // persistence is optional
    }
  }


  function cancelSale(expiredSale?: Sale) {
    if (expiredSale) {
      setHistory((h) => [{ sale: expiredSale, status: 'vencida' as const, late: false }, ...h].slice(0, 8))
    }
    setAmountInput('')
    setView({ mode: 'entry' })
  }

  if (!unlocked || merchantId === null) {
    return (
      <div className="card">
        <h1>Abrir caja</h1>
        <p className="muted">
          El cajero solo necesita el número del comercio y su PIN — nunca toca fondos ni llaves.
        </p>
        <label className="muted small" htmlFor="shop">
          Número de comercio
        </label>
        <input
          id="shop"
          className="caja-input"
          inputMode="numeric"
          autoFocus
          value={shopInput}
          onChange={(e) => setShopInput(e.target.value)}
        />
        {merchantId !== null && merchantRead.isLoading && (
          <div className="muted center small">Buscando el comercio…</div>
        )}
        {merchantId !== null && !merchantRead.isLoading && !merchantExists && (
          <div className="error-box">Ese comercio no está registrado.</div>
        )}
        {merchantExists && <div className="muted center">{merchantName}</div>}
        <input
          className="caja-input"
          type="password"
          inputMode="numeric"
          placeholder="PIN de cajero"
          value={pin}
          maxLength={8}
          onChange={(e) => {
            setPin(e.target.value)
            setPinError(false)
          }}
        />
        {pinError && <div className="error-box">PIN incorrecto</div>}
        <button
          className="btn"
          disabled={!merchantExists}
          onClick={() => {
            if (pin === CAJA_PIN) {
              try {
                sessionStorage.setItem('waliki.caja', '1')
                sessionStorage.setItem('waliki.cajaShop', String(merchantId))
              } catch {
                // session persistence is optional
              }
              setUnlocked(true)
            } else {
              setPinError(true)
            }
          }}
        >
          Entrar
        </button>
      </div>
    )
  }

  if (view.mode === 'paid') {
    const { sale, info } = view
    const received = info.received ?? sale.amountUnits
    return (
      <div className="success-panel">
        <div className="success-check">✓</div>
        <h1>¡Pago recibido!</h1>
        <div className="success-amount">
          {sale.bs != null
            ? `Bs ${nf.format(sale.bs)}`
            : `${fmtUsdt(received)} ${SYMBOL}`}
        </div>
        <div className="success-sub">
          {fmtUsdt(received)} {SYMBOL} · venta {short(sale.id)}
        </div>
        {info.late && <span className="chip chip-amber">pago fuera de plazo (cotización vencida)</span>}
        <div className="receipt">
          <div className="row">
            <span>Pagó</span>
            <span className="addr">{info.payer ? short(info.payer) : 'verificado on-chain'}</span>
          </div>
          <div className="row">
            <span>Transacción</span>
            {info.txHash ? (
              <a href={`${EXPLORER}/tx/${info.txHash}`} target="_blank" rel="noreferrer">
                {short(info.txHash)} ↗
              </a>
            ) : (
              <span>confirmada</span>
            )}
          </div>
          <div className="row">
            <span>Bloque</span>
            <span>{info.block !== undefined ? String(info.block) : '—'}</span>
          </div>
        </div>
        <button className="btn btn-white" onClick={() => cancelSale()}>
          Nueva venta
        </button>
      </div>
    )
  }

  if (view.mode === 'qr') {
    const { sale } = view
    const expired = sale.exp != null && now >= sale.exp
    const remaining = sale.exp != null ? Math.max(0, sale.exp - now) : null
    // The link carries only what the sale actually has: a USDT price
    // travels without a rate and without a deadline.
    const params = new URLSearchParams({
      m: String(MERCHANT_ID),
      a: String(sale.amountUnits),
    })
    if (sale.bs != null && sale.rate != null) {
      params.set('bs', String(sale.bs))
      params.set('r', sale.rate.toFixed(2))
    }
    if (sale.exp != null) params.set('exp', String(sale.exp))
    const url = `${window.location.origin}/pay/${sale.id}?${params.toString()}`
    const isLocalhost = /localhost|127\.0\.0\.1/.test(window.location.origin)
    return (
      <div className="card center-col">
        <div className="merchant-row">
          <div>
            <div className="muted small">Cobrando</div>
            <div className="merchant-name">
              {sale.bs != null ? `Bs ${nf.format(sale.bs)} · ` : null}
              {fmtUsdt(sale.amountUnits)} {SYMBOL}
            </div>
          </div>
          <span className={connectionOk ? 'chip chip-green' : 'chip chip-amber'}>
            {connectionOk ? '● conexión estable' : '● reconectando…'}
          </span>
        </div>

        <div className="qr-wrap">
          <QRCodeSVG value={url} size={250} marginSize={2} />
        </div>
        <div className="muted small center">
          El cliente escanea con su cámara — se abre la página de pago en su navegador
        </div>
        {isLocalhost && (
          <div className="error-box">
            Estás en localhost: el teléfono no podrá abrir este QR. Abre la caja con la URL de red
            (npm run dev -- --host).
          </div>
        )}

        <div className="wallet-row">
          <span className="pulse-dot"></span>
          <span style={{ flexGrow: 1 }}>Esperando el pago…</span>
          {expired ? (
            <span className="chip chip-red">cotización vencida</span>
          ) : remaining !== null ? (
            <span className="chip chip-amber">
              vence en {Math.floor(remaining / 60)}:{String(remaining % 60).padStart(2, '0')}
            </span>
          ) : null}
        </div>
        <div className="muted small center">
          El verde lo dispara el evento en la blockchain — no una captura del cliente.
        </div>

        {expired && (
          <button className="btn" onClick={() => cancelSale(sale)}>
            Generar un QR nuevo
          </button>
        )}
        <button className="btn btn-quiet" onClick={() => cancelSale(expired ? undefined : sale)}>
          Cancelar venta
        </button>
      </div>
    )
  }

  const typedValue = parseLocalNumber(amountInput)
  const rateValue = parseLocalNumber(rate)
  const previewOk =
    Number.isFinite(typedValue) &&
    typedValue > 0 &&
    (usdt || (Number.isFinite(rateValue) && rateValue > 0))
  const preview = previewOk
    ? parseUnits((usdt ? typedValue : typedValue / rateValue).toFixed(DECIMALS), DECIMALS)
    : null

  return (
    <div className="card">
      <div className="merchant-row">
        <div>
          <div className="muted small">Caja 1</div>
          <div className="merchant-name">{merchantName}</div>
        </div>
        <span className={connectionOk ? 'chip chip-green' : 'chip chip-amber'}>
          {connectionOk ? '● conexión estable' : '● reconectando…'}
        </span>
      </div>

      <div className="seg" role="group" aria-label="Moneda del cobro">
        <button type="button" aria-pressed={!usdt} onClick={() => switchCurrency(false)}>
          Bs · Bolivianos
        </button>
        <button type="button" aria-pressed={usdt} onClick={() => switchCurrency(true)}>
          $ · {SYMBOL}
        </button>
      </div>

      {!usdt && (
        <>
          {/* Read-only: the rate comes from the market on its own. */}
          <div className="wallet-row">
            <span className="muted small">Tasa (Bs por {SYMBOL})</span>
            <span className="num">{rate}</span>
          </div>
        </>
      )}

      <label className="muted small" htmlFor="bs">
        {usdt ? `Monto en ${SYMBOL}` : 'Monto en bolivianos'}
      </label>
      <input
        id="bs"
        className="caja-input"
        inputMode="decimal"
        placeholder="0,00"
        autoFocus
        value={amountInput}
        onChange={(e) => setAmountInput(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') cobrar()
        }}
      />
      {preview !== null && (
        <div className="muted center">
          {usdt
            ? `Se cobra ${fmtUsdt(preview)} ${SYMBOL}`
            : `≈ ${fmtUsdt(preview)} ${SYMBOL} · cotización congelada por ${QUOTE_MINUTES} min`}
        </div>
      )}

      <button className="btn" disabled={preview === null} onClick={cobrar}>
        Cobrar — generar QR
      </button>

      {history.length > 0 && (
        <div className="hist">
          <div className="muted small">Esta sesión</div>
          {history.map((h) => (
            <div className="hist-row" key={h.sale.id}>
              <span className="addr">{short(h.sale.id)}</span>
              <span>
                {h.sale.bs != null
                  ? `Bs ${nf.format(h.sale.bs)}`
                  : `${fmtUsdt(h.sale.amountUnits)} ${SYMBOL}`}
              </span>
              {h.status === 'pagada' ? (
                <span className="chip chip-green">{h.late ? 'pagada (fuera de plazo)' : 'pagada'}</span>
              ) : (
                <span className="chip">vencida</span>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
