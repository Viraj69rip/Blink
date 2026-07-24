import 'package:flutter/material.dart';
import '../theme/blink_theme.dart';

/// Renders the BLINK logo using a dot-matrix / stippled effect.
/// Each letter is composed of small dots arranged in a pixel-font grid.
class DottedLogo extends StatelessWidget {
  final double dotSize;
  final double spacing;
  final Color color;

  const DottedLogo({
    super.key,
    this.dotSize = 3.0,
    this.spacing = 2.0,
    this.color = BlinkColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final step = dotSize + spacing;
    // 5 letters, each 5 cols wide, 4 gaps of 1 col each = 29 cols total
    final totalWidth = 29 * step;
    final totalHeight = 7 * step;

    return CustomPaint(
      size: Size(totalWidth, totalHeight),
      painter: _DottedLogoPainter(
        dotSize: dotSize,
        spacing: spacing,
        color: color,
      ),
    );
  }
}

class _DottedLogoPainter extends CustomPainter {
  final double dotSize;
  final double spacing;
  final Color color;

  _DottedLogoPainter({
    required this.dotSize,
    required this.spacing,
    required this.color,
  });

  // 5x7 dot-matrix font definitions for B, L, I, N, K
  // Each letter is a list of 7 rows, each row is a list of booleans
  static const Map<String, List<List<bool>>> _font = {
    'B': [
      [true, true, true, true, false],
      [true, false, false, false, true],
      [true, false, false, false, true],
      [true, true, true, true, false],
      [true, false, false, false, true],
      [true, false, false, false, true],
      [true, true, true, true, false],
    ],
    'L': [
      [true, false, false, false, false],
      [true, false, false, false, false],
      [true, false, false, false, false],
      [true, false, false, false, false],
      [true, false, false, false, false],
      [true, false, false, false, false],
      [true, true, true, true, true],
    ],
    'I': [
      [true, true, true, true, true],
      [false, false, true, false, false],
      [false, false, true, false, false],
      [false, false, true, false, false],
      [false, false, true, false, false],
      [false, false, true, false, false],
      [true, true, true, true, true],
    ],
    'N': [
      [true, false, false, false, true],
      [true, true, false, false, true],
      [true, false, true, false, true],
      [true, false, true, false, true],
      [true, false, false, true, true],
      [true, false, false, true, true],
      [true, false, false, false, true],
    ],
    'K': [
      [true, false, false, false, true],
      [true, false, false, true, false],
      [true, false, true, false, false],
      [true, true, false, false, false],
      [true, false, true, false, false],
      [true, false, false, true, false],
      [true, false, false, false, true],
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final step = dotSize + spacing;
    final letters = ['B', 'L', 'I', 'N', 'K'];
    final letterSpacing = step * 6; // 5 cols + 1 gap between letters

    // Center vertically
    final totalHeight = 7 * step;
    final yOffset = (size.height - totalHeight) / 2;

    // Center horizontally
    final totalWidth = letters.length * letterSpacing - step;
    final xOffset = (size.width - totalWidth) / 2;

    for (int l = 0; l < letters.length; l++) {
      final grid = _font[letters[l]]!;
      for (int row = 0; row < grid.length; row++) {
        for (int col = 0; col < grid[row].length; col++) {
          if (grid[row][col]) {
            canvas.drawCircle(
              Offset(
                xOffset + l * letterSpacing + col * step + dotSize / 2,
                yOffset + row * step + dotSize / 2,
              ),
              dotSize / 2,
              paint,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLogoPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.dotSize != dotSize ||
        oldDelegate.spacing != spacing;
  }
}
