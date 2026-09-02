import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import '../../../../widgets/core/status_chip.dart';
import 'dynamic_service_form_screen.dart';
import 'service_request_detail_screen.dart';

class EmployeeServicesScreen extends StatefulWidget {
  const EmployeeServicesScreen({super.key});

  @override
  State<EmployeeServicesScreen> createState() => _EmployeeServicesScreenState();
}

class _EmployeeServicesScreenState extends State<EmployeeServicesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  IconData _getServiceIcon(String iconStr) {
    switch (iconStr.toLowerCase()) {
      case 'credit-card':
        return CupertinoIcons.creditcard;
      case 'map-pin':
        return CupertinoIcons.location_solid;
      case 'briefcase':
        return CupertinoIcons.briefcase;
      case 'award':
        return CupertinoIcons.rosette;
      case 'file-text':
      default:
        return CupertinoIcons.doc_text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final services = controller.serviceDefinitions;
        final myRequests = controller.serviceRequests;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("Employee HR Services", style: AppTypography.titleLarge),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
              tabs: [
                Tab(text: "Available Services (${services.length})"),
                Tab(text: "My Requests (${myRequests.length})"),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Service Catalog
              controller.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : services.isEmpty
                      ? const EmptyStateWidget(
                          icon: CupertinoIcons.square_grid_2x2,
                          title: "No services available",
                          description: "HR services will appear here once enabled.",
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                          itemCount: services.length,
                          itemBuilder: (context, index) {
                            final def = services[index];

                            return Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.md),
                              child: InkWell(
                                borderRadius: AppRadius.borderLg,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                      builder: (_) => DynamicServiceFormScreen(definition: def),
                                    ),
                                  );
                                },
                                child: AppCard(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppColors.mintBg,
                                          borderRadius: AppRadius.borderMd,
                                        ),
                                        child: Icon(_getServiceIcon(def.icon), color: AppColors.mintFg, size: 24),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(def.name, style: AppTypography.titleMedium),
                                            const SizedBox(height: 2),
                                            Text(def.category, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                                            if (def.description != null) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                def.description!,
                                                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(CupertinoIcons.clock, size: 12, color: AppColors.textMuted),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "SLA: ${def.slaHours}h Target",
                                                  style: AppTypography.caption.copyWith(fontSize: 10),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.textMuted),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

              // Tab 2: My Submitted Requests
              myRequests.isEmpty
                  ? const EmptyStateWidget(
                      icon: CupertinoIcons.doc_checkmark,
                      title: "No requests submitted yet",
                      description: "Choose a service from the catalog to submit your request.",
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                      itemCount: myRequests.length,
                      itemBuilder: (context, index) {
                        final req = myRequests[index];
                        StatusType chipType = StatusType.warning;
                        String statusLabel = "Submitted";

                        if (req.status == 'APPROVED' || req.status == 'COMPLETED') {
                          chipType = StatusType.success;
                          statusLabel = "Completed";
                        } else if (req.status == 'IN_REVIEW' || req.status == 'PROCESSING') {
                          chipType = StatusType.info;
                          statusLabel = "Processing";
                        } else if (req.status == 'ACTION_REQUIRED' || req.status == 'REJECTED') {
                          chipType = StatusType.error;
                          statusLabel = req.status == 'REJECTED' ? "Rejected" : "Action Required";
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: InkWell(
                            borderRadius: AppRadius.borderLg,
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (_) => ServiceRequestDetailScreen(request: req),
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
                                      Expanded(
                                        child: Text(req.serviceName, style: AppTypography.titleMedium),
                                      ),
                                      StatusChip(label: statusLabel, type: chipType),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    req.requestNumber,
                                    style: AppTypography.caption.copyWith(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Submitted: ${req.submittedAt.day}/${req.submittedAt.month}/${req.submittedAt.year}",
                                        style: AppTypography.caption,
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            "View Details",
                                            style: AppTypography.caption.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                          const Icon(CupertinoIcons.chevron_right, size: 12, color: AppColors.primary),
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
            ],
          ),
        );
      },
    );
  }
}
