import { useEffect, useRef, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { UPI_ID, ORDER_DELIVERY, hasOrderChannel } from '../config'

const tiers = {
  basic: { name: 'BLINK Basic', price: 3999 },
  wireless: { name: 'BLINK Wireless', price: 4999 },
  ai: { name: 'BLINK AI', price: 7999 },
}

const emptyForm = { name: '', phone: '', email: '', address: '', pincode: '' }

const buildOrderText = (variantKey, form) => {
  const tier = tiers[variantKey]
  return [
    'BLINK order',
    '',
    `Variant: ${tier.name}`,
    `Amount: Rs ${tier.price}`,
    `Name: ${form.name}`,
    `Phone: ${form.phone}`,
    form.email ? `Email: ${form.email}` : null,
    `Address: ${form.address}`,
    `Pincode: ${form.pincode}`,
  ]
    .filter((l) => l !== null)
    .join('\n')
}

/** WhatsApp first, then email. Returns null when the owner configured neither. */
const orderHandoffUrl = (variantKey, form) => {
  const text = buildOrderText(variantKey, form)
  if (ORDER_DELIVERY.whatsapp) {
    return `https://wa.me/${ORDER_DELIVERY.whatsapp}?text=${encodeURIComponent(text)}`
  }
  if (ORDER_DELIVERY.email) {
    const subject = `BLINK order — ${tiers[variantKey].name}`
    return `mailto:${ORDER_DELIVERY.email}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(text)}`
  }
  return null
}

export default function PaymentModal({ open, onClose, variant: initialVariant = 'basic' }) {
  const [step, setStep] = useState('form')
  const [variant, setVariant] = useState(initialVariant)
  const [form, setForm] = useState(emptyForm)
  const [submitted, setSubmitted] = useState(false)
  const [copied, setCopied] = useState(null)

  const dialogRef = useRef(null)
  const firstFieldRef = useRef(null)
  const openerRef = useRef(null)

  // The tier the visitor actually clicked. Without this the modal always
  // opened on Basic, no matter which card's "Order Now" was pressed.
  useEffect(() => {
    if (open) setVariant(initialVariant)
  }, [open, initialVariant])

  // Remember what had focus so it can be handed back on close, and stop the
  // page behind a full-screen overlay from scrolling under the finger.
  useEffect(() => {
    if (!open) return
    openerRef.current = document.activeElement
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    firstFieldRef.current?.focus()
    return () => {
      document.body.style.overflow = previousOverflow
      if (openerRef.current instanceof HTMLElement) openerRef.current.focus()
    }
  }, [open])

  const close = () => {
    setStep('form')
    setForm(emptyForm)
    setSubmitted(false)
    setCopied(null)
    onClose()
  }

  // Escape closes, and Tab is kept inside the dialog — otherwise focus walks
  // off into the page behind the overlay where nothing is visible.
  useEffect(() => {
    if (!open) return
    const onKeyDown = (e) => {
      if (e.key === 'Escape') {
        e.stopPropagation()
        close()
        return
      }
      if (e.key !== 'Tab') return
      const focusable = dialogRef.current?.querySelectorAll(
        'button, [href], input, textarea, select, [tabindex]:not([tabindex="-1"])',
      )
      if (!focusable?.length) return
      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault()
        last.focus()
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault()
        first.focus()
      }
    }
    window.addEventListener('keydown', onKeyDown, true)
    return () => window.removeEventListener('keydown', onKeyDown, true)
  })

  const update = (field) => (e) => setForm((f) => ({ ...f, [field]: e.target.value }))

  const handleSubmit = (e) => {
    e.preventDefault()
    setStep('payment')
  }

  const handoffUrl = orderHandoffUrl(variant, form)

  const handleConfirm = () => {
    // If the owner configured a delivery channel, hand the order to it before
    // showing the receipt — the click is still inside the user gesture, so the
    // popup blocker leaves it alone.
    if (handoffUrl) window.open(handoffUrl, '_blank', 'noopener,noreferrer')
    setSubmitted(true)
  }

  const copy = async (text, which) => {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(which)
      window.setTimeout(() => setCopied(null), 1800)
    } catch {
      // Insecure context or a denied permission — the text is on screen and
      // selectable, so say so rather than failing silently.
      setCopied('error')
      window.setTimeout(() => setCopied(null), 2400)
    }
  }

  const selected = tiers[variant]

  return (
    <AnimatePresence>
      {open && (
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
            onClick={close}
            style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.7)', backdropFilter: 'blur(8px)' }}
          />
          <motion.div
            ref={dialogRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby="payment-modal-title"
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
              <h3 id="payment-modal-title" style={{ fontFamily: 'var(--font-display)', fontSize: 20 }}>
                {submitted ? 'Order Summary' : step === 'form' ? 'Place Order' : 'Complete Payment'}
              </h3>
              <button
                type="button"
                onClick={close}
                aria-label="Close order form"
                style={{
                  background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.1)',
                  borderRadius: '50%', width: 32, height: 32, display: 'flex',
                  alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
                  color: 'var(--color-text-secondary)', fontSize: 16, flexShrink: 0,
                }}
              >&times;</button>
            </div>

            {step === 'form' && !submitted && (
              <form onSubmit={handleSubmit}>
                <div style={{ marginBottom: 20 }}>
                  <label style={labelStyle}>Select Variant</label>
                  <div className="variant-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
                    {Object.entries(tiers).map(([key, t]) => (
                      <button
                        key={key}
                        type="button"
                        aria-pressed={variant === key}
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
                        <div style={{ fontSize: 13, color: variant === key ? '#818cf8' : 'var(--color-text-tertiary)', marginTop: 4 }}>&#8377;{t.price}</div>
                      </button>
                    ))}
                  </div>
                </div>

                <div style={{ display: 'grid', gap: 12 }}>
                  <input ref={firstFieldRef} required placeholder="Full Name" autoComplete="name"
                    value={form.name} onChange={update('name')} style={inputStyle} />
                  <input required placeholder="Phone Number" type="tel" autoComplete="tel"
                    inputMode="numeric" pattern="[0-9+\-\s]{10,15}"
                    title="10-digit mobile number"
                    value={form.phone} onChange={update('phone')} style={inputStyle} />
                  <input placeholder="Email (optional)" type="email" autoComplete="email"
                    value={form.email} onChange={update('email')} style={inputStyle} />
                  <textarea required placeholder="Delivery Address" rows={3} autoComplete="street-address"
                    value={form.address} onChange={update('address')}
                    style={{ ...inputStyle, resize: 'vertical' }} />
                  <input required placeholder="Pincode" autoComplete="postal-code"
                    inputMode="numeric" pattern="[0-9]{6}" title="6-digit Indian pincode"
                    value={form.pincode} onChange={update('pincode')} style={inputStyle} />
                </div>

                <div style={{ display: 'flex', gap: 12, marginTop: 24 }}>
                  <button type="button" onClick={close}
                    style={{ flex: 1, padding: '12px 0', borderRadius: 12, border: '1px solid rgba(255,255,255,0.1)',
                      background: 'transparent', color: 'var(--color-text-secondary)', fontWeight: 600, cursor: 'pointer', fontSize: 14 }}>
                    Cancel
                  </button>
                  <button type="submit" style={primaryButtonStyle}>
                    Continue &mdash; &#8377;{selected.price}
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
                    <span style={{ fontWeight: 700, color: '#818cf8' }}>&#8377;{selected.price}</span>
                  </div>
                  <p style={{ fontSize: 12, color: 'var(--color-text-tertiary)' }}>{form.name} &middot; {form.phone}</p>
                </div>

                <div style={{ textAlign: 'center', marginBottom: 20 }}>
                  <p style={{ fontSize: 13, color: 'var(--color-text-tertiary)', marginBottom: 12 }}>
                    Scan to pay via UPI
                  </p>
                  <img
                    src={import.meta.env.BASE_URL + 'qr.jpg'}
                    alt={`UPI QR code for paying ${UPI_ID}`}
                    width="200"
                    height="200"
                    style={{
                      width: 'min(200px, 70vw)', height: 'min(200px, 70vw)',
                      borderRadius: 16, margin: '0 auto',
                      border: '1px solid rgba(255,255,255,0.1)',
                    }}
                  />
                  <div style={{ marginTop: 12 }}>
                    <p style={{ fontSize: 12, color: 'var(--color-text-tertiary)', marginBottom: 4 }}>Or pay to UPI ID:</p>
                    <button
                      type="button"
                      onClick={() => copy(UPI_ID, 'upi')}
                      style={{
                        display: 'inline-flex', alignItems: 'center', gap: 8,
                        padding: '8px 16px', borderRadius: 8,
                        background: 'rgba(99,102,241,0.1)', border: '1px solid rgba(99,102,241,0.2)',
                        cursor: 'pointer', fontSize: 14, fontWeight: 600, color: '#818cf8',
                      }}
                    >
                      {copied === 'upi' ? 'Copied!' : UPI_ID}
                      <svg width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24" aria-hidden="true">
                        <rect x="9" y="9" width="13" height="13" rx="2" />
                        <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" />
                      </svg>
                    </button>
                  </div>
                </div>

                <p style={{ fontSize: 12, color: 'var(--color-text-tertiary)', textAlign: 'center', marginBottom: 16 }}>
                  {hasOrderChannel()
                    ? 'Paid? Confirm below and your order details will open in a message, ready to send.'
                    : 'Paid? Confirm below to get your order details — you will need to send them to the seller.'}
                </p>

                <div style={{ display: 'flex', gap: 12 }}>
                  <button type="button" onClick={() => setStep('form')}
                    style={{ flex: '0 0 auto', padding: '14px 18px', borderRadius: 12, border: '1px solid rgba(255,255,255,0.1)',
                      background: 'transparent', color: 'var(--color-text-secondary)', fontWeight: 600, cursor: 'pointer', fontSize: 14 }}>
                    Back
                  </button>
                  <button type="button" onClick={handleConfirm} style={{ ...primaryButtonStyle, padding: '14px 0', fontSize: 15 }}>
                    I&apos;ve Paid &mdash; Confirm Order
                  </button>
                </div>
              </div>
            )}

            {submitted && (
              <div style={{ textAlign: 'center', padding: '4px 0' }}>
                <div style={{
                  width: 56, height: 56, borderRadius: '50%',
                  background: 'rgba(52, 211, 153, 0.15)', border: '1px solid rgba(52, 211, 153, 0.3)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  margin: '0 auto 16px',
                }}>
                  <svg width="24" height="24" fill="none" stroke="#34d399" strokeWidth="2.5" viewBox="0 0 24 24" aria-hidden="true">
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </div>
                <h3 style={{ fontFamily: 'var(--font-display)', fontSize: 20, marginBottom: 8 }}>
                  {hasOrderChannel() ? 'Order sent!' : 'One last step'}
                </h3>
                <p style={{ fontSize: 14, color: 'var(--color-text-secondary)', marginBottom: 4 }}>
                  Thanks, {form.name || 'friend'}!
                </p>
                <p style={{ fontSize: 13, color: 'var(--color-text-tertiary)', marginBottom: 20 }}>
                  {hasOrderChannel()
                    ? 'Your order opened in a new tab — send that message and we will confirm on your phone.'
                    : 'Copy the details below and send them to the seller along with your payment screenshot. Nothing was transmitted from this page.'}
                </p>

                <pre style={{
                  background: 'rgba(255,255,255,0.03)', borderRadius: 12, padding: 16, marginBottom: 12,
                  border: '1px solid rgba(255,255,255,0.06)', textAlign: 'left', fontSize: 12,
                  color: 'var(--color-text-secondary)', whiteSpace: 'pre-wrap', wordBreak: 'break-word',
                  fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', lineHeight: 1.7,
                }}>
                  {buildOrderText(variant, form)}
                </pre>

                <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
                  <button type="button" onClick={() => copy(buildOrderText(variant, form), 'order')}
                    style={{ ...primaryButtonStyle, padding: '12px 0' }}>
                    {copied === 'order' ? 'Copied!' : copied === 'error' ? 'Copy failed — select it above' : 'Copy order details'}
                  </button>
                  {handoffUrl && (
                    <a href={handoffUrl} target="_blank" rel="noopener noreferrer"
                      style={{
                        flex: 1, padding: '12px 0', borderRadius: 12, border: '1px solid rgba(255,255,255,0.1)',
                        background: 'transparent', color: 'white', fontWeight: 600, fontSize: 14, textAlign: 'center',
                      }}>
                      Send again
                    </a>
                  )}
                </div>

                <button type="button" onClick={close}
                  style={{
                    width: '100%', marginTop: 12, padding: '12px 0', borderRadius: 12,
                    border: '1px solid rgba(255,255,255,0.1)',
                    background: 'transparent', color: 'var(--color-text-secondary)', fontWeight: 600, cursor: 'pointer', fontSize: 14,
                  }}>
                  Close
                </button>
              </div>
            )}
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  )
}

const labelStyle = {
  fontSize: 12, fontWeight: 600, color: 'var(--color-text-tertiary)',
  textTransform: 'uppercase', letterSpacing: '0.06em', display: 'block', marginBottom: 8,
}

const inputStyle = {
  width: '100%', padding: '12px 14px', borderRadius: 12,
  border: '1px solid rgba(255,255,255,0.1)',
  background: 'rgba(255,255,255,0.04)',
  color: 'white', fontSize: 14, outline: 'none',
  fontFamily: 'inherit',
}

const primaryButtonStyle = {
  flex: 1, padding: '12px 0', borderRadius: 12, border: 'none',
  background: 'linear-gradient(135deg, #6366f1, #a855f7)',
  color: 'white', fontWeight: 700, cursor: 'pointer', fontSize: 14,
}
