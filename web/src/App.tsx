import { Link, Route, Routes } from 'react-router-dom'
import Caja from './pages/Caja'
import Home from './pages/Home'
import Pay from './pages/Pay'
import Registro from './pages/Registro'
import { network } from './lib/network'

export default function App() {
  return (
    <div className="app-shell">
      <header className="topbar">
        <Link className="brand" to="/">
          <span className="brand-mark" />
          waliki
        </Link>
        {network.isTestnet && (
        <span
          className="env-chip"
          title="Fase de prueba: red Base Sepolia. Las transacciones son reales y verificables, pero los fondos no tienen valor."
        >
          <span className="env-dot" />
          Fase de prueba
        </span>
        )}
      </header>
      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/caja" element={<Caja />} />
          <Route path="/pay/:saleId" element={<Pay />} />
          <Route path="/registro" element={<Registro />} />
        </Routes>
      </main>
    </div>
  )
}
