import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import '../../../../widgets/core/status_chip.dart';
import 'communication_detail_screen.dart';

class CommunicationScreen extends StatefulWidget {
  const CommunicationScreen({super.key});

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends State<CommunicationScreen> {
  @override
  void initState() {
    super.initState();
    MoreModulesController.instance.loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final communications = controller.communicationsList;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon:
                  const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title:
                Text("Company Announcements", style: AppTypography.titleLarge),
          ),
          body: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: Colors.white,
            onRefresh: () => controller.loadAllData(),
            child: controller.isLoading && communications.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : communications.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics()),
                        children: const [
                          SizedBox(height: 80),
                          EmptyStateWidget(
                            icon: CupertinoIcons.speaker_2,
                            title: "No announcements yet",
                            description:
                                "Company news, policy updates, and HR broadcasts will appear here.",
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics()),
                        padding:
                            const EdgeInsets.all(AppSpacing.screenHorizontal),
                        itemCount: communications.length,
                        itemBuilder: (context, index) {
                          final item = communications[index];

                          return Container(
                            margin:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: InkWell(
                              borderRadius: AppRadius.borderLg,
                              onTap: () {
                                MoreModulesController.instance.markCommunicationAsRead(item.id);
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) => CommunicationDetailScreen(
                                        communication: item),
                                  ),
                                );
                              },
                              child: AppCard(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.lavenderBg,
                                            borderRadius: AppRadius.borderSm,
                                          ),
                                          child: Text(
                                            item.communicationType,
                                            style:
                                                AppTypography.caption.copyWith(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.lavenderFg,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (item.priority == 'URGENT')
                                          const StatusChip(
                                              label: "URGENT",
                                              type: StatusType.error)
                                        else if (item.priority == 'IMPORTANT')
                                          const StatusChip(
                                              label: "IMPORTANT",
                                              type: StatusType.warning),
                                        const Spacer(),
                                        if (item.requiresAcknowledgement &&
                                            item.acknowledgedAt == null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.alertBg,
                                              borderRadius: AppRadius.borderSm,
                                            ),
                                            child: Text(
                                              "Ack Required",
                                              style: AppTypography.caption
                                                  .copyWith(
                                                      fontSize: 10,
                                                      color: AppColors.alertFg,
                                                      fontWeight:
                                                          FontWeight.bold),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(item.title,
                                        style: AppTypography.titleMedium),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.body,
                                      style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textSecondary),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "By ${item.authorName} • ${item.publishAt.day}/${item.publishAt.month}/${item.publishAt.year}",
                                          style: AppTypography.caption,
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              "Read More",
                                              style: AppTypography.caption
                                                  .copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                            const Icon(
                                                CupertinoIcons.chevron_right,
                                                size: 12,
                                                color: AppColors.primary),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        );
      },
    );
  }
}
