import { motion } from 'framer-motion'

const downloads = [
  {
    title: 'BLINK App v2 (Android)',
    desc: 'Companion APK — BLE control, drawing canvas, OTA updates.',
    icon: 'M14.25 9.75L16.5 12l-2.25 2.25m-4.5 0L7.5 12l2.25-2.25M6 20.25h12A2.25 2.25 0 0020.25 18V6A2.25 2.25 0 0018 3.75H6A2.25 2.25 0 003.75 6v12A2.25 2.25 0 006 20.25z',
    url: 'https://github.com/Viraj69rip/Blink/releases/latest/download/BLINK_App_v2_release.apk',
  },
  {
    title: 'BLINK Firmware v3',
    desc: 'ESP32-C3 firmware — flash via USB or OTA from the app.',
    icon: 'M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3',
    url: 'https://github.com/Viraj69rip/Blink/releases/latest/download/BLINK_Firmware_v3.zip',
  },
  {
    title: 'Source Code',
    desc: 'Full project on GitHub — hardware, firmware & app.',
    icon: 'M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z',
    url: 'https://github.com/Viraj69rip/Blink',
  },
]

export default function Downloads() {
  return (
    <section id="downloads" className="section" style={{ position: 'relative' }}>
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
              <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
            </svg>
            Downloads
          </div>
          <h2 className="section-title">Get BLINK</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            Download the latest app, firmware, or browse the source.
          </p>
        </motion.div>

        <div style={{ display: 'grid', gap: 16, gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', maxWidth: 900, margin: '0 auto' }}>
          {downloads.map((item, i) => (
            <motion.a
              key={item.title}
              href={item.url}
              target="_blank"
              rel="noopener noreferrer"
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: '-80px' }}
              transition={{ duration: 0.5, delay: i * 0.1 }}
              whileHover={{ y: -4 }}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 16,
                padding: '20px 24px',
                background: 'var(--color-surface)',
                border: '1px solid var(--color-border)',
                borderRadius: 'var(--radius-md)',
                textDecoration: 'none',
                color: 'inherit',
                transition: 'border-color 0.3s',
              }}
              onMouseEnter={(e) => (e.currentTarget.style.borderColor = 'rgba(99, 102, 241, 0.3)')}
              onMouseLeave={(e) => (e.currentTarget.style.borderColor = 'var(--color-border)')}
            >
              <div style={{
                width: 44,
                height: 44,
                borderRadius: 'var(--radius-sm)',
                background: 'rgba(99, 102, 241, 0.12)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                flexShrink: 0,
              }}>
                <svg width="22" height="22" fill="none" stroke="#818cf8" strokeWidth="1.8" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" d={item.icon} />
                </svg>
              </div>
              <div style={{ flex: 1 }}>
                <p style={{ fontWeight: 700, fontSize: 15, marginBottom: 2 }}>{item.title}</p>
                <p style={{ fontSize: 13, color: 'var(--color-text-tertiary)' }}>{item.desc}</p>
              </div>
              <svg width="16" height="16" fill="none" stroke="var(--color-text-tertiary)" strokeWidth="2" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 19.5l15-15m0 0H8.25m11.25 0v11.25" />
              </svg>
            </motion.a>
          ))}
        </div>
      </div>
    </section>
  )
}
