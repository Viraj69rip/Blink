import { motion } from 'framer-motion'

const floatingOrbs = [
  { size: '500px', top: '-10%', left: '-15%', color: 'rgba(99, 102, 241, 0.12)', duration: 20, x: 80, y: 100 },
  { size: '400px', top: '10%', right: '-10%', color: 'rgba(168, 85, 247, 0.1)', duration: 25, x: -60, y: 120 },
  { size: '350px', bottom: '-5%', left: '30%', color: 'rgba(6, 182, 212, 0.08)', duration: 22, x: 60, y: -80 },
]

export default function Hero() {
  return (
    <section style={{ position: 'relative', minHeight: '100vh', display: 'flex', alignItems: 'center', overflow: 'hidden', paddingTop: 'clamp(60px, 10vw, 80px)' }}>
      {floatingOrbs.map((orb, i) => (
        <motion.div
          key={i}
          style={{
            position: 'absolute',
            width: orb.size,
            height: orb.size,
            borderRadius: '50%',
            background: `radial-gradient(circle, ${orb.color}, transparent 70%)`,
            pointerEvents: 'none',
            ...(orb.top ? { top: orb.top } : {}),
            ...(orb.bottom ? { bottom: orb.bottom } : {}),
            ...(orb.left ? { left: orb.left } : {}),
            ...(orb.right ? { right: orb.right } : {}),
          }}
          animate={{ x: [0, orb.x, 0], y: [0, orb.y, 0] }}
          transition={{ duration: orb.duration, repeat: Infinity, ease: 'easeInOut' }}
        />
      ))}

      <div className="container" style={{ position: 'relative', zIndex: 2 }}>
        <div style={{ maxWidth: 720 }}>
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.1 }}
            style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginBottom: 24 }}
          >
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 6,
              padding: '6px 14px',
              background: 'rgba(255, 255, 255, 0.06)',
              border: '1px solid rgba(255, 255, 255, 0.12)',
              borderRadius: 'var(--radius-full)',
              fontSize: 12, fontWeight: 600,
              color: 'var(--color-text-secondary)',
              textTransform: 'uppercase', letterSpacing: '0.08em',
            }}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#f97316" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09z" />
              </svg>
              Proudly Made in India
            </span>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 6,
              padding: '6px 14px',
              background: 'rgba(99, 102, 241, 0.1)',
              border: '1px solid rgba(99, 102, 241, 0.2)',
              borderRadius: 'var(--radius-full)',
              fontSize: 12, fontWeight: 600,
              color: 'var(--color-accent-light)',
              textTransform: 'uppercase', letterSpacing: '0.08em',
            }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#6366f1' }} />
              Now on Sale
            </span>
          </motion.div>

          <motion.h1
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.2 }}
            style={{
              fontFamily: 'var(--font-display)',
              fontSize: 'clamp(2.5rem, 6vw, 4.5rem)',
              lineHeight: 1.1,
              marginBottom: 20,
            }}
          >
            Meet{' '}
            <span className="gradient-text">BLINK</span>
            <br />
            your interactive
            <br />
            desk robot.
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.3 }}
            style={{
              fontSize: 17,
              color: 'var(--color-text-secondary)',
              maxWidth: 480,
              lineHeight: 1.7,
              marginBottom: 32,
            }}
          >
            A tiny, expressive companion powered by ESP32-C3, a crisp 0.96 OLED display, and motion sensing — all controlled from a beautiful Flutter companion app.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.4 }}
            style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}
          >
            <a href="#pricing" className="btn-primary">
              Buy Now — From ₹3,999
              <svg width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2.5" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 3h1.386c.51 0 .955.343 1.087.835l.383 1.437M7.5 14.25a3 3 0 00-3 3h15.75m-12.75-3h11.218c1.121-2.3 2.1-4.684 2.924-7.138a60.114 60.114 0 00-16.536-1.84M7.5 14.25L5.106 5.272M6 20.25a.75.75 0 11-1.5 0 .75.75 0 011.5 0zm12.75 0a.75.75 0 11-1.5 0 .75.75 0 011.5 0z" />
              </svg>
            </a>
            <a href="#demo" className="btn-secondary">
              Try the Demo
            </a>
          </motion.div>

          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.6, delay: 0.5 }}
            style={{ display: 'flex', flexWrap: 'wrap', gap: 'clamp(12px, 3vw, 20px)', marginTop: 32, fontSize: 13, color: 'var(--color-text-tertiary)' }}
          >
            <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#34d399' }} />
              ESP32-C3
            </span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#22d3ee' }} />
              0.96" OLED
            </span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#a78bfa' }} />
              Flutter App
            </span>
          </motion.div>
        </div>
      </div>
    </section>
  )
}
