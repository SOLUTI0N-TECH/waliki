// Parallel-market dollar quote, read from paralelo.bo.
//
// Source: paralelo.bo, published under CC-BY-4.0. The licence asks for credit,
// so RATE_SOURCE is named wherever the rate is shown.
//
// Deliberately not fetched per sale. The endpoint publishes
// `Cache-Control: max-age=60`, so asking more often than once a minute cannot
// return anything newer — it would only add latency with a customer waiting,
// and turn a network hiccup into a failed sale. Equally not fetched once a
// day: the parallel rate moves intraday. So: serve the stored quote at once,
// refresh behind it, never block.

export const RATE_SOURCE = 'paralelo.bo'

const ENDPOINT = 'https://paralelo.bo/api/v1/rate'
const KEY = 'waliki.rateQuote'

/** Five minutes sits well inside the 15-minute window the QR quote accepts. */
export const FRESH_FOR_MS = 5 * 60 * 1000

export type RateQuote = {
  /** Bs to acquire one dollar — the side the register quotes. */
  buy: number
  /** Bs received selling one dollar; lower. The gap is the round-trip cost. */
  sell: number
  median: number
  /** When the source computed it. */
  at: string
  /** When this browser got it; staleness is measured from here. */
  fetched: number
}

function read(value: unknown, fetched: number): RateQuote | null {
  if (typeof value !== 'object' || value === null) return null
  const o = value as Record<string, unknown>
  const num = (v: unknown) => (typeof v === 'number' ? v : Number(v))
  const buy = num(o.buy)
  if (!Number.isFinite(buy) || buy <= 0) return null
  const sell = num(o.sell)
  const median = num(o.median)
  return {
    buy,
    sell: Number.isFinite(sell) ? sell : buy,
    median: Number.isFinite(median) ? median : buy,
    at: typeof o.timestamp === 'string' ? o.timestamp : new Date(fetched).toISOString(),
    fetched: typeof o.fetched === 'number' ? o.fetched : fetched,
  }
}

/** The quote stored in this browser. Instant, no network. */
export function storedQuote(): RateQuote | null {
  try {
    const raw = localStorage.getItem(KEY)
    return raw ? read(JSON.parse(raw), Date.now()) : null
  } catch {
    // a corrupt entry is not worth breaking the register over
    return null
  }
}

export function isStale(q: RateQuote | null): boolean {
  return !q || Date.now() - q.fetched > FRESH_FOR_MS
}

export function ageLabel(q: RateQuote): string {
  const min = Math.floor((Date.now() - q.fetched) / 60000)
  if (min < 1) return 'recién'
  if (min < 60) return `hace ${min} min`
  const h = Math.floor(min / 60)
  return h < 24 ? `hace ${h} h` : `hace ${Math.floor(h / 24)} d`
}

/** Returns null on any failure, leaving the stored quote in place. */
export async function fetchQuote(): Promise<RateQuote | null> {
  try {
    // Short on purpose: a slow network must not hold up a sale.
    const res = await fetch(ENDPOINT, {
      headers: { accept: 'application/json' },
      signal: AbortSignal.timeout(5000),
    })
    if (!res.ok) return null
    const quote = read(await res.json(), Date.now())
    if (!quote) return null
    quote.fetched = Date.now()
    try {
      localStorage.setItem(KEY, JSON.stringify(quote))
    } catch {
      // persistence is optional
    }
    return quote
  } catch {
    // offline, timeout, rate-limited: the stored quote keeps working
    return null
  }
}
