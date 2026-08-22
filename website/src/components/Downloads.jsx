import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { REPO, REPO_URL } from '../config'

const RELEASES_URL = `${REPO_URL}/releases/latest`
const API_URL = `https://api.github.com/repos/${REPO}/releases/latest`

const ICON_APK = 'M14.25 9.75L16.5 12l-2.25 2.25m-4.5 0L7.5 12l2.25-2.25M6 20.25h12A2.25 2.25 0 0020.25 18V6A2.25 2.25 0 0018 3.75H6A2.25 2.25 0 003.75 6v12A2.25 2.25 0 006 20.25z'
const ICON_BIN = 'M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3'
const ICON_SRC = 'M17.25 6.75L22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3l-4.5 16.5'
const ICON_INO = 'M17.25 6.75L22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3l-4.5 16.5'

/**
 * Static cards. These are what renders before (or instead of) the GitHub
 * lookup, so every link here has to work on its own — which means pointing at
 * the /releases/latest *page* rather than guessing an asset filename. The
 * release workflow stamps the tag into every asset name
 * (`BLINK_Robot-v6.bin`), so no fixed `/releases/latest/download/<name>` URL
 * can ever resolve.
 */
const fallbackCards = [
  {
    key: 'apk',
    title: 'BLINK Companion (Android)',
    desc: 'BLE control, drawing canvas, OTA updates.',
    icon: ICON_APK,
    url: RELEASES_URL,
    cta: 'View release',
  },
  {
    key: 'bin',
    title: 'ESP32-C3 Firmware',
    desc: 'Flash over USB, or push it wirelessly from the app.',
    icon: ICON_BIN,
    url: RELEASES_URL,
    cta: 'View release',
  },
  {
    key: 'src',
    title: 'Source Code',
    desc: 'Hardware notes, firmware and app — all on GitHub.',
    icon: ICON_SRC,
    url: REPO_URL,
    cta: 'Browse',
  },
]

const formatSize = (bytes) => {
  if (!bytes) return null
  const mb = bytes / (1024 * 1024)
  return mb >= 1 ? `${mb.toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`
}

/** Prefers an arm64 build — every phone sold in the last decade — then any APK. */
const pickApk = (assets) => {
  const apks = assets.filter((a) => a.name.endsWith('.apk'))
  return apks.find((a) => /arm64/i.test(a.name)) ?? apks[0]
}

function buildCards(release) {
  if (!release) return fallbackCards

  const assets = release.assets ?? []
  const apk = pickApk(assets)
  const bin = assets.find((a) => a.name.endsWith('.bin'))
  const ino = assets.find((a) => a.name.endsWith('.ino'))

  const cards = [
    apk
      ? {
          key: 'apk',
          title: 'BLINK Companion (Android)',
          desc: 'BLE control, drawing canvas, OTA updates.',
          icon: ICON_APK,
          url: apk.browser_download_url,
          meta: [apk.name, formatSize(apk.size)].filter(Boolean).join(' · '),
          cta: 'Download APK',
        }
      : fallbackCards[0],
    bin
      ? {
          key: 'bin',
          title: 'ESP32-C3 Firmware',
          desc: 'Flash over USB, or push it wirelessly from the app.',
          icon: ICON_BIN,
          url: bin.browser_download_url,
          meta: [bin.name, formatSize(bin.size)].filter(Boolean).join(' · '),
          cta: 'Download .bin',
        }
      : fallbackCards[1],
    fallbackCards[2],
  ]

  if (ino) {
    cards.push({
      key: 'ino',
      title: 'Arduino Sketch',
      desc: 'The shareable .ino, if you would rather compile it yourself.',
      icon: ICON_INO,
      url: ino.browser_download_url,
      meta: [ino.name, formatSize(ino.size)].filter(Boolean).join(' · '),
      cta: 'Download .ino',
    })
  }

  return cards
}

export default function Downloads() {
  const [release, setRelease] = useState(null)
  const [failed, setFailed] = useState(false)

  // Resolved at runtime rather than hardcoded, so a new tag needs no site edit
  // and the card can name the real file and its size. Unauthenticated GitHub
  // API calls are rate-limited per IP; any failure just leaves the static
  // "view release" cards in place.
  useEffect(() => {
    const controller = new AbortController()
    fetch(API_URL, {
      signal: controller.signal,
      headers: { Accept: 'application/vnd.github+json' },
    })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(setRelease)
      .catch((err) => {
        if (err.name !== 'AbortError') setFailed(true)
      })
    return () => controller.abort()
  }, [])

  const cards = buildCards(release)
  const tag = release?.tag_name

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
            <svg width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24" aria-hidden="true">
              <path strokeLinecap="round" strokeLinejoin="round" d={ICON_BIN} />
            </svg>
            Downloads
          </div>
          <h2 className="section-title">Get BLINK</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            {tag
              ? `Latest release ${tag} — app, firmware, and source.`
              : 'The latest app, firmware, and source code.'}
          </p>
          {failed && (
            <p style={{ marginTop: 10, fontSize: 13, color: 'var(--color-text-tertiary)' }}>
              Could not reach GitHub just now — the links below open the release page.
            </p>
          )}
        </motion.div>

        <div style={{ display: 'grid', gap: 16, gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', maxWidth: 900, margin: '0 auto' }}>
          {cards.map((item, i) => (
            <motion.a
              key={item.key}
              href={item.url}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={`${item.cta} — ${item.title}`}
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
                <svg width="22" height="22" fill="none" stroke="#818cf8" strokeWidth="1.8" viewBox="0 0 24 24" aria-hidden="true">
                  <path strokeLinecap="round" strokeLinejoin="round" d={item.icon} />
                </svg>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <p style={{ fontWeight: 700, fontSize: 15, marginBottom: 2 }}>{item.title}</p>
                <p style={{ fontSize: 13, color: 'var(--color-text-tertiary)' }}>{item.desc}</p>
                {item.meta && (
                  <p style={{
                    fontSize: 11,
                    marginTop: 6,
                    color: 'var(--color-text-tertiary)',
                    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}>
                    {item.meta}
                  </p>
                )}
              </div>
              <svg width="16" height="16" fill="none" stroke="var(--color-text-tertiary)" strokeWidth="2" viewBox="0 0 24 24" aria-hidden="true">
                <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 19.5l15-15m0 0H8.25m11.25 0v11.25" />
              </svg>
            </motion.a>
          ))}
        </div>

        <p style={{ textAlign: 'center', marginTop: 24, fontSize: 13, color: 'var(--color-text-tertiary)' }}>
          Android will warn about installing outside the Play Store — that is expected for a
          self-signed APK. Firmware can also be updated wirelessly from inside the app.
        </p>
      </div>
    </section>
  )
}
