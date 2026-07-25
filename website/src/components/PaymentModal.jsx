import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

const tiers = {
  basic: { name: 'BLINK Basic', price: 3999 },
  wireless: { name: 'BLINK Wireless', price: 4999 },
  ai: { name: 'BLINK AI', price: 7999 },
}

const UPID_ID = 'blinkrobotics@upi'

export default function PaymentModal({ open, onClose }) {
  const [step, setStep] = useState('form')
  const [variant, setVariant] = useState('basic')
  const [form, setForm] = useState({ name: '', phone: '', email: '', address: '', pincode: '' })
  const [submitted, setSubmitted] = useState(false)

  const update = (field) => (e) => setForm((f) => ({ ...f, [field]: e.target.value }))

  const handleSubmit = (e) => {
    e.preventDefault()
    setStep('payment')
  }

  const handleConfirm = () => {
    setSubmitted(true)
    const msg = `BLINK Order\n\nVariant: ${tiers[variant].name}\nAmount: ₹${tiers[variant].price}\nName: ${form.name}\nPhone: ${form.phone}\nAddress: ${form.address}`
    setForm((f) => ({ ...f, orderMsg: msg }))
  }

  const reset = () => {
    setStep('form')
    setVariant('basic')
    setForm({ name: '', phone: '', email: '', address: '', pincode: '' })
    setSubmitted(false)
    onClose()
  }

  const copyUpi = () => {
    navigator.clipboard.writeText(UPID_ID)
  }

  if (!open) return null

  const selected = tiers[variant]

  return (
    <AnimatePresence>
      <div
        style={{
          position: 'fixed', inset: 0, zIndex: 999,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          padding: 16,
        }}
      >
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={reset}
          style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.7)', backdropFilter: 'blur(8px)' }}
        />
        <motion.div
          initial={{ opacity: 0, scale: 0.92, y: 20 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.92, y: 20 }}
          transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
          className="payment-modal"
          style={{
            position: 'relative', zIndex: 2,
            width: '100%', maxWidth: 480,
            background: '#12121a',
            border: '1px solid rgba(255,255,255,0.1)',
            borderRadius: 24,
            padding: 32,
            maxHeight: '90vh', overflowY: 'auto',
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
            <h3 style={{ fontFamily: 'var(--font-display)', fontSize: 20 }}>
              {step === 'form' ? 'Place Order' : 'Complete Payment'}
            </h3>
            <button
              onClick={reset}
              style={{
                background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.1)',
                borderRadius: '50%', width: 32, height: 32, display: 'flex',
                alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
                color: 'var(--color-text-secondary)', fontSize: 16,
              }}
            >&times;</button>
          </div>

          {step === 'form' && (
            <form onSubmit={handleSubmit}>
              <div style={{ marginBottom: 20 }}>
                <label style={{ fontSize: 12, fontWeight: 600, color: 'var(--color-text-tertiary)', textTransform: 'uppercase', letterSpacing: '0.06em', display: 'block', marginBottom: 8 }}>
                  Select Variant
                </label>
                <div className="variant-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
                  {Object.entries(tiers).map(([key, t]) => (
                    <button
                      key={key}
                      type="button"
                      onClick={() => setVariant(key)}
                      style={{
                        padding: '10px 8px',
                        borderRadius: 12,
                        border: '1px solid',
                        borderColor: variant === key ? 'rgba(99,102,241,0.5)' : 'rgba(255,255,255,0.1)',
                        background: variant === key ? 'rgba(99,102,241,0.15)' : 'rgba(255,255,255,0.03)',
                        color: variant === key ? '#fff' : 'var(--color-text-secondary)',
                        fontSize: 11, fontWeight: 600, cursor: 'pointer',
                        textAlign: 'center',
                      }}
                    >
                      <div>{t.name.replace('BLINK ', '')}</div>
                      <div style={{ fontSize: 13, color: variant === key ? '#818cf8' : 'var(--color-text-tertiary)', marginTop: 4 }}>₹{t.price}</div>
                    </button>
                  ))}
                </div>
              </div>

              <div style={{ display: 'grid', gap: 12 }}>
                <input required placeholder="Full Name" value={form.name} onChange={update('name')}
                  style={inputStyle} />
                <input required placeholder="Phone Number" type="tel" value={form.phone} onChange={update('phone')}
                  style={inputStyle} />
                <input placeholder="Email (optional)" type="email" value={form.email} onChange={update('email')}
                  style={inputStyle} />
                <textarea required placeholder="Delivery Address" rows={3} value={form.address} onChange={update('address')}
                  style={{ ...inputStyle, resize: 'vertical' }} />
                <input required placeholder="Pincode" value={form.pincode} onChange={update('pincode')}
                  style={inputStyle} />
              </div>

              <div style={{ display: 'flex', gap: 12, marginTop: 24 }}>
                <button type="button" onClick={reset}
                  style={{ flex: 1, padding: '12px 0', borderRadius: 12, border: '1px solid rgba(255,255,255,0.1)',
                    background: 'transparent', color: 'var(--color-text-secondary)', fontWeight: 600, cursor: 'pointer', fontSize: 14 }}>
                  Cancel
                </button>
                <button type="submit"
                  style={{ flex: 1, padding: '12px 0', borderRadius: 12, border: 'none',
                    background: 'linear-gradient(135deg, #6366f1, #a855f7)', color: 'white', fontWeight: 700, cursor: 'pointer', fontSize: 14 }}>
                  Continue to Payment — ₹{selected.price}
                </button>
              </div>
            </form>
          )}

          {step === 'payment' && !submitted && (
            <div>
              <div style={{
                background: 'rgba(255,255,255,0.03)', borderRadius: 16, padding: 20, marginBottom: 20,
                border: '1px solid rgba(255,255,255,0.06)',
              }}>
                <p style={{ fontSize: 13, color: 'var(--color-text-tertiary)', marginBottom: 8 }}>Order Summary</p>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
                  <span style={{ fontSize: 14 }}>{selected.name}</span>
                  <span style={{ fontWeight: 700, color: '#818cf8' }}>₹{selected.price}</span>
                </div>
                <p style={{ fontSize: 12, color: 'var(--color-text-tertiary)' }}>{form.name} &middot; {form.phone}</p>
              </div>

              <div style={{ textAlign: 'center', marginBottom: 20 }}>
                <p style={{ fontSize: 13, color: 'var(--color-text-tertiary)', marginBottom: 12 }}>
                  Scan to pay via UPI
                </p>
                <img
                  src={import.meta.env.BASE_URL + 'qr.jpg'}
                  alt="UPI QR Code"
                  style={{
                    width: 'min(200px, 70vw)', height: 'min(200px, 70vw)',
                    borderRadius: 16, margin: '0 auto',
                    border: '1px solid rgba(255,255,255,0.1)',
                  }}
                />
                <div style={{ marginTop: 12 }}>
                  <p style={{ fontSize: 12, color: 'var(--color-text-tertiary)', marginBottom: 4 }}>Or pay to UPI ID:</p>
                  <div
                    onClick={copyUpi}
                    style={{
                      display: 'inline-flex', alignItems: 'center', gap: 8,
                      padding: '8px 16px', borderRadius: 8,
                      background: 'rgba(99,102,241,0.1)', border: '1px solid rgba(99,102,241,0.2)',
                      cursor: 'pointer', fontSize: 14, fontWeight: 600, color: '#818cf8',
                    }}
                  >
                    {UPID_ID}
                    <svg width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
                      <rect x="9" y="9" width="13" height="13" rx="2" />
                      <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" />
                    </svg>
                  </div>
                </div>
              </div>

              <p style={{ fontSize: 12, color: 'var(--color-text-tertiary)', textAlign: 'center', marginBottom: 16 }}>
                After payment, click confirm to receive order details.
              </p>

              <button onClick={handleConfirm}
                style={{
                  width: '100%', padding: '14px 0', borderRadius: 12, border: 'none',
                  background: 'linear-gradient(135deg, #6366f1, #a855f7)', color: 'white',
                  fontWeight: 700, fontSize: 15, cursor: 'pointer',
                }}>
                I've Paid — Confirm Order
              </button>
            </div>
          )}

          {submitted && (
            <div style={{ textAlign: 'center', padding: '20px 0' }}>
              <div style={{
                width: 56, height: 56, borderRadius: '50%',
                background: 'rgba(52, 211, 153, 0.15)', border: '1px solid rgba(52, 211, 153, 0.3)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                margin: '0 auto 16px',
              }}>
                <svg width="24" height="24" fill="none" stroke="#34d399" strokeWidth="2.5" viewBox="0 0 24 24">
                  <polyline points="20 6 9 17 4 12" />
                </svg>
              </div>
              <h3 style={{ fontFamily: 'var(--font-display)', fontSize: 20, marginBottom: 8 }}>Order Placed!</h3>
              <p style={{ fontSize: 14, color: 'var(--color-text-secondary)', marginBottom: 4 }}>
                Thank you, {form.name}!
              </p>
              <p style={{ fontSize: 13, color: 'var(--color-text-tertiary)', marginBottom: 20 }}>
                We'll send order confirmation to <strong>{form.phone}</strong> within 24 hours.
              </p>
              <div style={{
                background: 'rgba(255,255,255,0.03)', borderRadius: 12, padding: 16, marginBottom: 20,
                border: '1px solid rgba(255,255,255,0.06)', textAlign: 'left', fontSize: 13,
                color: 'var(--color-text-tertiary)',
              }}>
                <p style={{ marginBottom: 4 }}><strong style={{ color: 'var(--color-text-secondary)' }}>Variant:</strong> {selected.name}</p>
                <p style={{ marginBottom: 4 }}><strong style={{ color: 'var(--color-text-secondary)' }}>Amount:</strong> ₹{selected.price}</p>
                <p style={{ marginBottom: 4 }}><strong style={{ color: 'var(--color-text-secondary)' }}>Delivery:</strong> {form.address}</p>
              </div>
              <button onClick={reset}
                style={{
                  width: '100%', padding: '12px 0', borderRadius: 12, border: '1px solid rgba(255,255,255,0.1)',
                  background: 'transparent', color: 'white', fontWeight: 600, cursor: 'pointer', fontSize: 14,
                }}>
                Close
              </button>
            </div>
          )}
        </motion.div>
      </div>
    </AnimatePresence>
  )
}

const inputStyle = {
  width: '100%', padding: '12px 14px', borderRadius: 12,
  border: '1px solid rgba(255,255,255,0.1)',
  background: 'rgba(255,255,255,0.04)',
  color: 'white', fontSize: 14, outline: 'none',
  fontFamily: 'inherit',
}
