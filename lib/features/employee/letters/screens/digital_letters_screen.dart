import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/file_download_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import '../../../../widgets/core/status_chip.dart';
import 'digital_letter_viewer_screen.dart';

class DigitalLettersScreen extends StatelessWidget {
  const DigitalLettersScreen({super.key});

  Future<void> _handleDownload(BuildContext context, String title, String? url) async {
    final messenger = ScaffoldMessenger.of(context);
    final cleanName = '${title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.pdf';

    if (url != null && url.startsWith('http')) {
      final downloaded = await FileDownloadService.downloadFromUrl(
        url: url,
        fileName: cleanName,
      );
      if (downloaded) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("✓ '$cleanName' downloaded successfully."),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text("Downloading $cleanName..."),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final letters = controller.letters;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("Digital Letters", style: AppTypography.titleLarge),
          ),
          body: controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : letters.isEmpty
                  ? const EmptyStateWidget(
                      icon: CupertinoIcons.doc_plaintext,
                      title: "No digital letters yet",
                      description: "Official HR offer letters, increment letters, and certificates will appear here.",
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                      itemCount: letters.length,
                      itemBuilder: (context, index) {
                        final item = letters[index];
                        final issuedDateStr = "${item.issueDate.day}/${item.issueDate.month}/${item.issueDate.year}";

                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: AppCard(
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (_) => DigitalLetterViewerScreen(letter: item),
                                ),
                              );
                            },
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: const BoxDecoration(
                                        color: AppColors.skyBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.doc_text_fill,
                                        color: AppColors.skyFg,
                                        size: 20,
                                      ),
                                    ),
                                    AppSpacing.hGapMD,
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.title, style: AppTypography.titleMedium),
                                          const SizedBox(height: 2),
                                          Text(
                                            "Issued $issuedDateStr • ${item.category}",
                                            style: AppTypography.caption,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (item.isSigned)
                                      const StatusChip(
                                        label: "Signed",
                                        type: StatusType.success,
                                        icon: CupertinoIcons.checkmark_seal_fill,
                                      )
                                    else if (item.requiresSignature)
                                      const StatusChip(
                                        label: "Sign Req.",
                                        type: StatusType.warning,
                                      ),
                                  ],
                                ),
                                AppSpacing.gapMD,
                                const Divider(height: 1, color: AppColors.borderSubtle),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // View Button
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          CupertinoPageRoute(
                                            builder: (_) => DigitalLetterViewerScreen(letter: item),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: AppColors.slateBg,
                                          borderRadius: AppRadius.borderPill,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              CupertinoIcons.eye_fill,
                                              size: 14,
                                              color: AppColors.primary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              "View",
                                              style: AppTypography.caption.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Download Button
                                    GestureDetector(
                                      onTap: () => _handleDownload(context, item.title, item.documentUrl),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: AppColors.mintBg,
                                          borderRadius: AppRadius.borderPill,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              CupertinoIcons.arrow_down_circle_fill,
                                              size: 14,
                                              color: AppColors.mintFg,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              "Download",
                                              style: AppTypography.caption.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.mintFg,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }
}
