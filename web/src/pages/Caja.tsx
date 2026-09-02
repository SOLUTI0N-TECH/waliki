import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { QRCodeSVG } from 'qrcode.react'
import { useBlockNumber, usePublicClient, useReadContract, useWatchContractEvent } from 'wagmi'
import { formatUnits, parseUnits } from 'viem'
import { deployment, walikiRouterAbi } from '../contracts/waliki'

const CHAIN_ID = 84532
const ROUTER = deployment.walikiRouter as `0x${string}`
const EXPLORER = 'https://sepolia.basescan.org'
const LOG_RANGE = 9900n // public RPCs cap eth_getLogs at 10,000 blocks
const DEFAULT_MERCHANT_ID = (import.meta.env.VITE_MERCHANT_ID as string | undefined) ?? '1'
const CAJA_PIN = (import.meta.env.VITE_CAJA_PIN as string | undefined) ?? '1234'
const QUOTE_MINUTES = 15
const ZERO_SALE = ('0x' + '0'.repeat(64)) as `0x${string}`

const nf = new Intl.NumberFormat('es-BO', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

function fmtUsdt(units: bigint): string {
  return nf.format(Number(formatUnits(units, 6)))
}

function short(v: string): string {
  return `${v.slice(0, 6)}…${v.slice(-4)}`
}

function parseLocalNumber(raw: string): number {
  // Accept both "175,50" and "175.50"
  const n = Number(raw.replace(',', '.'))
  return Number.isFinite(n) && n > 0 ? n : NaN
}

function randomSaleId(): `0x${string}` {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  return ('0x' + Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')) as `0x${string}`
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

type Sale = { id: `0x${string}`; amountUnits: bigint; bs: number; rate: number; exp: number }
type PaidInfo = { payer?: string; txHash?: string; block?: bigint; late: boolean }
type HistItem = { sale: Sale; status: 'pagada' | 'vencida'; txHash?: string; late: boolean }
type View = { mode: 'entry' } | { mode: 'qr'; sale: Sale } | { mode: 'paid'; sale: Sale; info: PaidInfo }

export default function Caja() {
  // Which shop this register charges for: ?m=<id> (from /registro), else the
  // build default. Any merchant registered on-chain can open its own caja.
  const [search] = useSearchParams()
  const MERCHANT_ID = useMemo(() => {
    const m = search.get('m')
    return m && /^\d+$/.test(m) && BigInt(m) > 0n ? BigInt(m) : BigInt(DEFAULT_MERCHANT_ID)
  }, [search])

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
  const [bsInput, setBsInput] = useState('')
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
  })
  const merchantName = merchantRead.data ? merchantRead.data[2] : `Comercio #${String(MERCHANT_ID)}`

  const activeSale = view.mode === 'qr' ? view.sale : null
  const publicClient = usePublicClient({ chainId: CHAIN_ID })

  function markPaid(sale: Sale, info: Omit<PaidInfo, 'late'>) {
    setView((current) => {
      if (current.mode !== 'qr' || current.sale.id !== sale.id) return current
      const late = Math.floor(Date.now() / 1000) > sale.exp
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
      markPaid(activeSale, {
        payer: log.args.payer,
        txHash: log.transactionHash ?? undefined,
        block: log.blockNumber ?? undefined,
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
    if (!activeSale || !paidRead.data || paidRead.data === 0n) return
    const sale = activeSale
    // Backfill tx details from the event log (best-effort)
    void (async () => {
      let info: Omit<PaidInfo, 'late'> = {}
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
    const bs = parseLocalNumber(bsInput)
    const r = parseLocalNumber(rate)
    if (!Number.isFinite(bs) || !Number.isFinite(r)) return
    armSound()
    const sale: Sale = {
      id: randomSaleId(),
      amountUnits: parseUnits((bs / r).toFixed(6), 6),
      bs,
      rate: r,
      exp: Math.floor(Date.now() / 1000) + QUOTE_MINUTES * 60,
    }
    setView({ mode: 'qr', sale })
  }

  function cancelSale(expiredSale?: Sale) {
    if (expiredSale) {
      setHistory((h) => [{ sale: expiredSale, status: 'vencida' as const, late: false }, ...h].slice(0, 8))
    }
    setBsInput('')
    setView({ mode: 'entry' })
  }

  if (!unlocked) {
    return (
      <div className="card">
        <h1>Caja</h1>
        <p className="muted">
          {merchantName} · el cajero solo necesita su PIN — nunca toca fondos ni llaves.
        </p>
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
          onClick={() => {
            if (pin === CAJA_PIN) {
              try {
                sessionStorage.setItem('waliki.caja', '1')
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
    return (
      <div className="success-panel">
        <div className="success-check">✓</div>
        <h1>¡Pago recibido!</h1>
        <div className="success-amount">Bs {nf.format(sale.bs)}</div>
        <div className="success-sub">
          {fmtUsdt(sale.amountUnits)} tUSDT · venta {short(sale.id)}
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
    const expired = now >= sale.exp
    const remaining = Math.max(0, sale.exp - now)
    const url = `${window.location.origin}/pay/${sale.id}?m=${String(MERCHANT_ID)}&a=${String(sale.amountUnits)}&bs=${sale.bs}&r=${sale.rate.toFixed(2)}&exp=${sale.exp}`
    const isLocalhost = /localhost|127\.0\.0\.1/.test(window.location.origin)
    return (
      <div className="card center-col">
        <div className="merchant-row">
          <div>
            <div className="muted small">Cobrando</div>
            <div className="merchant-name">Bs {nf.format(sale.bs)} · {fmtUsdt(sale.amountUnits)} tUSDT</div>
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
          {!expired ? (
            <span className="chip chip-amber">
              vence en {Math.floor(remaining / 60)}:{String(remaining % 60).padStart(2, '0')}
            </span>
          ) : (
            <span className="chip chip-red">cotización vencida</span>
          )}
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

  const bsValue = parseLocalNumber(bsInput)
  const rateValue = parseLocalNumber(rate)
  const preview =
    Number.isFinite(bsValue) && Number.isFinite(rateValue)
      ? parseUnits((bsValue / rateValue).toFixed(6), 6)
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

      <div className="wallet-row">
        <span className="muted small">Tasa del comercio (Bs por USDT)</span>
        <input
          className="rate-input"
          inputMode="decimal"
          value={rate}
          onChange={(e) => {
            setRate(e.target.value)
            try {
              localStorage.setItem('waliki.rate', e.target.value)
            } catch {
              // persistence is optional
            }
          }}
        />
      </div>

      <label className="muted small" htmlFor="bs">
        Monto en bolivianos
      </label>
      <input
        id="bs"
        className="caja-input"
        inputMode="decimal"
        placeholder="0,00"
        autoFocus
        value={bsInput}
        onChange={(e) => setBsInput(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') cobrar()
        }}
      />
      {preview !== null && (
        <div className="muted center">≈ {fmtUsdt(preview)} tUSDT · cotización congelada por {QUOTE_MINUTES} min</div>
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
              <span>Bs {nf.format(h.sale.bs)}</span>
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
