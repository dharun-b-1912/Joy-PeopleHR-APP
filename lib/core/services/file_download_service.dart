import 'dart:typed_data';
import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';

class FileDownloadService {
  /// Save bytes directly to the user's Downloads or trigger browser download
  static Future<bool> downloadBytes({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    return saveOrDownloadFilePlatform(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  /// Trigger browser download directly from a signed or public URL
  static Future<bool> downloadFromUrl({
    required String url,
    required String fileName,
  }) async {
    return downloadUrlPlatform(
      url: url,
      fileName: fileName,
    );
  }
}
