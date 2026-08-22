import 'package:flutter/rendering.dart';

/// Laid-out [TextPainter]s, keyed by the exact text and style they were built
/// from.
///
/// The face and pairing painters draw a handful of short, rarely-changing
/// strings ('BLINK', 'FOCUS', 'z') on every frame. Laying those out per frame is
/// pure waste — text layout is one of the more expensive things a painter can
/// do, and none of it changes between frames.
///
/// Keying on the whole [TextStyle] means a painter is only reused when the
/// resolved colour and size match too, so an animated alpha or font size still
/// produces correct output; it simply misses the cache.
final Map<(String, TextStyle), TextPainter> _cache = {};

/// Above this many entries the cache is cleared rather than evicted one by one.
///
/// Styles whose colour or size is animated churn the key every frame, so the
/// map would otherwise grow without bound. A flush is fine: the entries that
/// matter are re-laid-out on the next frame, and the ones being dropped were
/// single-use anyway.
const int _maxEntries = 48;

/// Returns a laid-out painter for [text] in [style], reusing a cached one when
/// possible.
///
/// The returned painter is shared — paint from it, but do not mutate it.
TextPainter cachedTextPainter(String text, TextStyle style) {
  final key = (text, style);
  final hit = _cache[key];
  if (hit != null) return hit;

  if (_cache.length >= _maxEntries) _cache.clear();

  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  _cache[key] = painter;
  return painter;
}

/// Drops every cached painter. Exposed for tests and for a hard reset; normal
/// use relies on the automatic flush at [_maxEntries].
void clearTextPainterCache() => _cache.clear();
