import { useRef, useEffect, useState } from 'react'
import { motion } from 'framer-motion'

const states = [
  { id: 'idle', label: 'Idle' },
  { id: 'happy', label: 'Happy' },
  { id: 'dizzy', label: 'Dizzy' },
  { id: 'yawn', label: 'Yawning' },
  { id: 'app', label: 'App Mode' },
]

function drawIdle(ctx, t, w, h) {
  const blink = Math.sin(t * 3) > 0.92
  ctx.strokeStyle = '#ffffff'
  ctx.lineWidth = 2
  ctx.lineCap = 'round'
  if (blink) {
    ctx.beginPath(); ctx.moveTo(w * 0.22, h * 0.35); ctx.lineTo(w * 0.35, h * 0.35); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(w * 0.65, h * 0.35); ctx.lineTo(w * 0.78, h * 0.35); ctx.stroke()
  } else {
    ctx.fillStyle = '#ffffff'
    ctx.beginPath(); ctx.arc(w * 0.285, h * 0.35, w * 0.055, 0, Math.PI * 2); ctx.fill()
    ctx.beginPath(); ctx.arc(w * 0.715, h * 0.35, w * 0.055, 0, Math.PI * 2); ctx.fill()
  }
  ctx.beginPath()
  ctx.arc(w * 0.5, h * 0.62, w * 0.045, 0.15 * Math.PI, 0.85 * Math.PI)
  ctx.stroke()
}

function drawHappy(ctx, t, w, h) {
  ctx.strokeStyle = '#ffffff'
  ctx.lineWidth = 2
  ctx.lineCap = 'round'
  const s = Math.sin(t * 16) * 2
  ctx.beginPath(); ctx.moveTo(w * 0.22 + s, h * 0.40); ctx.lineTo(w * 0.285 + s, h * 0.28); ctx.lineTo(w * 0.35 + s, h * 0.40); ctx.stroke()
  ctx.beginPath(); ctx.moveTo(w * 0.65 + s, h * 0.40); ctx.lineTo(w * 0.715 + s, h * 0.28); ctx.lineTo(w * 0.78 + s, h * 0.40); ctx.stroke()
  ctx.fillStyle = '#ffffff'
  ctx.beginPath(); ctx.ellipse(w * 0.5 + s, h * 0.66, w * 0.06, h * 0.07, 0, 0, Math.PI * 2); ctx.fill()
}

function drawDizzy(ctx, t, w, h) {
  ctx.strokeStyle = '#ffffff'
  ctx.lineWidth = 2
  ;[w * 0.285, w * 0.715].forEach((cx) => {
    ctx.beginPath()
    for (let i = 0; i < 20; i++) {
      const a = t * 3.5 + i * 0.4
      const r = 2 + i * 0.3
      const x = cx + Math.cos(a) * r
      const y = h * 0.38 + Math.sin(a) * r
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
    }
    ctx.stroke()
  })
  ctx.beginPath(); ctx.arc(w * 0.5, h * 0.72, w * 0.03, 0, Math.PI * 2); ctx.stroke()
}

function drawYawn(ctx, t, w, h) {
  ctx.fillStyle = '#ffffff'
  ctx.beginPath(); ctx.arc(w * 0.285, h * 0.35, w * 0.055, 0, Math.PI, false); ctx.fill()
  ctx.beginPath(); ctx.arc(w * 0.715, h * 0.35, w * 0.055, 0, Math.PI, false); ctx.fill()
  const mouthH = h * 0.22 + Math.sin(t * 2.5) * h * 0.04
  ctx.beginPath(); ctx.ellipse(w * 0.5, h * 0.68, w * 0.07, mouthH / 2, 0, 0, Math.PI * 2); ctx.fill()
}

function drawApp(ctx, t, w, h) {
  ctx.textAlign = 'center'
  ctx.font = `${h * 0.17}px monospace`
  ctx.fillStyle = '#ffffff'
  ctx.fillText('APP MODE', w * 0.5, h * 0.22)
  for (let i = 0; i < 4; i++) {
    const bh = h * 0.28 * ((i + 1) / 4) + Math.sin(t * 4 + i) * h * 0.04
    ctx.fillStyle = i === 3 ? '#818cf8' : '#ffffff'
    ctx.fillRect(w * 0.3 + i * w * 0.08, h * 0.8 - bh, w * 0.045, bh)
  }
  const ox = w * 0.5 + Math.cos(t * 2) * w * 0.09
  const oy = h * 0.48 + Math.sin(t * 2) * h * 0.08
  ctx.fillStyle = '#6366f1'
  ctx.beginPath(); ctx.arc(ox, oy, w * 0.025, 0, Math.PI * 2); ctx.fill()
}

const drawers = { idle: drawIdle, happy: drawHappy, dizzy: drawDizzy, yawn: drawYawn, app: drawApp }

export default function Demo() {
  const canvasRef = useRef(null)
  const [currentState, setCurrentState] = useState('idle')
  const stateRef = useRef('idle')
  const timeRef = useRef(0)

  useEffect(() => {
    stateRef.current = currentState
    timeRef.current = 0
  }, [currentState])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    let animId
    let start = performance.now()

    function render(ts) {
      const t = (ts - start) / 1000
      const w = canvas.width
      const h = canvas.height
      ctx.fillStyle = '#000000'
      ctx.fillRect(0, 0, w, h)
      const draw = drawers[stateRef.current]
      if (draw) draw(ctx, t, w, h)
      animId = requestAnimationFrame(render)
    }
    animId = requestAnimationFrame(render)
    return () => cancelAnimationFrame(animId)
  }, [])

  return (
    <section id="demo" className="section" style={{ position: 'relative' }}>
      <div className="container">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-80px' }}
          transition={{ duration: 0.5 }}
          style={{ textAlign: 'center', marginBottom: 48 }}
        >
          <div className="section-label" style={{ margin: '0 auto 20px' }}>
            <svg width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" d="M14.25 9.75L16.5 12l-2.25 2.25m-4.5 0L7.5 12l2.25-2.25M6 20.25h12A2.25 2.25 0 0020.25 18V6A2.25 2.25 0 0018 3.75H6A2.25 2.25 0 003.75 6v12A2.25 2.25 0 006 20.25z" />
            </svg>
            Live Demo
          </div>
          <h2 className="section-title">OLED Simulator</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            See BLINK's emotional states in action on a pixel-accurate 128x64 display simulation.
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          whileInView={{ opacity: 1, scale: 1 }}
          viewport={{ once: true, margin: '-80px' }}
          transition={{ duration: 0.6 }}
          style={{
            maxWidth: 520,
            margin: '0 auto',
            background: 'linear-gradient(145deg, #1a1a28, #12121a)',
            border: '1px solid var(--color-border)',
            borderRadius: 'var(--radius-xl)',
            padding: 32,
          }}
        >
          <div
            style={{
              background: 'linear-gradient(145deg, #1f2937, #111827)',
              borderRadius: 20,
              padding: 12,
              border: '1px solid rgba(255,255,255,0.08)',
              boxShadow: 'inset 0 2px 8px rgba(0,0,0,0.6)',
            }}
          >
            <div
              style={{
                background: '#000',
                borderRadius: 10,
                overflow: 'hidden',
                position: 'relative',
                boxShadow: 'inset 0 0 20px rgba(0,0,0,0.9)',
                aspectRatio: '2/1',
              }}
            >
              <canvas ref={canvasRef} width="256" height="128" style={{ width: '100%', height: '100%', imageRendering: 'pixelated' }} />
            </div>
          </div>

          <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 8, marginTop: 24 }}>
            {states.map((s) => (
              <motion.button
                key={s.id}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={() => setCurrentState(s.id)}
                style={{
                  padding: '8px 18px',
                  fontSize: 13,
                  fontWeight: 600,
                  borderRadius: 'var(--radius-full)',
                  border: '1px solid',
                  borderColor: currentState === s.id ? 'rgba(99, 102, 241, 0.5)' : 'var(--color-border)',
                  background: currentState === s.id ? 'rgba(99, 102, 241, 0.2)' : 'rgba(255,255,255,0.04)',
                  color: currentState === s.id ? '#fff' : 'var(--color-text-secondary)',
                  cursor: 'pointer',
                  transition: 'all 0.2s',
                }}
              >
                {s.label}
              </motion.button>
            ))}
          </div>

          <p style={{ textAlign: 'center', marginTop: 16, fontSize: 13, color: 'var(--color-text-tertiary)' }}>
            Current state: <span style={{ color: 'var(--color-accent-light)', fontWeight: 600 }}>{states.find((s) => s.id === currentState)?.label}</span>
          </p>
        </motion.div>
      </div>
    </section>
  )
}
