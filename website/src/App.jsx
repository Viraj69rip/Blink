import Navbar from './components/Navbar'
import Hero from './components/Hero'
import ProductShowcase from './components/ProductShowcase'
import Demo from './components/Demo'
import Specs from './components/Specs'
import Downloads from './components/Downloads'
import Footer from './components/Footer'

export default function App() {
  return (
    <div style={{ minHeight: '100vh', overflowX: 'clip' }}>
      <a href="#main" className="skip-link">Skip to content</a>
      <Navbar />
      {/* tabIndex -1 so the skip link actually moves focus here, not just the
          scroll position — without it the next Tab returns to the navbar. */}
      <main id="main" tabIndex={-1}>
        <Hero />
        <ProductShowcase />
        <Demo />
        <Specs />
        <Downloads />
      </main>
      <Footer />
    </div>
  )
}
