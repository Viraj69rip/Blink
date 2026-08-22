import { motion } from 'framer-motion'

// Kept in step with firmware/BLINK_Robot/BLINK_Robot.ino — the pin map at the
// top of that file and the U8g2 constructor are the source of truth here.
const specs = [
  { label: 'Microcontroller', value: 'ESP32-C3', detail: 'RISC-V single-core @ 160 MHz' },
  { label: 'Display', value: '0.96" OLED', detail: '128x64 px, SSD1306, I2C on GPIO 8/9' },
  { label: 'Motion Sensor', value: 'MPU6050', detail: '3-axis accel + 3-axis gyro, shake & tilt' },
  { label: 'Connectivity', value: 'BLE 5 (NimBLE)', detail: 'Custom GATT service, ~10 Hz state sync' },
  { label: 'Updates', value: 'OTA over BLE', detail: 'Flash new firmware from the app' },
  { label: 'Power', value: 'USB-C / 3.7V LiPo', detail: 'Battery level via ADC on GPIO 2' },
  { label: 'Firmware', value: 'Arduino (C++)', detail: 'State-machine animations, 21 idle moods' },
  { label: 'Touch', value: 'Capacitive', detail: 'GPIO 4, tap / hold-to-scroll / long-press' },
  { label: 'Audio', value: 'Piezo Buzzer', detail: 'GPIO 3, melodies & alerts' },
]

const containerVariants = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.04 } },
}

const itemVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: { opacity: 1, y: 0, transition: { duration: 0.5, ease: [0.22, 1, 0.36, 1] } },
}

export default function Specs() {
  return (
    <section id="specs" className="section" style={{ position: 'relative' }}>
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
              <path strokeLinecap="round" strokeLinejoin="round" d="M10.5 1.5H8.25A2.25 2.25 0 006 3.75v16.5a2.25 2.25 0 002.25 2.25h7.5A2.25 2.25 0 0018 20.25V3.75a2.25 2.25 0 00-2.25-2.25H13.5m-3 0V3h3V1.5m-3 0h3m-3 18.75h3" />
            </svg>
            Tech Specs
          </div>
          <h2 className="section-title">Under the hood</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            The hardware and software stack that powers your desk companion.
          </p>
        </motion.div>

        <motion.div
          variants={containerVariants}
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, margin: '-80px' }}
          style={{
            display: 'grid',
            gap: 12,
            gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
          }}
        >
          {specs.map((spec) => (
            <motion.div
              key={spec.label}
              variants={itemVariants}
              whileHover={{ y: -2 }}
              style={{
                background: 'var(--color-surface)',
                border: '1px solid var(--color-border)',
                borderRadius: 'var(--radius-md)',
                padding: '20px 24px',
                transition: 'border-color 0.3s',
              }}
              onMouseEnter={(e) => (e.currentTarget.style.borderColor = 'rgba(99, 102, 241, 0.2)')}
              onMouseLeave={(e) => (e.currentTarget.style.borderColor = 'var(--color-border)')}
            >
              <p style={{ fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.08em', color: 'var(--color-text-tertiary)', marginBottom: 6 }}>
                {spec.label}
              </p>
              <p style={{ fontSize: 17, fontWeight: 700, color: 'var(--color-accent-light)', marginBottom: 4 }}>
                {spec.value}
              </p>
              <p style={{ fontSize: 13, color: 'var(--color-text-secondary)' }}>
                {spec.detail}
              </p>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  )
}
