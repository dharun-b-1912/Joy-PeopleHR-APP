import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

enum FaceQualityIssue {
  none,
  lowLight,
  overexposed,
  coveredOrFlat,
  blurry,
}

class FaceQualityReport {
  final bool ok;
  final FaceQualityIssue issue;
  final String? warningMessage;
  final double avgLuminance;
  final double contrastStdDev;
  final double edgeSharpness;

  const FaceQualityReport({
    required this.ok,
    required this.issue,
    this.warningMessage,
    required this.avgLuminance,
    required this.contrastStdDev,
    required this.edgeSharpness,
  });

  static const FaceQualityReport fallbackOk = FaceQualityReport(
    ok: true,
    issue: FaceQualityIssue.none,
    avgLuminance: 128,
    contrastStdDev: 40,
    edgeSharpness: 15,
  );
}

/// Pure-Dart image quality & lighting analyzer (works on Web, Android, and iOS)
/// that inspects the center face region for low light, glare, blur, or covered lens.
class FaceQualityAnalyzer {
  FaceQualityAnalyzer._();

  static Future<FaceQualityReport> analyze(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      return const FaceQualityReport(
        ok: false,
        issue: FaceQualityIssue.coveredOrFlat,
        warningMessage: 'Empty image captured. Please try again.',
        avgLuminance: 0,
        contrastStdDev: 0,
        edgeSharpness: 0,
      );
    }

    try {
      // Downscale to ~120px wide for fast (<5ms) pixel quality analysis
      final codec = await ui.instantiateImageCodec(imageBytes, targetWidth: 120);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = img.width;
      final h = img.height;
      img.dispose();
      codec.dispose();

      if (byteData == null || w < 16 || h < 16) {
        return FaceQualityReport.fallbackOk;
      }

      final rgba = byteData.buffer.asUint8List();
      // Inspect center 60% x 70% region where the face sits inside the round dial
      final xStart = (w * 0.20).floor();
      final xEnd = (w * 0.80).ceil();
      final yStart = (h * 0.15).floor();
      final yEnd = (h * 0.85).ceil();

      double sum = 0;
      double sumSq = 0;
      double edgeSum = 0;
      int count = 0;
      int edgeCount = 0;

      double lumaAt(int x, int y) {
        final idx = (y * w + x) * 4;
        return 0.299 * rgba[idx] + 0.587 * rgba[idx + 1] + 0.114 * rgba[idx + 2];
      }

      for (var y = yStart; y < yEnd; y++) {
        for (var x = xStart; x < xEnd; x++) {
          final l = lumaAt(x, y);
          sum += l;
          sumSq += l * l;
          count++;

          if (x + 1 < xEnd && y + 1 < yEnd) {
            final gx = (lumaAt(x + 1, y) - l).abs();
            final gy = (lumaAt(x, y + 1) - l).abs();
            edgeSum += (gx + gy) * 0.5;
            edgeCount++;
          }
        }
      }

      if (count == 0) return FaceQualityReport.fallbackOk;

      final mean = sum / count;
      final variance = math.max(0.0, (sumSq / count) - (mean * mean));
      final stdDev = math.sqrt(variance);
      final sharpness = edgeCount > 0 ? edgeSum / edgeCount : 0.0;

      if (mean < 52) {
        return FaceQualityReport(
          ok: false,
          issue: FaceQualityIssue.lowLight,
          warningMessage: 'Low light detected. Move to a brighter spot or face a light source.',
          avgLuminance: mean,
          contrastStdDev: stdDev,
          edgeSharpness: sharpness,
        );
      }

      if (mean > 228) {
        return FaceQualityReport(
          ok: false,
          issue: FaceQualityIssue.overexposed,
          warningMessage: 'Too much glare / bright backlight. Adjust lighting and retry.',
          avgLuminance: mean,
          contrastStdDev: stdDev,
          edgeSharpness: sharpness,
        );
      }

      if (stdDev < 15) {
        return FaceQualityReport(
          ok: false,
          issue: FaceQualityIssue.coveredOrFlat,
          warningMessage: 'Camera looks covered or unclear. Keep your face centered in the circle.',
          avgLuminance: mean,
          contrastStdDev: stdDev,
          edgeSharpness: sharpness,
        );
      }

      if (sharpness < 4.5) {
        return FaceQualityReport(
          ok: false,
          issue: FaceQualityIssue.blurry,
          warningMessage: 'Image looks blurry. Hold steady for a moment while scanning.',
          avgLuminance: mean,
          contrastStdDev: stdDev,
          edgeSharpness: sharpness,
        );
      }

      return FaceQualityReport(
        ok: true,
        issue: FaceQualityIssue.none,
        avgLuminance: mean,
        contrastStdDev: stdDev,
        edgeSharpness: sharpness,
      );
    } catch (_) {
      return FaceQualityReport.fallbackOk;
    }
  }
}

