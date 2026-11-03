import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'file_pick_models.dart';
import 'file_pick_stub.dart' if (dart.library.html) 'file_pick_web.dart';

export 'file_pick_models.dart';

/// Service handling REAL Android, Web & Cross-Platform document file picking & validation rules
class FilePickService {
  static const int maxDocumentSizeBytes = 20 * 1024 * 1024; // 20 MB

  static const List<String> allowedExtensions = [
    "pdf",
    "jpg",
    "jpeg",
    "png",
    "webp",
    "doc",
    "docx",
  ];

  static const List<String> disallowedExtensions = [
    "exe",
    "apk",
    "bat",
    "sh",
    "cmd",
    "msi",
    "js",
    "bin",
  ];

  /// Detect file extension from binary header (magic bytes)
  static String? detectExtensionFromBytes(List<int> bytes) {
    if (bytes.length < 4) return null;

    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return "png";
    }
    // JPEG/JPG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return "jpg";
    }
    // PDF: 25 50 44 46 (%PDF)
    if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
      return "pdf";
    }
    // WebP: RIFF ... WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return "webp";
    }
    // DOCX / ZIP: 50 4B 03 04 (PK..)
    if (bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04) {
      return "docx";
    }
    // DOC (OLE2): D0 CF 11 E0
    if (bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) {
      return "doc";
    }

    return null;
  }

  /// Validate selected file extension and file size
  static String? validateFile(SelectedFileResult file) {
    final ext = file.fileExtension.toLowerCase().replaceAll('.', '');
    if (disallowedExtensions.contains(ext)) {
      return "Executable files (.$ext) are forbidden for security reasons.";
    }
    if (file.sizeInBytes > maxDocumentSizeBytes) {
      return "File is too large (${file.formattedSize}). Max size allowed is 20 MB.";
    }
    if (ext.isNotEmpty && !allowedExtensions.contains(ext)) {
      return "Unsupported format (.$ext). Allowed: PDF, JPG, PNG, WEBP, DOC, DOCX.";
    }
    return null; // Valid
  }

  /// Opens the system device file picker (Mobile & Web compatible)
  static Future<SelectedFileResult?> pickDocumentFile({String? preferredDocType}) async {
    try {
      // 1. Direct native HTML5 picker on Web (100% reliable on Chrome/Firefox/Safari)
      if (kIsWeb) {
        debugPrint('[FILE_PICKER] Initiating Native HTML5 Web File Picker...');
        final webResult = await pickHtmlWebFile();
        if (webResult != null) {
          debugPrint('[FILE_PICKER] Native HTML5 Web File selected: ${webResult.fileName} (${webResult.formattedSize})');
          return webResult;
        }
      }

      // 2. Cross-platform FilePicker for Android, iOS & Desktop
      debugPrint('[FILE_PICKER] Initiating Cross-Platform FilePicker...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final platformFile = result.files.first;
        var name = platformFile.name;
        var rawExt = platformFile.extension ?? '';
        final bytes = platformFile.bytes;
        final size = platformFile.size > 0 ? platformFile.size : (bytes?.length ?? 0);
        final path = platformFile.path;

        if (rawExt.isEmpty && name.contains('.')) {
          rawExt = name.split('.').last.toLowerCase();
        }

        // If extension is missing from filename or platformFile, infer from bytes
        if (rawExt.isEmpty && bytes != null && bytes.isNotEmpty) {
          final detected = detectExtensionFromBytes(bytes);
          if (detected != null) {
            rawExt = detected;
            if (!name.contains('.')) {
              name = '$name.$detected';
            }
          }
        }

        if (rawExt.isEmpty) {
          rawExt = 'pdf';
        }

        final ext = rawExt.startsWith('.') ? rawExt : '.$rawExt';

        debugPrint('[FILE_PICKER] File selected: $name ($size bytes, ext: $ext)');

        return SelectedFileResult(
          fileName: name,
          fileExtension: ext,
          sizeInBytes: size,
          bytes: bytes,
          filePath: path,
        );
      }
      debugPrint('[FILE_PICKER] User canceled file selection.');
      return null;
    } catch (e, st) {
      debugPrint('[FILE_PICKER] Error picking file: $e\n$st');
      return null;
    }
  }

  /// Opens Camera or Image Gallery directly (Mobile & Web compatible)
  static Future<SelectedFileResult?> pickImageFile({bool fromCamera = false}) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
      );
      if (xfile != null) {
        final bytes = await xfile.readAsBytes();
        final name = xfile.name.isNotEmpty ? xfile.name : 'document_scan.jpg';
        final ext = name.contains('.') ? '.${name.split('.').last.toLowerCase()}' : '.jpg';
        debugPrint('[FILE_PICKER] Image picked: $name (${bytes.length} bytes)');
        return SelectedFileResult(
          fileName: name,
          fileExtension: ext,
          sizeInBytes: bytes.length,
          bytes: bytes,
          filePath: xfile.path,
        );
      }
    } catch (e) {
      debugPrint('[FILE_PICKER] Error picking image: $e');
    }
    return null;
  }
}
