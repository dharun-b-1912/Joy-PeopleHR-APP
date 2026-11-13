import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Optimizes captured face images by cropping to the center portrait dial
/// (removing background posters/bystanders) and compressing size without
/// sacrificing facial feature clarity for 1:1 recognition.
class FaceImageOptimizer {
  FaceImageOptimizer._();

  static const int maxDimension = 512;
  static const int jpegQuality = 85;

  /// Crops the captured frame to the center region visible inside the circular
  /// dial (`min(w, h) * 0.78`), stripping wide background walls/posters.
  static Future<Uint8List> cropToCenterDial(Uint8List rawBytes) async {
    if (rawBytes.isEmpty) return rawBytes;
    try {
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      final srcW = src.width.toDouble();
      final srcH = src.height.toDouble();

      final side = math.min(srcW, srcH) * 0.78;
      final srcRect = ui.Rect.fromCenter(
        center: ui.Offset(srcW / 2, srcH / 2),
        width: side,
        height: side,
      );

      final targetSide = math.min(side.round(), maxDimension).clamp(160, maxDimension);
      final dstRect = ui.Rect.fromLTWH(0, 0, targetSide.toDouble(), targetSide.toDouble());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(src, srcRect, dstRect, ui.Paint()..filterQuality = ui.FilterQuality.medium);
      final picture = recorder.endRecording();
      final outImg = await picture.toImage(targetSide, targetSide);
      final pngBytes = await outImg.toByteData(format: ui.ImageByteFormat.png);

      src.dispose();
      codec.dispose();
      picture.dispose();
      outImg.dispose();

      if (pngBytes != null && pngBytes.lengthInBytes > 0) {
        return pngBytes.buffer.asUint8List();
      }
      return rawBytes;
    } catch (_) {
      return rawBytes;
    }
  }

  static Future<Uint8List> optimizeForFaceVerify(Uint8List rawBytes) async {
    if (rawBytes.isEmpty) return rawBytes;
    final cropped = await cropToCenterDial(rawBytes);

    if (kIsWeb) {
      return cropped;
    }
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        cropped,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: jpegQuality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (compressed.isNotEmpty && compressed.length < cropped.length) {
        return Uint8List.fromList(compressed);
      }
      return cropped;
    } catch (_) {
      return cropped;
    }
  }
}
