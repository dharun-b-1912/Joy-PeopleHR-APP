// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Save or trigger browser download on Flutter Web
Future<bool> saveOrDownloadFilePlatform({
  required String fileName,
  required Uint8List bytes,
  String? mimeType,
}) async {
  try {
    final type = mimeType ?? (fileName.endsWith('.pdf') ? 'application/pdf' : 'application/octet-stream');
    final blob = html.Blob([bytes], type);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
    return true;
  } catch (e) {
    return false;
  }
}

/// Trigger browser download directly from a public or signed URL
Future<bool> downloadUrlPlatform({
  required String url,
  required String fileName,
}) async {
  try {
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..setAttribute('target', '_blank')
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    return true;
  } catch (e) {
    return false;
  }
}
