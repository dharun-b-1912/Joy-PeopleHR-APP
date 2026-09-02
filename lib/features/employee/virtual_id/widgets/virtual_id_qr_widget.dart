import 'dart:math';
import 'package:flutter/material.dart';

/// Clean vector QR Code Painter Widget generating a crisp 21x21 QR matrix
class VirtualIdQrWidget extends StatelessWidget {
  final String data;
  final double size;
  final Color color;

  const VirtualIdQrWidget({
    super.key,
    required this.data,
    this.size = 140,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _QrMatrixPainter(data: data, color: color),
      ),
    );
  }
}

class _QrMatrixPainter extends CustomPainter {
  final String data;
  final Color color;

  _QrMatrixPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const int matrixSize = 21; // 21x21 QR Version 1 Matrix
    final double moduleSize = size.width / matrixSize;

    // Generate deterministic boolean matrix based on data hash + standard QR patterns
    final boolMatrix = _generateMatrix(data, matrixSize);

    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        if (boolMatrix[r][c]) {
          final rect = Rect.fromLTWH(
            c * moduleSize,
            r * moduleSize,
            moduleSize + 0.3,
            moduleSize + 0.3,
          );
          canvas.drawRect(rect, paint);
        }
      }
    }
  }

  List<List<bool>> _generateMatrix(String text, int size) {
    final matrix = List.generate(size, (_) => List.generate(size, (_) => false));

    // 1. Draw 3 Corner Finder Patterns (7x7 Outer, 5x5 Inner white, 3x3 Center block)
    _drawFinder(matrix, 0, 0);
    _drawFinder(matrix, size - 7, 0);
    _drawFinder(matrix, 0, size - 7);

    // 2. Timing Patterns (Row 6, Col 6)
    for (int i = 8; i < size - 8; i += 2) {
      matrix[6][i] = true;
      matrix[i][6] = true;
    }

    // 3. Fill data modules deterministically based on text seed
    int seed = 0;
    for (int i = 0; i < text.length; i++) {
      seed = (seed * 31 + text.codeUnitAt(i)) & 0xFFFFFF;
    }

    final random = Random(seed);

    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        // Skip finder patterns area
        if (_isFinderArea(r, c, size)) continue;
        // Skip timing pattern lines
        if (r == 6 || c == 6) continue;

        // Deterministic pseudo-random module
        matrix[r][c] = random.nextDouble() > 0.45;
      }
    }

    return matrix;
  }

  void _drawFinder(List<List<bool>> matrix, int startR, int startC) {
    for (int r = 0; r < 7; r++) {
      for (int c = 0; c < 7; c++) {
        final isBorder = (r == 0 || r == 6 || c == 0 || c == 6);
        final isCenter = (r >= 2 && r <= 4 && c >= 2 && c <= 4);
        if (isBorder || isCenter) {
          matrix[startR + r][startC + c] = true;
        }
      }
    }
  }

  bool _isFinderArea(int r, int c, int size) {
    if (r < 8 && c < 8) return true; // Top-left
    if (r < 8 && c >= size - 8) return true; // Top-right
    if (r >= size - 8 && c < 8) return true; // Bottom-left
    return false;
  }

  @override
  bool shouldRepaint(covariant _QrMatrixPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}
