/// Representation of a file selected by the employee
class SelectedFileResult {
  final String fileName;
  final String fileExtension;
  final int sizeInBytes;
  final List<int>? bytes;
  final String? filePath;

  const SelectedFileResult({
    required this.fileName,
    required this.fileExtension,
    required this.sizeInBytes,
    this.bytes,
    this.filePath,
  });

  String get formattedSize {
    if (sizeInBytes < 1024) {
      return "$sizeInBytes B";
    } else if (sizeInBytes < 1024 * 1024) {
      final kb = (sizeInBytes / 1024).toStringAsFixed(1);
      return "$kb KB";
    } else {
      final mb = (sizeInBytes / (1024 * 1024)).toStringAsFixed(1);
      return "$mb MB";
    }
  }

  bool get isPdf =>
      fileExtension.toLowerCase() == ".pdf" || fileExtension.toLowerCase() == "pdf";

  bool get isImage => [
        "jpg",
        "jpeg",
        "png",
        "webp",
        "jfif",
      ].contains(fileExtension.toLowerCase().replaceAll('.', ''));
}
