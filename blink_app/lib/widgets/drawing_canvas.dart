import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ble_manager.dart';
import '../theme/blink_constants.dart';
import '../theme/blink_theme.dart';

/// The exact pixel dimensions of BLINK's SSD1306 OLED.
const int kOledWidth = 128;
const int kOledHeight = 64;

/// A pixel-art drawing surface. Every visible white cell is an OLED pixel,
/// and each emitted segment is the same integer line sent to the robot.
class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({super.key, this.ble, this.enabled = true});

  final BleManager? ble;
  final bool enabled;

  @override
  State<DrawingCanvas> createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  final List<_OledStroke> _strokes = <_OledStroke>[];
  Offset? _lastOled;
  Future<void> _sendQueue = Future<void>.value();
  bool _drawModeSent = false;

  BleManager get _ble => widget.ble ?? BleManager.instance;

  Offset _toOled(Offset local, Size size) {
    final x = (local.dx / size.width * (kOledWidth - 1)).round();
    final y = (local.dy / size.height * (kOledHeight - 1)).round();
    return Offset(
      x.clamp(0, kOledWidth - 1).toDouble(),
      y.clamp(0, kOledHeight - 1).toDouble(),
    );
  }

  void _ensureDrawMode() {
    if (_drawModeSent) return;
    _drawModeSent = true;
    _ble.sendCommand('DRAW');
  }

  void _emitSegment(Offset from, Offset to) {
    // Ordered BLE writes keep the OLED and local pixel grid in lockstep.
    _sendQueue = _sendQueue.then((_) => _ble.sendDrawLine(
          from.dx.toInt(),
          from.dy.toInt(),
          to.dx.toInt(),
          to.dy.toInt(),
        ));
  }

  void _onPanStart(DragStartDetails details, Size size) {
    if (!widget.enabled) return;
    _lastOled = _toOled(details.localPosition, size);
    _ensureDrawMode();
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final from = _lastOled;
    if (!widget.enabled || from == null) return;
    final to = _toOled(details.localPosition, size);
    if (to == from) return;

    setState(() {
      _strokes.add(_OledStroke(from: from, to: to));
    });
    _emitSegment(from, to);
    _lastOled = to;
  }

  void _onPanEnd(DragEndDetails _) => _lastOled = null;

  Future<void> clearAll() async {
    setState(() {
      _strokes.clear();
      _lastOled = null;
      _drawModeSent = false;
    });
    await _ble.sendCommand('CLEAR');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _onPanStart(details, size),
          onPanUpdate: (details) => _onPanUpdate(details, size),
          onPanEnd: _onPanEnd,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius:
                  BorderRadius.circular(BlinkConstants.borderRadiusSmall),
              border: Border.all(color: BlinkColors.cardBorder),
            ),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(BlinkConstants.borderRadiusSmall),
              child: CustomPaint(
                painter:
                    _PixelGridPainter(strokes: List<_OledStroke>.of(_strokes)),
                size: size,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OledStroke {
  const _OledStroke({required this.from, required this.to});
  final Offset from;
  final Offset to;
}

class _PixelGridPainter extends CustomPainter {
  const _PixelGridPainter({required this.strokes});

  final List<_OledStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / kOledWidth;
    final cellH = size.height / kOledHeight;
    final majorGrid = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..strokeWidth = 1;

    // Major cells make the actual 128×64 coordinate system readable without
    // drawing the old dotted background.
    for (var x = 0; x <= kOledWidth; x += 8) {
      canvas.drawLine(
          Offset(x * cellW, 0), Offset(x * cellW, size.height), majorGrid);
    }
    for (var y = 0; y <= kOledHeight; y += 8) {
      canvas.drawLine(
          Offset(0, y * cellH), Offset(size.width, y * cellH), majorGrid);
    }

    final pixel = Paint()..color = Colors.white;
    final drawn = <int>{};
    for (final stroke in strokes) {
      _drawOledLine(
        stroke.from.dx.toInt(),
        stroke.from.dy.toInt(),
        stroke.to.dx.toInt(),
        stroke.to.dy.toInt(),
        (x, y) {
          final key = y * kOledWidth + x;
          if (!drawn.add(key)) return;
          // Small overlap avoids visual gaps on fractional pixel sizes.
          canvas.drawRect(
            Rect.fromLTWH(x * cellW, y * cellH, cellW + 0.35, cellH + 0.35),
            pixel,
          );
        },
      );
    }
  }

  void _drawOledLine(
    int x0,
    int y0,
    int x1,
    int y1,
    void Function(int x, int y) drawPixel,
  ) {
    final dx = (x1 - x0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final dy = -(y1 - y0).abs();
    final sy = y0 < y1 ? 1 : -1;
    var error = dx + dy;

    while (true) {
      drawPixel(x0, y0);
      if (x0 == x1 && y0 == y1) return;
      final twiceError = 2 * error;
      if (twiceError >= dy) {
        error += dy;
        x0 += sx;
      }
      if (twiceError <= dx) {
        error += dx;
        y0 += sy;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelGridPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
