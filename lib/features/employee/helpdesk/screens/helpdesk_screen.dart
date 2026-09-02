import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_relations_models.dart';
import '../../../../widgets/core/app_card.dart';
import '../../../../widgets/core/empty_state_widget.dart';
import '../../../../widgets/core/status_chip.dart';
import '../../../../widgets/workforce_request_modal.dart';
import 'ticket_detail_screen.dart';

class HelpdeskScreen extends StatefulWidget {
  const HelpdeskScreen({super.key});

  @override
  State<HelpdeskScreen> createState() => _HelpdeskScreenState();
}

class _HelpdeskScreenState extends State<HelpdeskScreen> {
  int _selectedTabIndex = 0;
  final List<String> _tabs = ["All", "Open", "In Progress", "Resolved"];

  void _showNewTicketModal(BuildContext context) {
    showWorkForceRequestModal(
      context: context,
      builder: (ctx) => const _NewTicketDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MoreModulesController.instance,
      builder: (context, _) {
        final controller = MoreModulesController.instance;
        final allTickets = controller.helpdeskTickets;

        final filteredTickets = allTickets.where((t) {
          if (_selectedTabIndex == 1) {
            return t.status == HelpdeskStatus.open || t.status == HelpdeskStatus.assigned;
          } else if (_selectedTabIndex == 2) {
            return t.status == HelpdeskStatus.inProgress ||
                t.status == HelpdeskStatus.waitingForEmployee ||
                t.status == HelpdeskStatus.waitingForHr;
          } else if (_selectedTabIndex == 3) {
            return t.status == HelpdeskStatus.resolved || t.status == HelpdeskStatus.closed;
          }
          return true;
        }).toList();

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("HR Helpdesk & Support", style: AppTypography.titleLarge),
            actions: [
              IconButton(
                icon: const Icon(CupertinoIcons.add, color: AppColors.primary),
                onPressed: () => _showNewTicketModal(context),
              ),
            ],
          ),
          body: Column(
            children: [
              // Filter Chips
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _tabs.length,
                  itemBuilder: (context, index) {
                    final isSelected = _selectedTabIndex == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = index),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.slateBg,
                          borderRadius: AppRadius.borderPill,
                        ),
                        child: Text(
                          _tabs[index],
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Tickets List
              Expanded(
                child: controller.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredTickets.isEmpty
                        ? EmptyStateWidget(
                            icon: CupertinoIcons.question_circle_fill,
                            title: "No support tickets",
                            description: "Raise an issue with HR for attendance, payroll, leaves, or benefits.",
                            actionLabel: "Raise Ticket",
                            onAction: () => _showNewTicketModal(context),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                            itemCount: filteredTickets.length,
                            itemBuilder: (context, index) {
                              final item = filteredTickets[index];
                              StatusType chipType = StatusType.warning;
                              String statusLabel = "Open";

                              if (item.status == HelpdeskStatus.inProgress || item.status == HelpdeskStatus.assigned) {
                                chipType = StatusType.info;
                                statusLabel = "In Progress";
                              } else if (item.status == HelpdeskStatus.resolved || item.status == HelpdeskStatus.closed) {
                                chipType = StatusType.success;
                                statusLabel = "Resolved";
                              } else if (item.status == HelpdeskStatus.escalated) {
                                chipType = StatusType.error;
                                statusLabel = "Escalated";
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                                child: InkWell(
                                  borderRadius: AppRadius.borderLg,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      CupertinoPageRoute(
                                        builder: (_) => TicketDetailScreen(ticket: item),
                                      ),
                                    );
                                  },
                                  child: AppCard(
                                    padding: const EdgeInsets.all(AppSpacing.md),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.subject,
                                                style: AppTypography.titleMedium,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            StatusChip(label: statusLabel, type: chipType),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              item.ticketNumber,
                                              style: AppTypography.caption.copyWith(
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.slateBg,
                                                borderRadius: AppRadius.borderSm,
                                              ),
                                              child: Text(
                                                item.category,
                                                style: AppTypography.caption.copyWith(fontSize: 10),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          item.description,
                                          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(CupertinoIcons.clock, size: 12, color: AppColors.textMuted),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year}",
                                                  style: AppTypography.caption,
                                                ),
                                              ],
                                            ),
                                            if (item.status == HelpdeskStatus.open || item.status == HelpdeskStatus.assigned)
                                              InkWell(
                                                onTap: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      title: const Text("Withdraw Ticket?"),
                                                      content: const Text("Are you sure you want to withdraw and completely remove this ticket?"),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(ctx, false),
                                                          child: const Text("No"),
                                                        ),
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(ctx, true),
                                                          style: TextButton.styleFrom(foregroundColor: AppColors.roseFg),
                                                          child: const Text("Yes, Withdraw"),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm == true) {
                                                    await MoreModulesController.instance.withdrawHelpdeskTicket(item.id.isNotEmpty ? item.id : item.ticketNumber);
                                                  }
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  child: Text(
                                                    "Withdraw",
                                                    style: AppTypography.caption.copyWith(
                                                      color: AppColors.roseFg,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
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
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showNewTicketModal(context),
            backgroundColor: AppColors.primary,
            icon: const Icon(CupertinoIcons.add, color: Colors.white),
            label: Text("Raise Ticket", style: AppTypography.bodyLarge.copyWith(color: Colors.white)),
          ),
        );
      },
    );
  }
}

class _NewTicketDialog extends StatefulWidget {
  const _NewTicketDialog();

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  final _subjectController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCategory = "Attendance";
  final TicketPriority _selectedPriority = TicketPriority.medium;
  String? _errorText;

  Uint8List? _attachmentBytes;
  String? _attachmentFileName;
  bool _isSubmitting = false;

  final List<String> _categories = const [
    "Attendance",
    "Leave",
    "Payroll",
    "Payslip",
    "Documents",
    "Profile",
    "Benefits",
    "Workplace",
    "General HR",
    "Other",
  ];

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'webp'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _attachmentBytes = file.bytes;
            _attachmentFileName = file.name;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    final subject = _subjectController.text.trim();
    final desc = _descController.text.trim();

    if (subject.isEmpty) {
      setState(() => _errorText = "Please enter a subject");
      return;
    }
    if (desc.isEmpty) {
      setState(() => _errorText = "Please describe your question or issue");
      return;
    }

    setState(() => _isSubmitting = true);

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final success = await MoreModulesController.instance.submitHelpdeskTicket(
      category: _selectedCategory,
      subject: subject,
      description: desc,
      priority: _selectedPriority,
      attachmentBytes: _attachmentBytes,
      attachmentFileName: _attachmentFileName,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            success ? "✓ Ticket submitted to HR Support Team" : "Failed to submit ticket. Please try again.",
          ),
          backgroundColor: success ? AppColors.primary : AppColors.statusError,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WorkForceOSRequestModal(
      title: "Raise Support Ticket",
      subtitle: "Submit an inquiry or issue for HR assistance.",
      primaryButtonLabel: _isSubmitting ? "Submitting..." : "Submit Ticket",
      onPrimaryPressed: _handleSubmit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Category", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.slateBg,
              borderRadius: AppRadius.borderMd,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCategory,
                isExpanded: true,
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text("Subject", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _subjectController,
            decoration: InputDecoration(
              hintText: "Brief summary of issue (e.g. Missing punch on 12-Aug)",
              filled: true,
              fillColor: AppColors.slateBg,
              border: OutlineInputBorder(borderRadius: AppRadius.borderMd, borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          Text("Description", style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: "Provide all relevant details for HR review...",
              filled: true,
              fillColor: AppColors.slateBg,
              border: OutlineInputBorder(borderRadius: AppRadius.borderMd, borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          // Attachment
          InkWell(
            onTap: _pickAttachment,
            borderRadius: AppRadius.borderMd,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borderSubtle),
                borderRadius: AppRadius.borderMd,
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.paperclip, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _attachmentFileName ?? "Attach supporting screenshot or file (Optional)",
                      style: AppTypography.caption.copyWith(
                        fontWeight: _attachmentFileName != null ? FontWeight.bold : FontWeight.normal,
                        color: _attachmentFileName != null ? AppColors.textPrimary : AppColors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(_errorText!, style: AppTypography.caption.copyWith(color: AppColors.statusError)),
          ],
        ],
      ),
    );
  }
}
