import { useRef, useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import usePrefersReducedMotion from '../hooks/usePrefersReducedMotion'

const states = [
  { id: 'idle', label: 'Idle' },
  { id: 'happy', label: 'Happy' },
  { id: 'dizzy', label: 'Dizzy' },
  { id: 'yawn', label: 'Yawning' },
  { id: 'love', label: 'Love' },
  { id: 'app', label: 'App Mode' },
]

function drawEyes(ctx, x, y, r, t, blinkFreq = 3) {
  const blink = Math.sin(t * blinkFreq) > 0.92
  ctx.fillStyle = '#ffffff'
  if (blink) {
    ctx.fillRect(x - r, y - 1, r * 2, 3)
  } else {
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill()
    ctx.fillStyle = '#000000'
    const px = Math.sin(t * 0.5) * r * 0.2
    const py = Math.cos(t * 0.7) * r * 0.15
    ctx.beginPath(); ctx.arc(x + px, y + py, r * 0.45, 0, Math.PI * 2); ctx.fill()
    ctx.fillStyle = '#ffffff'
    ctx.beginPath(); ctx.arc(x + px - r * 0.15, y + py - r * 0.15, r * 0.15, 0, Math.PI * 2); ctx.fill()
  }
}

function drawIdle(ctx, t, w, h) {
  drawEyes(ctx, w * 0.285, h * 0.33, w * 0.05, t)
  drawEyes(ctx, w * 0.715, h * 0.33, w * 0.05, t)
  ctx.strokeStyle = '#ffffff'
  ctx.lineWidth = 2
  ctx.lineCap = 'round'
  const breath = Math.sin(t * 1.2) * 1.5
  ctx.beginPath()
  ctx.arc(w * 0.5, h * 0.62 + breath, w * 0.04, 0.15 * Math.PI, 0.85 * Math.PI)
  ctx.stroke()
}

function drawHappy(ctx, t, w, h) {
  const shake = Math.sin(t * 18) * 1.5
  ctx.strokeStyle = '#ffffff'
  ctx.lineWidth = 2.2
  ctx.lineCap = 'round'
  ctx.beginPath(); ctx.moveTo(w * 0.22 + shake, h * 0.38); ctx.lineTo(w * 0.285 + shake, h * 0.26); ctx.lineTo(w * 0.35 + shake, h * 0.38); ctx.stroke()
  ctx.beginPath(); ctx.moveTo(w * 0.65 + shake, h * 0.38); ctx.lineTo(w * 0.715 + shake, h * 0.26); ctx.lineTo(w * 0.78 + shake, h * 0.38); ctx.stroke()
  ctx.fillStyle = '#ffffff'
  const mouthOpen = 0.5 + Math.sin(t * 6) * 0.15
  ctx.beginPath(); ctx.ellipse(w * 0.5 + shake, h * 0.64, w * 0.065, h * 0.06 * mouthOpen, 0, 0, Math.PI * 2); ctx.fill()
  ctx.fillStyle = 'rgba(255,255,255,0.08)'
  ctx.beginPath(); ctx.arc(w * 0.2 + shake, h * 0.48, w * 0.035, 0, Math.PI * 2); ctx.fill()
  ctx.beginPath(); ctx.arc(w * 0.8 + shake, h * 0.48, w * 0.035, 0, Math.PI * 2); ctx.fill()
}

function drawDizzy(ctx, t, w, h) {
  ctx.strokeStyle = '#ffffff'
  ctx.lineWidth = 1.8
  ;[w * 0.285, w * 0.715].forEach((cx) => {
    ctx.beginPath()
    for (let i = 0; i < 24; i++) {
      const a = t * 4 + i * 0.3
      const r = 2 + i * 0.35 + Math.sin(t * 2 + i) * 0.5
      const x = cx + Math.cos(a) * r
      const y = h * 0.36 + Math.sin(a) * r * 0.6
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
    }
    ctx.stroke()
  })
  ctx.fillStyle = 'rgba(255,255,255,0.8)'
  const wobble = Math.sin(t * 10) * 2
  for (let i = 0; i < 4; i++) {
    const a = t * 3 + i * 1.57
    const r = 6 + Math.sin(t * 2 + i) * 2
    const sx = w * 0.5 + Math.cos(a) * r
    const sy = h * 0.64 + Math.sin(a) * r * 0.5 + wobble
    ctx.beginPath(); ctx.arc(sx, sy, 1.5, 0, Math.PI * 2); ctx.fill()
  }
}

function drawYawn(ctx, t, w, h) {
  ctx.fillStyle = '#ffffff'
  const eyeH = 0.5 + Math.sin(t * 1.5) * 0.15
  ctx.beginPath(); ctx.ellipse(w * 0.285, h * 0.33, w * 0.05, w * 0.035 * eyeH, 0, 0, Math.PI, false); ctx.fill()
  ctx.beginPath(); ctx.ellipse(w * 0.715, h * 0.33, w * 0.05, w * 0.035 * eyeH, 0, 0, Math.PI, false); ctx.fill()
  const yawnH = h * 0.24 + Math.sin(t * 2) * h * 0.06
  ctx.beginPath(); ctx.ellipse(w * 0.5, h * 0.66, w * 0.075, yawnH / 2, 0, 0, Math.PI * 2); ctx.fill()
  ctx.fillStyle = '#000000'
  ctx.beginPath(); ctx.ellipse(w * 0.5, h * 0.7, w * 0.04, yawnH / 4, 0, 0, Math.PI * 2); ctx.fill()
  ctx.fillStyle = 'rgba(255,255,255,0.6)'
  ctx.font = `${h * 0.1}px monospace`
  ctx.fillText('z', w * 0.88, h * 0.22)
  ctx.fillText('z', w * 0.94, h * 0.14)
}

function drawLove(ctx, t, w, h) {
  drawEyes(ctx, w * 0.285, h * 0.30, w * 0.055, t, 2)
  drawEyes(ctx, w * 0.715, h * 0.30, w * 0.055, t, 2)
  ctx.fillStyle = '#ffffff'
  ctx.beginPath()
  const pulse = 1 + Math.sin(t * 3) * 0.06
  const hx = w * 0.5, hy = h * 0.54
  ctx.moveTo(hx, hy + h * 0.04 * pulse)
  ctx.bezierCurveTo(hx + w * 0.1 * pulse, hy - h * 0.04 * pulse, hx + w * 0.05 * pulse, hy - h * 0.1 * pulse, hx, hy - h * 0.02 * pulse)
  ctx.bezierCurveTo(hx - w * 0.05 * pulse, hy - h * 0.1 * pulse, hx - w * 0.1 * pulse, hy - h * 0.04 * pulse, hx, hy + h * 0.04 * pulse)
  ctx.fill()
  for (let i = 0; i < 5; i++) {
    const a = t * 2 + i * 1.26
    const r = 8 + Math.sin(t * 1.5 + i) * 3
    const px = w * 0.3 + Math.cos(a) * r * 0.6 + w * 0.2
    const py = h * 0.46 + Math.sin(a) * r * 0.4
    ctx.fillStyle = `rgba(255,255,255,${0.3 + Math.sin(t + i) * 0.15})`
    ctx.beginPath(); ctx.arc(px, py, 1.5 + Math.sin(t + i) * 0.5, 0, Math.PI * 2); ctx.fill()
  }
}

function drawApp(ctx, t, w, h) {
  ctx.textAlign = 'center'
  ctx.font = `bold ${h * 0.16}px monospace`
  ctx.fillStyle = '#818cf8'
  ctx.fillText('BLINK', w * 0.5, h * 0.22)
  ctx.font = `${h * 0.08}px monospace`
  ctx.fillStyle = 'rgba(255,255,255,0.5)'
  ctx.fillText('CONNECTED', w * 0.5, h * 0.34)
  const barCount = 5
  for (let i = 0; i < barCount; i++) {
    const bh = h * 0.3 * ((i + 1) / barCount) + Math.sin(t * 3 + i * 1.2) * h * 0.04
    const bx = w * 0.25 + i * (w * 0.1)
    ctx.fillStyle = `rgba(129, 140, 248, ${0.4 + (i / barCount) * 0.6})`
    ctx.fillRect(bx, h * 0.72 - bh, w * 0.05, bh)
  }
  const dotX = w * 0.5 + Math.cos(t * 1.5) * w * 0.08
  const dotY = h * 0.5 + Math.sin(t * 1.8) * h * 0.06
  ctx.fillStyle = '#6366f1'
  ctx.shadowColor = '#6366f1'
  ctx.shadowBlur = 8
  ctx.beginPath(); ctx.arc(dotX, dotY, w * 0.025, 0, Math.PI * 2); ctx.fill()
  ctx.shadowBlur = 0
  ctx.fillStyle = 'rgba(255,255,255,0.08)'
  ctx.beginPath(); ctx.arc(dotX, dotY, w * 0.055, 0, Math.PI * 2); ctx.fill()
}

const drawers = { idle: drawIdle, happy: drawHappy, dizzy: drawDizzy, yawn: drawYawn, love: drawLove, app: drawApp }

// 2× the robot's real 128×64 panel, so strokes land on half-pixels and the
// upscale stays crisp. The 2:1 aspect ratio is the panel's own.
const CANVAS_W = 256
const CANVAS_H = 128

export default function Demo() {
  const canvasRef = useRef(null)
  const frameRef = useRef(null)
  const [currentState, setCurrentState] = useState('idle')
  const [visible, setVisible] = useState(false)
  const stateRef = useRef('idle')
  const reducedMotion = usePrefersReducedMotion()

  useEffect(() => {
    stateRef.current = currentState
  }, [currentState])

  // Only animate while the simulator is actually on screen. requestAnimationFrame
  // keeps firing at 60 Hz for a canvas scrolled far out of view, which used to
  // burn a frame's worth of work per tick for the whole visit.
  useEffect(() => {
    const frame = frameRef.current
    if (!frame) return
    const observer = new IntersectionObserver(
      ([entry]) => setVisible(entry.isIntersecting),
      { rootMargin: '120px' },
    )
    observer.observe(frame)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const w = canvas.width
    const h = canvas.height

    const paint = (t) => {
      // Reset everything the draw functions mutate. They share one context, so
      // leaving e.g. textAlign: 'center' set by App Mode used to shift the
      // sleep "z" glyphs the next time Yawning was selected.
      ctx.textAlign = 'left'
      ctx.textBaseline = 'alphabetic'
      ctx.lineCap = 'butt'
      ctx.lineWidth = 1
      ctx.shadowBlur = 0
      ctx.fillStyle = '#000000'
      ctx.fillRect(0, 0, w, h)
      const draw = drawers[stateRef.current]
      if (draw) draw(ctx, t, w, h)
    }

    if (reducedMotion || !visible) {
      // Still show the face, just frozen at a representative moment rather
      // than a black rectangle.
      paint(1.2)
      return
    }

    let animId
    const start = performance.now()
    const render = (ts) => {
      paint((ts - start) / 1000)
      animId = requestAnimationFrame(render)
    }
    animId = requestAnimationFrame(render)
    return () => cancelAnimationFrame(animId)
  }, [visible, reducedMotion, currentState])

  const activeLabel = states.find((s) => s.id === currentState)?.label

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
            <svg width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24" aria-hidden="true">
              <path strokeLinecap="round" strokeLinejoin="round" d="M14.25 9.75L16.5 12l-2.25 2.25m-4.5 0L7.5 12l2.25-2.25M6 20.25h12A2.25 2.25 0 0020.25 18V6A2.25 2.25 0 0018 3.75H6A2.25 2.25 0 003.75 6v12A2.25 2.25 0 006 20.25z" />
            </svg>
            Live Demo
          </div>
          <h2 className="section-title">OLED Simulator</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            BLINK&apos;s emotional states, rendered at 2&times; the robot&apos;s real 128&times;64 OLED. Pick a mood.
          </p>
        </motion.div>

        <motion.div
          ref={frameRef}
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
              boxShadow: 'inset 0 2px 8px rgba(0,0,0,0.6), 0 12px 36px rgba(0,0,0,0.3)',
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
              <canvas
                ref={canvasRef}
                width={CANVAS_W}
                height={CANVAS_H}
                role="img"
                aria-label={`BLINK OLED simulation showing the ${activeLabel} state`}
                style={{ width: '100%', height: '100%', imageRendering: 'pixelated', display: 'block' }}
              />
            </div>
          </div>

          <div
            role="group"
            aria-label="Robot state"
            style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 8, marginTop: 24 }}
          >
            {states.map((s) => {
              const active = currentState === s.id
              return (
                <motion.button
                  key={s.id}
                  type="button"
                  aria-pressed={active}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => setCurrentState(s.id)}
                  style={{
                    padding: '8px 18px',
                    fontSize: 13,
                    fontWeight: 600,
                    borderRadius: 'var(--radius-full)',
                    border: '1px solid',
                    borderColor: active ? 'rgba(99, 102, 241, 0.5)' : 'var(--color-border)',
                    background: active ? 'rgba(99, 102, 241, 0.2)' : 'rgba(255,255,255,0.04)',
                    color: active ? '#fff' : 'var(--color-text-secondary)',
                    cursor: 'pointer',
                    transition: 'all 0.2s',
                  }}
                >
                  {s.label}
                </motion.button>
              )
            })}
          </div>

          <p style={{ textAlign: 'center', marginTop: 16, fontSize: 13, color: 'var(--color-text-tertiary)' }}>
            Current state: <span style={{ color: 'var(--color-accent-light)', fontWeight: 600 }}>{activeLabel}</span>
          </p>
        </motion.div>
      </div>
    </section>
  )
}
