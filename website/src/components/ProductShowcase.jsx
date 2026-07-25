import { motion } from 'framer-motion'

const products = [
  {
    name: 'BLINK Robot Kit',
    tagline: 'Everything you need to build your own desk companion.',
    price: 'Free / Open Source',
    badge: 'Hardware',
    features: ['ESP32-C3 SuperMini', '0.96" SSD1306 OLED', 'MPU6050 Motion Sensor', 'Touch Sensor + Buzzer', 'USB-C Power'],
  },
  {
    name: 'BLINK Companion App',
    tagline: 'Control, draw, and update your robot wirelessly.',
    price: 'Free',
    badge: 'Android',
    features: ['BLE Connection', 'Drawing Canvas', 'OTA Firmware Updates', 'Focus Timer', 'Expression Vault'],
  },
  {
    name: 'BLINK Firmware',
    tagline: 'Open-source firmware with 21+ idle animations.',
    price: 'Free',
    badge: 'Arduino',
    features: ['21 Idle Animations', 'Mario Clock', 'Touch Menu', 'Shake Detection', 'Night Mode'],
  },
]

const containerVariants = {
  hidden: {},
  visible: {
    transition: { staggerChildren: 0.1 },
  },
}

const itemVariants = {
  hidden: { opacity: 0, y: 30 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.22, 1, 0.36, 1] },
  },
}

export default function ProductShowcase() {
  return (
    <section id="features" className="section" style={{ position: 'relative' }}>
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
              <path strokeLinecap="round" strokeLinejoin="round" d="M9.53 16.122a3 3 0 00-5.78 1.128 2.25 2.25 0 01-2.4 2.245 4.5 4.5 0 008.4-2.245c0-.399-.078-.78-.22-1.128zm0 0a15.998 15.998 0 003.388-1.62m-5.043-.025a15.994 15.994 0 011.622-3.395m3.42 3.42a15.995 15.995 0 004.764-4.648l3.876-5.814a1.151 1.151 0 00-1.597-1.597L14.146 6.32a15.996 15.996 0 00-4.649 4.763m3.42 3.42a6.776 6.776 0 00-3.42-3.42" />
            </svg>
            Open Source Stack
          </div>
          <h2 className="section-title">Everything you need</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            Hardware schematics, firmware, and mobile app — all fully open source and ready for you to build.
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
            gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
          }}
        >
          {products.map((product, i) => (
            <motion.div
              key={product.name}
              variants={itemVariants}
              whileHover={{ y: -6 }}
              style={{
                background: 'var(--color-surface)',
                border: '1px solid var(--color-border)',
                borderRadius: 'var(--radius-lg)',
                padding: 40,
                position: 'relative',
                overflow: 'hidden',
                transition: 'border-color 0.3s',
              }}
              onMouseEnter={(e) => (e.currentTarget.style.borderColor = 'rgba(99, 102, 241, 0.3)')}
              onMouseLeave={(e) => (e.currentTarget.style.borderColor = 'var(--color-border)')}
            >
              <div
                style={{
                  position: 'absolute',
                  top: 20,
                  right: 20,
                  padding: '4px 12px',
                  background: 'rgba(99, 102, 241, 0.15)',
                  border: '1px solid rgba(99, 102, 241, 0.25)',
                  borderRadius: 'var(--radius-full)',
                  fontSize: 11,
                  fontWeight: 700,
                  color: 'var(--color-accent-light)',
                  textTransform: 'uppercase',
                  letterSpacing: '0.06em',
                }}
              >
                {product.badge}
              </div>

              <h3
                style={{
                  fontFamily: 'var(--font-display)',
                  fontSize: 22,
                  marginBottom: 8,
                  marginTop: 8,
                }}
              >
                {product.name}
              </h3>
              <p style={{ fontSize: 14, color: 'var(--color-text-secondary)', marginBottom: 20, lineHeight: 1.6 }}>
                {product.tagline}
              </p>

              <div style={{ fontSize: 20, fontWeight: 700, color: 'var(--color-accent-light)', marginBottom: 24 }}>
                {product.price}
              </div>

              <ul style={{ listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 10 }}>
                {product.features.map((f) => (
                  <li key={f} style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 14, color: 'var(--color-text-secondary)' }}>
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#6366f1" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                    {f}
                  </li>
                ))}
              </ul>

              <a
                href="https://github.com/Viraj69rip/Blink"
                target="_blank"
                rel="noopener noreferrer"
                className="btn-secondary"
                style={{ width: '100%', justifyContent: 'center', marginTop: 28 }}
              >
                Get Started
                <svg width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 19.5l15-15m0 0H8.25m11.25 0v11.25" />
                </svg>
              </a>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  )
}
