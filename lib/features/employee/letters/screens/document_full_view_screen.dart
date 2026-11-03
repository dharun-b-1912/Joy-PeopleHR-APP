import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfx/pdfx.dart';
import '../../../../core/services/document_upload_service.dart';
import '../../../../core/services/file_download_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../core/utils/secure_log.dart';
import '../../../../core/utils/validators.dart';
import '../../../../widgets/core/app_button.dart';

class DocumentFullViewScreen extends StatefulWidget {
  final String? documentId;
  final String title;
  final String? documentUrl;
  final Uint8List? fileBytes;
  final String? mimeType;
  final String? fileName;

  const DocumentFullViewScreen({
    super.key,
    this.documentId,
    required this.title,
    this.documentUrl,
    this.fileBytes,
    this.mimeType,
    this.fileName,
  });

  @override
  State<DocumentFullViewScreen> createState() => _DocumentFullViewScreenState();
}

class _DocumentFullViewScreenState extends State<DocumentFullViewScreen> {
  Uint8List? _bytes;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isPdf = false;
  bool _isImage = false;
  PdfController? _pdfController;
  int _actualCurrentPage = 1;
  int _actualTotalPages = 1;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadDocumentBytes();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _loadDocumentBytes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Uint8List? loaded = widget.fileBytes;

      if ((loaded == null || loaded.isEmpty) && widget.documentUrl != null && widget.documentUrl!.isNotEmpty) {
        final rawUrl = widget.documentUrl!;
        if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
          loaded = await DocumentUploadService.instance.downloadFileBytes(rawUrl);
          if (loaded == null || loaded.isEmpty) {
            final signed = await DocumentUploadService.instance.getSignedUrl(rawUrl);
            if (signed != null && signed.startsWith('http')) {
              loaded = await _fetchBytesFromHttp(signed);
            }
          }
        } else {
          loaded = await _fetchBytesFromHttp(rawUrl);
        }
      }

      if (loaded == null || loaded.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "The document could not be loaded. Check your connection and retry.";
          });
        }
        return;
      }

      // Inspect byte signatures
      final isPdfDoc = loaded.length >= 4 &&
          loaded[0] == 0x25 &&
          loaded[1] == 0x50 &&
          loaded[2] == 0x44 &&
          loaded[3] == 0x46;

      final isJpegDoc = loaded.length >= 3 &&
          loaded[0] == 0xFF &&
          loaded[1] == 0xD8 &&
          loaded[2] == 0xFF;

      final isPngDoc = loaded.length >= 4 &&
          loaded[0] == 0x89 &&
          loaded[1] == 0x50 &&
          loaded[2] == 0x4E &&
          loaded[3] == 0x47;

      final isWebpDoc = loaded.length > 12 &&
          loaded[0] == 0x52 &&
          loaded[1] == 0x49 &&
          loaded[2] == 0x46 &&
          loaded[3] == 0x46 &&
          loaded[8] == 0x57 &&
          loaded[9] == 0x45 &&
          loaded[10] == 0x42 &&
          loaded[11] == 0x50;

      final isImg = isJpegDoc || isPngDoc || isWebpDoc;

      PdfController? controller;
      if (isPdfDoc) {
        try {
          controller = PdfController(
            document: PdfDocument.openData(loaded),
          );
        } catch (e) {
          secureLog('[FullView] DOCUMENT_VIEW_FAILED: Error opening PDF data: $e');
        }
      }

      if (mounted) {
        setState(() {
          _bytes = loaded;
          _isPdf = isPdfDoc && controller != null;
          _isImage = isImg;
          _pdfController = controller;
          _isLoading = false;
          if (!_isPdf && !_isImage) {
            _errorMessage = "Preview is not available for this file type. You can download the document to open it.";
          }
        });
      }
    } catch (e) {
      secureLog('[FullView] DOCUMENT_VIEW_FAILED: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "The document could not be opened.";
        });
      }
    }
  }

  Future<Uint8List?> _fetchBytesFromHttp(String url) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        secureLog('[FullView] DOCUMENT_DOWNLOAD_FAILED: HTTP status ${response.statusCode}');
        return null;
      }
      final bytesBuilder = BytesBuilder();
      await for (final chunk in response) {
        bytesBuilder.add(chunk);
      }
      return bytesBuilder.toBytes();
    } catch (e) {
      secureLog('[FullView] HTTP fetch error: $e');
      return null;
    }
  }

  String _resolveCleanFileName() {
    String name = widget.fileName ?? widget.title;
    if (name.trim().isEmpty) name = 'Official_Document';
    name = Validators.sanitizeFileName(name);

    if (_isPdf && !name.toLowerCase().endsWith('.pdf')) {
      name = '$name.pdf';
    } else if (_isImage && !name.toLowerCase().endsWith('.jpg') && !name.toLowerCase().endsWith('.png')) {
      name = '$name.jpg';
    }
    return name;
  }

  Future<void> _handleDownload() async {
    if (_bytes == null || _bytes!.isEmpty) return;
    setState(() => _isDownloading = true);
    final messenger = ScaffoldMessenger.of(context);
    final fileName = _resolveCleanFileName();

    try {
      final success = await FileDownloadService.downloadBytes(
        fileName: fileName,
        bytes: _bytes!,
        mimeType: _isPdf ? 'application/pdf' : (_isImage ? 'image/jpeg' : 'application/octet-stream'),
      );

      if (success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("✓ '$fileName' saved to Downloads"),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: "OPEN",
              textColor: Colors.white,
              onPressed: () {
                FileDownloadService.openDownloadedFile(fileName);
              },
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Unable to save file to downloads."),
            backgroundColor: AppColors.statusError,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Download error: $e"),
          backgroundColor: AppColors.statusError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _handleShareOrOpenExternal() async {
    if (_bytes == null || _bytes!.isEmpty) return;
    final fileName = _resolveCleanFileName();
    try {
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(_bytes!, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      secureLog('[FullView] DOCUMENT_VIEW_FAILED: Error opening external viewer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_bytes != null) ...[
            IconButton(
              tooltip: "Open External",
              icon: const Icon(CupertinoIcons.share, color: Colors.white, size: 20),
              onPressed: _handleShareOrOpenExternal,
            ),
            IconButton(
              tooltip: "Download",
              icon: _isDownloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.arrow_down_circle, color: Colors.white, size: 22),
              onPressed: _isDownloading ? null : _handleDownload,
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
      bottomNavigationBar: (_isPdf && _pdfController != null && _actualTotalPages > 1)
          ? Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_left, color: Colors.white),
                    onPressed: _actualCurrentPage > 1
                        ? () => _pdfController?.previousPage(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                            )
                        : null,
                  ),
                  Text(
                    "Page $_actualCurrentPage of $_actualTotalPages",
                    style: AppTypography.caption.copyWith(color: Colors.white70),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_right, color: Colors.white),
                    onPressed: _actualCurrentPage < _actualTotalPages
                        ? () => _pdfController?.nextPage(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                            )
                        : null,
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              "Loading document...",
              style: AppTypography.caption.copyWith(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 48, color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                "Document could not be opened",
                style: AppTypography.titleMedium.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: AppTypography.caption.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppButton(
                    label: "Retry",
                    icon: CupertinoIcons.refresh,
                    variant: AppButtonVariant.primaryPill,
                    onPressed: _loadDocumentBytes,
                  ),
                  if (_bytes != null) ...[
                    const SizedBox(width: 12),
                    AppButton(
                      label: "Download",
                      icon: CupertinoIcons.arrow_down_circle,
                      variant: AppButtonVariant.secondaryPill,
                      onPressed: _handleDownload,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_isPdf && _pdfController != null) {
      return PdfView(
        controller: _pdfController!,
        scrollDirection: Axis.vertical,
        onDocumentLoaded: (doc) {
          if (mounted) {
            setState(() {
              _actualTotalPages = doc.pagesCount;
            });
          }
        },
        onPageChanged: (page) {
          if (mounted) {
            setState(() {
              _actualCurrentPage = page;
            });
          }
        },
      );
    }

    if (_isImage && _bytes != null) {
      return PhotoView(
        imageProvider: MemoryImage(_bytes!),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4.0,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      );
    }

    return Center(
      child: Text(
        "Unsupported document preview",
        style: AppTypography.caption.copyWith(color: Colors.white70),
      ),
    );
  }
}
