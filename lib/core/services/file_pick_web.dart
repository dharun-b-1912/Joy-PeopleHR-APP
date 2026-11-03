// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';
import 'file_pick_models.dart';

/// Direct HTML5 File Upload Picker for Flutter Web
Future<SelectedFileResult?> pickHtmlWebFile({String? accept}) async {
  final completer = Completer<SelectedFileResult?>();
  final uploadInput = html.FileUploadInputElement();
  uploadInput.accept = accept ?? '.pdf,.png,.jpg,.jpeg,.webp,.doc,.docx';
  uploadInput.multiple = false;
  uploadInput.click();

  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files != null && files.isNotEmpty) {
      final file = files.first;
      final reader = html.FileReader();

      reader.onLoadEnd.listen((e) {
        final result = reader.result;
        Uint8List? bytes;
        if (result is Uint8List) {
          bytes = result;
        } else if (result is ByteBuffer) {
          bytes = Uint8List.view(result);
        } else if (result is List<int>) {
          bytes = Uint8List.fromList(result);
        }

        if (bytes != null && bytes.isNotEmpty) {
          final name = file.name;
          final ext = name.contains('.') ? '.${name.split('.').last.toLowerCase()}' : '.pdf';
          if (!completer.isCompleted) {
            completer.complete(SelectedFileResult(
              fileName: name,
              fileExtension: ext,
              sizeInBytes: file.size,
              bytes: bytes,
            ));
          }
        } else {
          if (!completer.isCompleted) completer.complete(null);
        }
      });

      reader.onError.listen((e) {
        if (!completer.isCompleted) completer.complete(null);
      });

      reader.readAsArrayBuffer(file);
    } else {
      if (!completer.isCompleted) completer.complete(null);
    }
  });

  return completer.future;
}
