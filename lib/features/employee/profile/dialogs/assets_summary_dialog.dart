import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../core/utils/secure_log.dart';
import '../../../../widgets/core/app_button.dart';
import '../../../../widgets/core/status_chip.dart';

class AssetsSummaryDialog extends StatefulWidget {
  const AssetsSummaryDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AssetsSummaryDialog(),
    );
  }

  @override
  State<AssetsSummaryDialog> createState() => _AssetsSummaryDialogState();
}

class _AssetsSummaryDialogState extends State<AssetsSummaryDialog> {
  List<Map<String, dynamic>> _assets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRealAssets();
  }

  Future<void> _fetchRealAssets() async {
    final user = UserService.instance.currentUser;
    final empUuid = user.employeeUuid;

    // Check if user model already has populated assigned assets
    if (user.assignedAssets.isNotEmpty) {
      if (mounted) {
        setState(() {
          _assets = user.assignedAssets.map((a) => {
            'name': a.assetName,
            'id': a.assetId,
            'category': a.category,
            'status': a.status,
            'date': a.assignedDate,
          }).toList();
          _isLoading = false;
        });
      }
      return;
    }

    if (empUuid == null || empUuid.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('assets')
          .select()
          .or('employee_id.eq.$empUuid,custodian_id.eq.$empUuid');

      if (mounted) {
        setState(() {
          _assets = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      secureLog('[AssetsDialog] Error fetching assets: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.lavenderBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.cube_box_fill, color: AppColors.lavenderFg, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Assigned Equipment & Assets",
                      style: AppTypography.titleLarge.copyWith(fontSize: 18),
                    ),
                    Text(
                      "Hardware, tools, uniform & access badges assigned to you.",
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.lavenderFg),
              ),
            )
          else if (_assets.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.slateBg,
                borderRadius: AppRadius.borderMd,
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                children: [
                  const Icon(CupertinoIcons.cube_box, size: 28, color: AppColors.textMuted),
                  const SizedBox(height: 8),
                  Text(
                    "No assets assigned",
                    style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "No company hardware, tools, or physical equipment currently assigned to you.",
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._assets.map((a) {
              final name = a['name'] ?? a['asset_name'] ?? a['asset_code'] ?? 'Company Asset';
              final id = a['id'] ?? a['asset_code'] ?? '';
              final category = a['category'] ?? a['asset_type_code'] ?? 'General';
              final status = (a['status'] ?? 'ASSIGNED').toString().toUpperCase();

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.slateBg,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.lavenderBg,
                        borderRadius: AppRadius.borderSquircle,
                      ),
                      child: const Icon(CupertinoIcons.device_laptop, color: AppColors.lavenderFg, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.toString(),
                            style: AppTypography.bodyRegular.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            id.isNotEmpty ? "ID: $id • $category" : category.toString(),
                            style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(
                      label: status,
                      type: StatusType.success,
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 16),
          AppButton(
            label: "Close",
            variant: AppButtonVariant.secondaryPill,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
