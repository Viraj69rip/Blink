// BLINK App Launcher Icon Generator
// Run this script with: dart run tool/generate_icon.dart
// This creates minimal robot-eye BLINK icons for all Android mipmap densities.

import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

/// Generates a minimal PNG image with the BLINK robot eye icon.
/// The icon is a pure black circle with two white robot eyes and a red dot.
void main() async {
  final densities = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  const basePath = 'android/app/src/main/res';

  for (final entry in densities.entries) {
    final dir = entry.key;
    final size = entry.value;
    final pngData = generateBlinkIcon(size);
    final file = File('$basePath/$dir/ic_launcher.png');
    await file.writeAsBytes(pngData);
    print('Generated $dir/ic_launcher.png (${size}x$size)');
  }
}

/// Generate a minimal valid PNG with BLINK robot eye design
/// Uses raw PNG encoding - black background with two white rounded-rect eyes
Uint8List generateBlinkIcon(int size) {
  // Create RGBA pixel data
  final pixels = Uint8List(size * size * 4);
  final center = size / 2;
  final radius = size / 2;

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final idx = (y * size + x) * 4;
      final dx = x - center;
      final dy = y - center;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist <= radius) {
        // Inside the circle - black background
        pixels[idx] = 0;     // R
        pixels[idx + 1] = 0; // G
        pixels[idx + 2] = 0; // B
        pixels[idx + 3] = 255; // A

        // Draw robot eyes (two rounded rectangles)
        final eyeWidth = size * 0.14;
        final eyeHeight = size * 0.3;
        final eyeSpacing = size * 0.11;
        final eyeY = center - size * 0.02;

        // Left eye bounds
        final leftEyeCx = center - eyeSpacing;
        final rightEyeCx = center + eyeSpacing;

        bool inEye(double cx) {
          final ex = (x - cx).abs();
          final ey = (y - eyeY).abs();
          if (ex <= eyeWidth / 2 && ey <= eyeHeight / 2) {
            // Rounded corner check
            final cornerR = eyeWidth * 0.35;
            final innerW = eyeWidth / 2 - cornerR;
            final innerH = eyeHeight / 2 - cornerR;
            if (ex > innerW && ey > innerH) {
              final cdx = ex - innerW;
              final cdy = ey - innerH;
              return sqrt(cdx * cdx + cdy * cdy) <= cornerR;
            }
            return true;
          }
          return false;
        }

        if (inEye(leftEyeCx) || inEye(rightEyeCx)) {
          pixels[idx] = 255;     // R - white
          pixels[idx + 1] = 255; // G
          pixels[idx + 2] = 255; // B
        }

        // Red accent dot below eyes
        final dotCx = center;
        final dotCy = center + size * 0.22;
        final dotR = size * 0.035;
        final dotDx = x - dotCx;
        final dotDy = y - dotCy;
        if (sqrt(dotDx * dotDx + dotDy * dotDy) <= dotR) {
          pixels[idx] = 255;     // R - red accent
          pixels[idx + 1] = 51;  // G
          pixels[idx + 2] = 51;  // B
        }
      } else {
        // Outside circle - transparent
        pixels[idx] = 0;
        pixels[idx + 1] = 0;
        pixels[idx + 2] = 0;
        pixels[idx + 3] = 0;
      }
    }
  }

  return encodePNG(size, size, pixels);
}

/// Minimal PNG encoder
Uint8List encodePNG(int width, int height, Uint8List rgba) {
  final signature = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

  // IHDR chunk
  final ihdrData = ByteData(13);
  ihdrData.setUint32(0, width);
  ihdrData.setUint32(4, height);
  ihdrData.setUint8(8, 8);   // bit depth
  ihdrData.setUint8(9, 6);   // color type (RGBA)
  ihdrData.setUint8(10, 0);  // compression
  ihdrData.setUint8(11, 0);  // filter
  ihdrData.setUint8(12, 0);  // interlace
  final ihdr = _makeChunk('IHDR', ihdrData.buffer.asUint8List());

  // IDAT chunk - raw pixel data with zlib
  final rawData = <int>[];
  for (int y = 0; y < height; y++) {
    rawData.add(0); // filter byte: None
    for (int x = 0; x < width; x++) {
      final idx = (y * width + x) * 4;
      rawData.addAll([rgba[idx], rgba[idx + 1], rgba[idx + 2], rgba[idx + 3]]);
    }
  }
  final compressed = zDeflate(Uint8List.fromList(rawData));
  final idat = _makeChunk('IDAT', compressed);

  // IEND chunk
  final iend = _makeChunk('IEND', Uint8List(0));

  // Combine
  final result = <int>[];
  result.addAll(signature);
  result.addAll(ihdr);
  result.addAll(idat);
  result.addAll(iend);
  return Uint8List.fromList(result);
}

Uint8List _makeChunk(String type, Uint8List data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  final crcInput = <int>[...typeBytes, ...data];
  final crc = _crc32(Uint8List.fromList(crcInput));
  final crcBytes = ByteData(4)..setUint32(0, crc);

  return Uint8List.fromList([
    ...length.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...crcBytes.buffer.asUint8List(),
  ]);
}

int _crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (int i = 0; i < 8; i++) {
      if (crc & 1 == 1) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// Simple DEFLATE compression (zlib wrapper around raw store blocks)
Uint8List zDeflate(Uint8List data) {
  final result = <int>[];
  // Zlib header
  result.addAll([0x78, 0x01]); // CMF + FLG (deflate, no dict, low compression)

  // Store in blocks of max 65535 bytes
  int offset = 0;
  while (offset < data.length) {
    final remaining = data.length - offset;
    final blockLen = remaining > 65535 ? 65535 : remaining;
    final isLast = offset + blockLen >= data.length;

    result.add(isLast ? 0x01 : 0x00); // BFINAL + BTYPE=00 (stored)
    result.add(blockLen & 0xFF);
    result.add((blockLen >> 8) & 0xFF);
    result.add((~blockLen) & 0xFF);
    result.add(((~blockLen) >> 8) & 0xFF);

    result.addAll(data.sublist(offset, offset + blockLen));
    offset += blockLen;
  }

  // Adler32 checksum
  int a = 1, b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  final adler = (b << 16) | a;
  result.addAll([
    (adler >> 24) & 0xFF,
    (adler >> 16) & 0xFF,
    (adler >> 8) & 0xFF,
    adler & 0xFF,
  ]);

  return Uint8List.fromList(result);
}
