import Navbar from './components/Navbar'
import Hero from './components/Hero'
import ProductShowcase from './components/ProductShowcase'
import Demo from './components/Demo'
import Specs from './components/Specs'
import Downloads from './components/Downloads'
import Footer from './components/Footer'

export default function App() {
  return (
    <div style={{ minHeight: '100vh', overflow: 'hidden' }}>
      <Navbar />
      <main>
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
