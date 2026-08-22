import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/ble_manager.dart';
import '../theme/blink_constants.dart';
import '../theme/blink_theme.dart';

/// The exact pixel dimensions of BLINK's SSD1306 OLED.
const int kOledWidth = 128;
const int kOledHeight = 64;

/// Sending every pointer sample creates a long BLE backlog.  The preview is
/// still updated for every sample, while the robot receives one continuous
/// segment at this cadence (the newest point always wins).
const Duration _kMinimumBleSegmentInterval = Duration(milliseconds: 20);

/// A direct, pixel-accurate drawing surface for BLINK's 128 x 64 OLED.
///
/// The canvas deliberately listens to raw pointer events instead of using a
/// drag recognizer.  Flutter's drag slop is useful for scroll views, but makes
/// a pen feel late here.  A compact bitmap also avoids replaying every old
/// stroke on each pointer update, which was the main source of local lag.
class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    super.key,
    this.ble,
    this.enabled = true,
    this.showGrid = false,
  });

  final BleManager? ble;
  final bool enabled;

  /// A faint 16 px guide can be useful while debugging artwork.  It is off by
  /// default so the preview reads like a clean OLED instead of a field of dots.
  final bool showGrid;

  @override
  State<DrawingCanvas> createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  final Uint8List _pixels = Uint8List(kOledWidth * kOledHeight);
  final ValueNotifier<int> _bitmapRevision = ValueNotifier<int>(0);

  Offset? _lastInputPoint;
  Offset? _lastSentPoint;
  Offset? _queuedRemotePoint;
  int? _activePointer;

  /// True when the next segment sent to the robot begins a fresh stroke.
  ///
  /// Without this, `_lastSentPoint` survived a pointer-up and the first segment
  /// of the next stroke was drawn from the end of the *previous* one — a long
  /// straight line slashed across the artwork every time a finger was lifted.
  bool _startNewStroke = true;

  bool _drawModeRequested = false;
  bool _writeInFlight = false;
  bool _clearing = false;
  DateTime? _lastBleWriteAt;
  Timer? _sendTimer;
  Future<void> _lastWrite = Future<void>.value();

  BleManager get _ble => widget.ble ?? BleManager.instance;

  bool get isEmpty => !_pixels.any((pixel) => pixel != 0);

  Offset _toOled(Offset local, Size size) {
    final safeWidth = size.width <= 0 ? 1.0 : size.width;
    final safeHeight = size.height <= 0 ? 1.0 : size.height;
    final x = (local.dx / safeWidth * (kOledWidth - 1)).round();
    final y = (local.dy / safeHeight * (kOledHeight - 1)).round();
    return Offset(
      x.clamp(0, kOledWidth - 1).toDouble(),
      y.clamp(0, kOledHeight - 1).toDouble(),
    );
  }

  bool _samePoint(Offset a, Offset b) =>
      a.dx.toInt() == b.dx.toInt() && a.dy.toInt() == b.dy.toInt();

  void _ensureDrawMode() {
    if (_drawModeRequested) return;
    _drawModeRequested = true;
    // Keep the UI responsive: waiting for a command response before showing
    // the first pixel is noticeable. BLE preserves write order on the link.
    unawaited(_ble.sendCommand('DRAW'));
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (!widget.enabled || _clearing || _activePointer != null) return;

    _activePointer = event.pointer;
    final point = _toOled(event.localPosition, size);
    _lastInputPoint = point;

    // Break the link to the previous stroke, and drop any tail point that is
    // still waiting behind an in-flight write — it belongs to a stroke the user
    // has already finished.
    _startNewStroke = true;
    _queuedRemotePoint = null;

    _ensureDrawMode();

    // A press without movement is a valid one-pixel mark.
    _drawLocalLine(point, point);
    _queueRemotePoint(point, immediate: true);
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (!widget.enabled || event.pointer != _activePointer || _clearing) {
      return;
    }

    final from = _lastInputPoint;
    if (from == null) return;
    final to = _toOled(event.localPosition, size);
    if (_samePoint(from, to)) return;

    _drawLocalLine(from, to);
    _lastInputPoint = to;
    _queueRemotePoint(to);
  }

  void _onPointerEnd(int pointer) {
    if (pointer != _activePointer) return;
    final finalPoint = _lastInputPoint;
    if (finalPoint != null) {
      _queueRemotePoint(finalPoint, immediate: true);
    }
    _activePointer = null;
    _lastInputPoint = null;
  }

  void _queueRemotePoint(Offset point, {bool immediate = false}) {
    if (_clearing) return;
    _queuedRemotePoint = point;
    if (_writeInFlight) return;

    final now = DateTime.now();
    final lastWrite = _lastBleWriteAt;
    final elapsed = lastWrite == null ? null : now.difference(lastWrite);
    if (immediate ||
        elapsed == null ||
        elapsed >= _kMinimumBleSegmentInterval) {
      _sendTimer?.cancel();
      _sendTimer = null;
      unawaited(_flushLatestRemotePoint());
      return;
    }

    _sendTimer ??= Timer(_kMinimumBleSegmentInterval - elapsed, () {
      _sendTimer = null;
      unawaited(_flushLatestRemotePoint());
    });
  }

  Future<void> _flushLatestRemotePoint() async {
    if (_writeInFlight || _clearing) return;
    final target = _queuedRemotePoint;
    if (target == null) return;
    _queuedRemotePoint = null;

    // The first segment of a stroke is a degenerate `x,y,x,y`, which the
    // firmware rasterises as a single dot — never a line back to wherever the
    // pen happened to be lifted.
    final startNew = _startNewStroke;
    final from = startNew ? target : (_lastSentPoint ?? target);
    if (!startNew && _lastSentPoint != null && _samePoint(from, target)) return;
    _startNewStroke = false;

    _writeInFlight = true;
    _lastSentPoint = target;
    _lastBleWriteAt = DateTime.now();

    final write = _ble.sendDrawLine(
      from.dx.toInt(),
      from.dy.toInt(),
      target.dx.toInt(),
      target.dy.toInt(),
    );
    _lastWrite = write;
    try {
      await write;
    } finally {
      _writeInFlight = false;
      if (mounted && !_clearing && _queuedRemotePoint != null) {
        _queueRemotePoint(_queuedRemotePoint!);
      }
    }
  }

  void _drawLocalLine(Offset from, Offset to) {
    var x0 = from.dx.toInt();
    var y0 = from.dy.toInt();
    final x1 = to.dx.toInt();
    final y1 = to.dy.toInt();
    final dx = (x1 - x0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final dy = -(y1 - y0).abs();
    final sy = y0 < y1 ? 1 : -1;
    var error = dx + dy;
    var changed = false;

    while (true) {
      final index = y0 * kOledWidth + x0;
      if (_pixels[index] == 0) {
        _pixels[index] = 1;
        changed = true;
      }
      if (x0 == x1 && y0 == y1) break;
      final twiceError = error * 2;
      if (twiceError >= dy) {
        error += dy;
        x0 += sx;
      }
      if (twiceError <= dx) {
        error += dx;
        y0 += sy;
      }
    }

    if (changed) _bitmapRevision.value++;
  }

  /// Clears the immediate app preview and the matching robot canvas.
  Future<void> clearAll() async {
    _clearing = true;
    _sendTimer?.cancel();
    _sendTimer = null;
    _queuedRemotePoint = null;
    _activePointer = null;
    _lastInputPoint = null;
    _lastSentPoint = null;
    _startNewStroke = true;

    _pixels.fillRange(0, _pixels.length, 0);
    _bitmapRevision.value++;

    // Preserve BLE ordering: an in-flight segment must finish before CLEAR.
    // This prevents a stale late segment from reappearing after a clear.
    try {
      await _lastWrite;
    } catch (_) {
      // BleManager already handles characteristic write failures. Clearing the
      // local preview should remain deterministic even if the link drops.
    }
    await _ble.sendCommand('CLEAR');
    _lastBleWriteAt = null;
    _drawModeRequested = false;
    _clearing = false;
  }

  @override
  void didUpdateWidget(covariant DrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _sendTimer?.cancel();
      _sendTimer = null;
      _queuedRemotePoint = null;
      _activePointer = null;
      _lastInputPoint = null;
      _startNewStroke = true;
    }
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    _bitmapRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 1,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 1,
          );

          return Semantics(
            label: '128 by 64 pixel OLED drawing canvas',
            hint: widget.enabled
                ? 'Draw with one finger or a stylus. Every mark is sent to BLINK.'
                : 'Connect to BLINK to enable drawing.',
            child: MouseRegion(
              cursor: widget.enabled
                  ? SystemMouseCursors.precise
                  : SystemMouseCursors.forbidden,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _onPointerDown(event, size),
                onPointerMove: (event) => _onPointerMove(event, size),
                onPointerUp: (event) => _onPointerEnd(event.pointer),
                onPointerCancel: (event) => _onPointerEnd(event.pointer),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(
                      BlinkConstants.borderRadiusSmall,
                    ),
                    border: Border.all(
                      color: widget.enabled
                          ? BlinkColors.cardBorder
                          : BlinkColors.cardBorder.withValues(alpha: 0.45),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      BlinkConstants.borderRadiusSmall,
                    ),
                    child: CustomPaint(
                      painter: _OledBitmapPainter(
                        pixels: _pixels,
                        revision: _bitmapRevision,
                        showGrid: widget.showGrid,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OledBitmapPainter extends CustomPainter {
  _OledBitmapPainter({
    required this.pixels,
    required this.revision,
    required this.showGrid,
  }) : super(repaint: revision);

  final Uint8List pixels;
  final ValueListenable<int> revision;
  final bool showGrid;

  int _paintedRevision = -1;
  Path? _pixelPath;

  Path _pixelsAsPath() {
    final currentRevision = revision.value;
    if (_pixelPath != null && _paintedRevision == currentRevision) {
      return _pixelPath!;
    }

    final path = Path();
    for (var y = 0; y < kOledHeight; y++) {
      final rowOffset = y * kOledWidth;
      for (var x = 0; x < kOledWidth; x++) {
        if (pixels[rowOffset + x] != 0) {
          // The fractional overlap removes hairline gaps caused by the device
          // pixel ratio while retaining a faithful OLED-pixel silhouette.
          path.addRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.02, 1.02));
        }
      }
    }
    _paintedRevision = currentRevision;
    _pixelPath = path;
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cellWidth = size.width / kOledWidth;
    final cellHeight = size.height / kOledHeight;

    if (showGrid) {
      final guide = Paint()
        ..color = Colors.white.withValues(alpha: 0.055)
        ..strokeWidth = 1;
      for (var x = 0; x <= kOledWidth; x += 16) {
        canvas.drawLine(
          Offset(x * cellWidth, 0),
          Offset(x * cellWidth, size.height),
          guide,
        );
      }
      for (var y = 0; y <= kOledHeight; y += 16) {
        canvas.drawLine(
          Offset(0, y * cellHeight),
          Offset(size.width, y * cellHeight),
          guide,
        );
      }
    }

    canvas.save();
    canvas.scale(cellWidth, cellHeight);
    canvas.drawPath(
      _pixelsAsPath(),
      Paint()
        ..color = BlinkColors.textPrimary
        ..style = PaintingStyle.fill
        ..isAntiAlias = false,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OledBitmapPainter oldDelegate) =>
      oldDelegate.showGrid != showGrid || oldDelegate.pixels != pixels;
}
