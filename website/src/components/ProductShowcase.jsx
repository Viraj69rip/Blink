import { useState } from 'react'
import { motion } from 'framer-motion'
import PaymentModal from './PaymentModal'

const tiers = [
  {
    key: 'basic',
    name: 'BLINK Basic',
    tagline: 'Your desk companion, ready to go.',
    price: '₹3,999',
    badge: 'Most Popular',
    highlight: true,
    features: [
      'ESP32-C3 SuperMini',
      '0.96" SSD1306 OLED',
      'MPU6050 Motion Sensor',
      'Touch Sensor + Buzzer',
      'USB-C Power (adapter included)',
      'Flutter Companion App',
      '21 Idle Animations',
    ],
  },
  {
    key: 'wireless',
    name: 'BLINK Wireless',
    tagline: 'Untethered freedom with built-in battery.',
    price: '₹4,999',
    badge: 'Best Value',
    highlight: false,
    features: [
      'Everything in Basic',
      'Built-in Li-Po Battery',
      'Up to 6hrs Runtime',
      'USB-C Charging',
      'Portable — no wires needed',
      'Night Mode Automation',
    ],
  },
  {
    key: 'ai',
    name: 'BLINK AI',
    tagline: 'Voice-powered AI assistant on your desk.',
    price: '₹7,999',
    badge: 'Premium',
    highlight: false,
    features: [
      'Everything in Wireless',
      'Integrated AI Voice Assistant',
      'Alexa-like Smart Features',
      'Voice Commands & Responses',
      'Wi-Fi + BLE 5 Connectivity',
      'Cloud AI Processing',
      'Smart Home Integration Ready',
    ],
  },
]

const containerVariants = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.12 } },
}

const itemVariants = {
  hidden: { opacity: 0, y: 40 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.6, ease: [0.22, 1, 0.36, 1] } },
}

export default function ProductShowcase() {
  const [modalOpen, setModalOpen] = useState(false)
  const [selectedVariant, setSelectedVariant] = useState('basic')

  const openOrder = (key) => {
    setSelectedVariant(key)
    setModalOpen(true)
  }

  return (
    <section id="pricing" className="section" style={{ position: 'relative' }}>
      <div className="container">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-80px' }}
          transition={{ duration: 0.5 }}
          style={{ textAlign: 'center', marginBottom: 60 }}
        >
          <div className="section-label" style={{ margin: '0 auto 20px' }}>
            <svg width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 3h1.386c.51 0 .955.343 1.087.835l.383 1.437M7.5 14.25a3 3 0 00-3 3h15.75m-12.75-3h11.218c1.121-2.3 2.1-4.684 2.924-7.138a60.114 60.114 0 00-16.536-1.84M7.5 14.25L5.106 5.272M6 20.25a.75.75 0 11-1.5 0 .75.75 0 011.5 0zm12.75 0a.75.75 0 11-1.5 0 .75.75 0 011.5 0z" />
            </svg>
            Pricing
          </div>
          <h2 className="section-title">Choose your BLINK</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            Three variants to fit your needs — from the essential companion to the AI-powered smart assistant.
          </p>
        </motion.div>

        <motion.div
          variants={containerVariants}
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, margin: '-80px' }}
          style={{
            display: 'grid',
            gap: 24,
            gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
            maxWidth: 1000,
            margin: '0 auto',
          }}
        >
          {tiers.map((tier) => (
            <motion.div
              key={tier.name}
              variants={itemVariants}
              whileHover={{ y: -8 }}
              style={{
                background: tier.highlight
                  ? 'linear-gradient(145deg, rgba(99, 102, 241, 0.12), rgba(99, 102, 241, 0.04))'
                  : 'var(--color-surface)',
                border: tier.highlight
                  ? '1px solid rgba(99, 102, 241, 0.35)'
                  : '1px solid var(--color-border)',
                borderRadius: 'var(--radius-lg)',
                padding: tier.highlight ? '48px clamp(20px, 5vw, 36px)' : '40px clamp(20px, 5vw, 36px)',
                position: 'relative',
                overflow: 'hidden',
                transition: 'border-color 0.3s',
                display: 'flex',
                flexDirection: 'column',
              }}
              onMouseEnter={(e) => (e.currentTarget.style.borderColor = tier.highlight ? 'rgba(99, 102, 241, 0.6)' : 'rgba(99, 102, 241, 0.3)')}
              onMouseLeave={(e) => (e.currentTarget.style.borderColor = tier.highlight ? 'rgba(99, 102, 241, 0.35)' : 'var(--color-border)')}
            >
              {tier.badge && (
                <div
                  style={{
                    position: 'absolute',
                    top: 20,
                    right: 20,
                    padding: '4px 14px',
                    background: tier.highlight
                      ? 'linear-gradient(135deg, #6366f1, #a855f7)'
                      : 'rgba(255, 255, 255, 0.06)',
                    border: tier.highlight ? 'none' : '1px solid rgba(255, 255, 255, 0.12)',
                    borderRadius: 'var(--radius-full)',
                    fontSize: 11,
                    fontWeight: 700,
                    color: tier.highlight ? '#fff' : 'var(--color-text-secondary)',
                    textTransform: 'uppercase',
                    letterSpacing: '0.06em',
                  }}
                >
                  {tier.badge}
                </div>
              )}

              <h3
                style={{
                  fontFamily: 'var(--font-display)',
                  fontSize: 22,
                  marginBottom: 8,
                  marginTop: 8,
                }}
              >
                {tier.name}
              </h3>

              <p style={{ fontSize: 14, color: 'var(--color-text-secondary)', marginBottom: 24, lineHeight: 1.6, minHeight: 44 }}>
                {tier.tagline}
              </p>

              <div style={{ marginBottom: 28 }}>
                <span style={{ fontSize: 'clamp(28px, 6vw, 36px)', fontWeight: 800, color: tier.highlight ? '#818cf8' : 'white' }}>
                  {tier.price}
                </span>
              </div>

              <ul style={{ listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 10, flex: 1 }}>
                {tier.features.map((f) => (
                  <li key={f} style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 14, color: 'var(--color-text-secondary)' }}>
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#6366f1" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                    {f}
                  </li>
                ))}
              </ul>

              <button
                type="button"
                onClick={() => openOrder(tier.key)}
                aria-label={`Order ${tier.name} for ${tier.price}`}
                className={tier.highlight ? 'btn-primary' : 'btn-secondary'}
                style={{ width: '100%', justifyContent: 'center', marginTop: 32, textAlign: 'center', border: tier.highlight ? 'none' : '1px solid rgba(255,255,255,0.18)' }}
              >
                Order Now
                <svg width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
                </svg>
              </button>
            </motion.div>
          ))}
        </motion.div>
      </div>
      {/* `variant` is what makes the tier the visitor clicked the tier that
          opens — without it the modal always started on Basic and
          `selectedVariant` was dead state. */}
      <PaymentModal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        variant={selectedVariant}
      />
    </section>
  )
}
