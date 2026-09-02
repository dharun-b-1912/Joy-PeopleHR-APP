import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../core/utils/secure_log.dart';
import '../../../../models/hrms_models.dart';
import '../../../../widgets/core/app_button.dart';

class EmergencyContactDialog extends StatefulWidget {
  final EmergencyContactModel? currentContact;

  const EmergencyContactDialog({super.key, this.currentContact});

  static Future<void> show(BuildContext context, {EmergencyContactModel? currentContact}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EmergencyContactDialog(currentContact: currentContact),
    );
  }

  @override
  State<EmergencyContactDialog> createState() => _EmergencyContactDialogState();
}

class _EmergencyContactDialogState extends State<EmergencyContactDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  String _selectedRelationship = 'Family Member';
  bool _isSaving = false;
  String? _errorMessage;

  final List<String> _relationships = [
    'Mother',
    'Father',
    'Spouse',
    'Brother',
    'Sister',
    'Guardian',
    'Family Member',
    'Friend / Colleague',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentContact?.name ?? '');
    _phoneController = TextEditingController(text: widget.currentContact?.phone ?? '');
    if (widget.currentContact?.relationship != null &&
        _relationships.contains(widget.currentContact!.relationship)) {
      _selectedRelationship = widget.currentContact!.relationship;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter a contact name.');
      return;
    }
    if (phone.isEmpty || phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _errorMessage = 'Please enter a valid 10-digit phone number.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final newContact = EmergencyContactModel(
      name: name,
      relationship: _selectedRelationship,
      phone: phone,
    );

    try {
      // 1. Optimistically update local UserService
      UserService.instance.updateEmergencyContact(newContact);

      // 2. Persist to Supabase if connected
      final user = UserService.instance.currentUser;
      final empUuid = user.employeeUuid;
      if (empUuid != null && empUuid.isNotEmpty) {
        try {
          final client = Supabase.instance.client;
          await client.from('employee_emergency_contacts').upsert({
            'employee_id': empUuid,
            'name': name,
            'relationship': _selectedRelationship,
            'primary_phone': phone,
            'is_primary': true,
            'updated_at': DateTime.now().toIso8601String(),
          });
        } catch (dbErr) {
          secureLog('[EmergencyContact] DB update notice: $dbErr');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Emergency contact updated successfully.",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not save contact. Please try again.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
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
                  color: AppColors.mintBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.phone_fill, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.currentContact == null ? "Add Emergency Contact" : "Edit Emergency Contact",
                      style: AppTypography.titleLarge.copyWith(fontSize: 18),
                    ),
                    Text(
                      "HR and emergency services will reach this contact during urgencies.",
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Name Field
          Text("Full Name", style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.slateBg,
              borderRadius: AppRadius.borderMd,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _nameController,
              style: AppTypography.bodyRegular,
              decoration: const InputDecoration(
                hintText: "e.g. Kavitha B",
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Relationship Dropdown
          Text("Relationship", style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.slateBg,
              borderRadius: AppRadius.borderMd,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedRelationship,
                isExpanded: true,
                items: _relationships.map((r) {
                  return DropdownMenuItem(value: r, child: Text(r, style: AppTypography.bodyRegular));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedRelationship = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Phone Field
          Text("Contact Number", style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.slateBg,
              borderRadius: AppRadius.borderMd,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: AppTypography.bodyRegular,
              decoration: const InputDecoration(
                hintText: "e.g. +91 98765 43210",
                border: InputBorder.none,
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(CupertinoIcons.exclamationmark_circle, size: 14, color: AppColors.statusError),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.statusError)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: "Cancel",
                  variant: AppButtonVariant.secondaryPill,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              AppSpacing.hGapMD,
              Expanded(
                child: AppButton(
                  label: _isSaving ? "Saving..." : "Save Contact",
                  variant: AppButtonVariant.primaryPill,
                  onPressed: _isSaving ? null : _handleSave,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
