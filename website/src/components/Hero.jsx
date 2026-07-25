import { motion } from 'framer-motion'

const floatingOrbs = [
  { size: '500px', top: '-10%', left: '-15%', color: 'rgba(99, 102, 241, 0.12)', duration: 20, x: 80, y: 100 },
  { size: '400px', top: '10%', right: '-10%', color: 'rgba(168, 85, 247, 0.1)', duration: 25, x: -60, y: 120 },
  { size: '350px', bottom: '-5%', left: '30%', color: 'rgba(6, 182, 212, 0.08)', duration: 22, x: 60, y: -80 },
]

export default function Hero() {
  return (
    <section style={{ position: 'relative', minHeight: '100vh', display: 'flex', alignItems: 'center', overflow: 'hidden', paddingTop: 80 }}>
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
          animate={{
            x: [0, orb.x, 0],
            y: [0, orb.y, 0],
          }}
          transition={{
            duration: orb.duration,
            repeat: Infinity,
            ease: 'easeInOut',
          }}
        />
      ))}

      <div className="container" style={{ position: 'relative', zIndex: 2 }}>
        <div style={{ maxWidth: 720 }}>
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.1 }}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 8,
              padding: '6px 14px',
              background: 'rgba(99, 102, 241, 0.1)',
              border: '1px solid rgba(99, 102, 241, 0.2)',
              borderRadius: 'var(--radius-full)',
              fontSize: 12,
              fontWeight: 600,
              color: 'var(--color-accent-light)',
              textTransform: 'uppercase',
              letterSpacing: '0.08em',
              marginBottom: 24,
            }}
          >
            <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#6366f1' }} />
            Open Source Hardware
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
            <a href="#demo" className="btn-primary">
              Try the Demo
              <svg width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2.5" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M5 12h14M12 5l7 7-7 7" />
              </svg>
            </a>
            <a href="https://github.com/Viraj69rip/Blink" target="_blank" rel="noopener noreferrer" className="btn-secondary">
              <svg width="16" height="16" fill="currentColor" viewBox="0 0 24 24">
                <path fillRule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" clipRule="evenodd" />
              </svg>
              View on GitHub
            </a>
          </motion.div>

          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.6, delay: 0.5 }}
            style={{ display: 'flex', gap: 20, marginTop: 32, fontSize: 13, color: 'var(--color-text-tertiary)' }}
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
