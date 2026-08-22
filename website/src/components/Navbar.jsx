import { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { REPO_URL } from '../config'

const navLinks = [
  { label: 'Pricing', href: '#pricing' },
  { label: 'Demo', href: '#demo' },
  { label: 'Specs', href: '#specs' },
  { label: 'Downloads', href: '#downloads' },
]

const GithubMark = ({ size = 14 }) => (
  <svg width={size} height={size} fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
    <path fillRule="evenodd" clipRule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" />
  </svg>
)

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const [activeSection, setActiveSection] = useState('')

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  // Scroll spy. Cheaper and smoother than measuring offsets on every scroll
  // event: the browser tells us which section owns the upper band of the
  // viewport, and the band is offset by the bar's own height so a section
  // hidden behind the bar is never reported as active.
  useEffect(() => {
    const sections = navLinks
      .map((l) => document.querySelector(l.href))
      .filter(Boolean)
    if (!sections.length) return

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
        if (visible.length) setActiveSection(`#${visible[0].target.id}`)
      },
      { rootMargin: '-80px 0px -55% 0px', threshold: 0 },
    )
    sections.forEach((s) => observer.observe(s))
    return () => observer.disconnect()
  }, [])

  // Escape closes the mobile sheet, which is otherwise only dismissable by
  // hitting the (now off-screen) toggle again.
  useEffect(() => {
    if (!menuOpen) return
    const onKey = (e) => {
      if (e.key === 'Escape') setMenuOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [menuOpen])

  const closeMenu = () => setMenuOpen(false)

  return (
    <motion.nav
      initial={{ y: -20, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.6, ease: [0.22, 1, 0.36, 1] }}
      aria-label="Main"
      className={scrolled || menuOpen ? 'glass' : ''}
      style={{
        // Inline, not utility classes: this project has no Tailwind, so the
        // `fixed top-0 z-50` classnames this used to carry did nothing and the
        // bar scrolled away with the page.
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        zIndex: 50,
        padding: '14px 0',
        transition: 'background-color 0.4s, border-color 0.4s, backdrop-filter 0.4s',
      }}
    >
      <div className="container" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <a href="#top" style={{ display: 'flex', alignItems: 'center', gap: 10 }} aria-label="BLINK — home">
          <span style={{ fontFamily: 'var(--font-display)', fontSize: 22, color: 'white', letterSpacing: '0.08em' }}>BLINK</span>
        </a>

        <div className="nav-desktop" style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
          {navLinks.map((link) => {
            const active = activeSection === link.href
            return (
              <a
                key={link.href}
                href={link.href}
                aria-current={active ? 'true' : undefined}
                style={{
                  position: 'relative',
                  fontSize: 14,
                  fontWeight: 500,
                  color: active ? 'white' : 'var(--color-text-secondary)',
                  transition: 'color 0.2s',
                  whiteSpace: 'nowrap',
                  paddingBottom: 2,
                }}
                onMouseEnter={(e) => (e.currentTarget.style.color = 'white')}
                onMouseLeave={(e) => (e.currentTarget.style.color = active ? 'white' : 'var(--color-text-secondary)')}
              >
                {link.label}
                {active && (
                  <motion.span
                    layoutId="nav-underline"
                    style={{
                      position: 'absolute',
                      left: 0,
                      right: 0,
                      bottom: -4,
                      height: 2,
                      borderRadius: 2,
                      background: 'var(--color-accent-gradient)',
                    }}
                  />
                )}
              </a>
            )
          })}
          <a href={REPO_URL} target="_blank" rel="noopener noreferrer"
            className="btn-primary hide-mobile"
            style={{ padding: '8px 16px', fontSize: 13 }}>
            <GithubMark />
            <span>GitHub</span>
          </a>
        </div>

        <button onClick={() => setMenuOpen((v) => !v)} className="hamburger"
          style={{
            display: 'none', background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.12)',
            borderRadius: 8, width: 36, height: 36, cursor: 'pointer', color: 'white', fontSize: 18, alignItems: 'center', justifyContent: 'center', padding: 0,
          }}
          aria-label={menuOpen ? 'Close menu' : 'Open menu'}
          aria-expanded={menuOpen}
          aria-controls="mobile-menu">
          <svg width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24" aria-hidden="true">
            {menuOpen ? <path strokeLinecap="round" d="M6 18L18 6M6 6l12 12" /> : <path strokeLinecap="round" d="M4 6h16M4 12h16M4 18h16" />}
          </svg>
        </button>
      </div>

      <AnimatePresence>
        {menuOpen && (
          <motion.div
            id="mobile-menu"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            className="mobile-menu"
            style={{
              display: 'none', position: 'absolute', top: '100%', left: 0, right: 0,
              background: '#12121a', borderBottom: '1px solid rgba(255,255,255,0.1)',
              padding: '12px 24px 20px',
            }}>
            {navLinks.map((link) => (
              <a key={link.href} href={link.href} onClick={closeMenu}
                aria-current={activeSection === link.href ? 'true' : undefined}
                style={{
                  display: 'block', padding: '10px 0', fontSize: 15, fontWeight: 500,
                  color: activeSection === link.href ? 'white' : 'var(--color-text-secondary)',
                  borderBottom: '1px solid rgba(255,255,255,0.05)',
                }}>
                {link.label}
              </a>
            ))}
            <a href={REPO_URL} target="_blank" rel="noopener noreferrer" onClick={closeMenu}
              className="btn-primary" style={{ width: '100%', justifyContent: 'center', marginTop: 12, padding: '10px 0', fontSize: 14 }}>
              <GithubMark />
              GitHub
            </a>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.nav>
  )
}
