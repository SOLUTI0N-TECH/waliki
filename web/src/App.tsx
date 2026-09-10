import { Link, Route, Routes } from 'react-router-dom'
import Caja from './pages/Caja'
import Home from './pages/Home'
import Pay from './pages/Pay'
import Registro from './pages/Registro'

export default function App() {
  return (
    <div className="app-shell">
      <header className="topbar">
        <Link className="brand" to="/">
          <img className="brand-mark" src="/waliki-mark.png" alt="" />
          Waliki
        </Link>
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
