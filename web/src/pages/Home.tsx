import { Link } from 'react-router-dom'

export default function Home() {
  return (
    <>
      <h1>Cobra en USDT, sin custodios</h1>
      <p className="muted">
        El pago viaja directo de la billetera del cliente a la del comercio. Waliki solo lee la
        blockchain para confirmarlo — nunca toca el dinero.
      </p>

      <nav className="home-nav">
        <Link to="/caja">
          Abrir la caja <span className="chip">cajero · PIN</span>
        </Link>
        <Link to="/registro">
          Registrar mi comercio <span className="chip">dueño · 1 firma</span>
        </Link>
      </nav>
    </>
  )
}
