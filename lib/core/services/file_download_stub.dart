import 'dart:io';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

Future<bool> saveOrDownloadFilePlatform({
  required String fileName,
  required Uint8List bytes,
  String? mimeType,
}) async {
  try {
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return true;
  } catch (e) {
    return false;
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
