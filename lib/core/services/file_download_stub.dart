import 'dart:io';
import 'dart:typed_data';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

Future<bool> saveOrDownloadFilePlatform({
  required String fileName,
  required Uint8List bytes,
  String? mimeType,
}) async {
  try {
    final dirPath = await getPublicDownloadsDirectoryPath();
    if (dirPath == null) return false;
    final filePath = '$dirPath/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    // Open the saved file in default device viewer
    try {
      await OpenFilex.open(filePath);
    } catch (_) {}

    return true;
  } catch (e) {
    try {
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$fileName');
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
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  } catch (e) {
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
