/**
 * Site-owner configuration.
 *
 * Everything here is read at build time and shipped in the bundle, so it must
 * only ever contain values that are meant to be public (a shop UPI ID, a
 * business WhatsApp number). Never put an API key or secret in this file.
 */

export const REPO = 'Viraj69rip/Blink'
export const REPO_URL = `https://github.com/${REPO}`

/** UPI handle shown on the payment step, next to the QR in `public/qr.jpg`. */
export const UPI_ID = 'blinkrobotics@upi'

/**
 * Where a submitted order is delivered.
 *
 * The site has no backend, so an order can only reach you if the buyer's own
 * device hands it over — a WhatsApp deep link or a prefilled email. Until at
 * least one of these is filled in, the checkout tells the buyer to copy their
 * order and send it themselves; it does not pretend an order was received.
 *
 * TODO(owner): set `whatsapp` to a full international number with no spaces or
 * '+' (e.g. '919876543210'), and/or `email` to the address that should receive
 * orders. Both are optional; WhatsApp is used first when both are present.
 */
export const ORDER_DELIVERY = {
  whatsapp: '',
  email: '',
}

export const hasOrderChannel = () =>
  Boolean(ORDER_DELIVERY.whatsapp || ORDER_DELIVERY.email)
