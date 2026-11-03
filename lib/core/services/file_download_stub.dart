import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/secure_log.dart';
import '../utils/validators.dart';
import 'document_upload_service.dart';

Future<String?> getPublicDownloadsDirectoryPath() async {
  if (Platform.isAndroid) {
    final publicDownloadDir = Directory('/storage/emulated/0/Download');
    if (await publicDownloadDir.exists()) {
      return publicDownloadDir.path;
    }
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) return extDir.path;
    } catch (_) {}
  }
  try {
    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir != null) return downloadsDir.path;
  } catch (_) {}

  try {
    final appDocDir = await getApplicationDocumentsDirectory();
    return appDocDir.path;
  } catch (_) {}

  return Directory.systemTemp.path;
}

/// Detects file format signature and returns the authentic extension and MIME type.
({String extension, String mimeType, bool isErrorPayload}) _inspectByteSignature(Uint8List bytes) {
  if (bytes.length < 4) {
    return (extension: '.bin', mimeType: 'application/octet-stream', isErrorPayload: false);
  }

  // 1. Check for HTML / JSON error response payload
  final previewLen = bytes.length < 256 ? bytes.length : 256;
  final previewString = ascii.decode(bytes.sublist(0, previewLen), allowInvalid: true).toLowerCase();
  if (previewString.contains('<!doctype html') ||
      previewString.contains('<html') ||
      previewString.contains('{"error"') ||
      previewString.contains('{"message"') ||
      previewString.contains('{"statuscode"')) {
    return (extension: '.txt', mimeType: 'text/html', isErrorPayload: true);
  }

  // 2. PDF magic bytes: %PDF- (0x25, 0x50, 0x44, 0x46)
  if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
    return (extension: '.pdf', mimeType: 'application/pdf', isErrorPayload: false);
  }

  // 3. JPEG magic bytes: 0xFF, 0xD8, 0xFF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return (extension: '.jpg', mimeType: 'image/jpeg', isErrorPayload: false);
  }

  // 4. PNG magic bytes: 0x89, 0x50, 0x4E, 0x47
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return (extension: '.png', mimeType: 'image/png', isErrorPayload: false);
  }

  // 5. WebP magic bytes: RIFF....WEBP
  if (bytes.length > 12 &&
      bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
      bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
    return (extension: '.webp', mimeType: 'image/webp', isErrorPayload: false);
  }

  return (extension: '.bin', mimeType: 'application/octet-stream', isErrorPayload: false);
}

/// Resolves a file name to have the correct extension according to its genuine byte content.
String _resolveAuthenticFileName(String rawFileName, Uint8List bytes) {
  final inspection = _inspectByteSignature(bytes);
  var clean = Validators.sanitizeFileName(rawFileName);

  if (inspection.extension == '.jpg') {
    // If filename was wrongly forced with .pdf, strip it
    if (clean.toLowerCase().endsWith('.jpg.pdf')) {
      clean = clean.substring(0, clean.length - 4);
    } else if (clean.toLowerCase().endsWith('.pdf')) {
      clean = '${clean.substring(0, clean.length - 4)}.jpg';
    } else if (!clean.toLowerCase().endsWith('.jpg') && !clean.toLowerCase().endsWith('.jpeg')) {
      clean = '$clean.jpg';
    }
  } else if (inspection.extension == '.png') {
    if (clean.toLowerCase().endsWith('.png.pdf')) {
      clean = clean.substring(0, clean.length - 4);
    } else if (clean.toLowerCase().endsWith('.pdf')) {
      clean = '${clean.substring(0, clean.length - 4)}.png';
    } else if (!clean.toLowerCase().endsWith('.png')) {
      clean = '$clean.png';
    }
  } else if (inspection.extension == '.pdf') {
    if (!clean.toLowerCase().endsWith('.pdf')) {
      clean = '$clean.pdf';
    }
  }

  return clean;
}

Future<bool> saveOrDownloadFilePlatform({
  required String fileName,
  required Uint8List bytes,
  String? mimeType,
}) async {
  try {
    if (bytes.isEmpty) {
      secureLog('[Download] DOCUMENT_DOWNLOAD_FAILED: Received empty byte payload for $fileName');
      return false;
    }

    final inspection = _inspectByteSignature(bytes);
    if (inspection.isErrorPayload) {
      secureLog('[Download] DOCUMENT_INVALID_BYTES: Refusing to save HTML/JSON error payload as $fileName');
      return false;
    }

    final authenticName = _resolveAuthenticFileName(fileName, bytes);
    final dirPath = await getPublicDownloadsDirectoryPath();
    if (dirPath == null) return false;

    final filePath = '$dirPath/$authenticName';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    secureLog('[Download] Saved $authenticName (${bytes.length} bytes) to $filePath');

    // Open the saved file in default device viewer
    try {
      final res = await OpenFilex.open(filePath);
      if (res.type != ResultType.done) {
        secureLog('[Download] OpenFilex result: ${res.type} - ${res.message}');
      }
    } catch (e) {
      secureLog('[Download] DOCUMENT_VIEW_FAILED: Error opening file with viewer: $e');
    }

    return true;
  } catch (e) {
    secureLog('[Download] DOCUMENT_DOWNLOAD_FAILED: Exception writing file: $e');
    try {
      final tempDir = Directory.systemTemp;
      final authenticName = _resolveAuthenticFileName(fileName, bytes);
      final file = File('${tempDir.path}/$authenticName');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
      return true;
    } catch (_) {
      return false;
    }
  }
}

Future<bool> downloadUrlPlatform({
  required String url,
  required String fileName,
}) async {
  try {
    if (url.isEmpty) {
      secureLog('[Download] DOCUMENT_NOT_FOUND: Empty download URL provided');
      return false;
    }

    String effectiveUrl = url;
    Uint8List? directBytes;

    // 1. If this is a private Supabase storage path or relative path, fetch via storage service
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      try {
        directBytes = await DocumentUploadService.instance.downloadFileBytes(url);
      } catch (e) {
        secureLog('[Download] DOCUMENT_DOWNLOAD_FAILED: Storage download error: $e');
      }

      if (directBytes == null || directBytes.isEmpty) {
        final signed = await DocumentUploadService.instance.getSignedUrl(url);
        if (signed != null && signed.startsWith('http')) {
          effectiveUrl = signed;
        } else {
          secureLog('[Download] DOCUMENT_SIGNED_URL_FAILED: Could not generate signed URL for $url');
          return false;
        }
      }
    }

    // 2. If we already have the bytes from storage, save directly
    if (directBytes != null && directBytes.isNotEmpty) {
      return await saveOrDownloadFilePlatform(fileName: fileName, bytes: directBytes);
    }

    // 3. Otherwise perform HTTP GET and validate headers & byte signature
    final uri = Uri.parse(effectiveUrl);
    final response = await http.get(uri).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      secureLog('[Download] DOCUMENT_DOWNLOAD_FAILED: Server returned HTTP status ${response.statusCode}');
      return false;
    }

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('application/json') || contentType.contains('text/html')) {
      secureLog('[Download] DOCUMENT_MIME_MISMATCH: Content-Type is $contentType for expected document');
      return false;
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      secureLog('[Download] DOCUMENT_INVALID_BYTES: Response body bytes were empty');
      return false;
    }

    return await saveOrDownloadFilePlatform(
      fileName: fileName,
      bytes: bytes,
      mimeType: contentType,
    );
  } catch (e) {
    secureLog('[Download] DOCUMENT_DOWNLOAD_FAILED: Exception during download: $e');
    return false;
  }
}

Future<bool> openDownloadedFilePlatform(String fileName) async {
  try {
    final dirPath = await getPublicDownloadsDirectoryPath();
    if (dirPath != null) {
      final file = File('$dirPath/$fileName');
      if (await file.exists()) {
        final res = await OpenFilex.open(file.path);
        return res.type == ResultType.done;
      }
    }
    final tempFile = File('${Directory.systemTemp.path}/$fileName');
    if (await tempFile.exists()) {
      final res = await OpenFilex.open(tempFile.path);
      return res.type == ResultType.done;
    }
    return false;
  } catch (_) {
    return false;
  }
}
