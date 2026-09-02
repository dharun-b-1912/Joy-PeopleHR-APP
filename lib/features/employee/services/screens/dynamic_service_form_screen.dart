import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/controllers/employee_controller.dart';
import '../../../../core/services/document_upload_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/employee_relations_models.dart';

class DynamicServiceFormScreen extends StatefulWidget {
  final ServiceDefinitionModel definition;

  const DynamicServiceFormScreen({super.key, required this.definition});

  @override
  State<DynamicServiceFormScreen> createState() => _DynamicServiceFormScreenState();
}

class _DynamicServiceFormScreenState extends State<DynamicServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _formData = {};
  final Map<String, Uint8List> _attachmentBytes = {};
  final Map<String, String> _attachmentFileNames = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Initialize default values for form fields
    for (final field in widget.definition.formSchema) {
      if (field.type == ServiceFieldType.checkbox) {
        _formData[field.id] = false;
      } else if (field.type == ServiceFieldType.dropdown || field.type == ServiceFieldType.radio) {
        if (field.options.isNotEmpty) {
          _formData[field.id] = field.options.first;
        }
      }
    }
  }

  Future<void> _pickAttachment(String fieldId) async {
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
            _attachmentBytes[fieldId] = file.bytes!;
            _attachmentFileNames[fieldId] = file.name;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    // Check required attachments
    for (final field in widget.definition.formSchema) {
      if (field.type == ServiceFieldType.attachment && field.required) {
        if (!_attachmentBytes.containsKey(field.id)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Please attach ${field.label}"),
              backgroundColor: AppColors.statusError,
            ),
          );
          return;
        }
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final user = UserService.instance.currentUser;
      final tenantId = user.companyId.isNotEmpty
          ? user.companyId
          : (user.organizationId?.isNotEmpty == true ? user.organizationId! : '');
      final empId = user.employeeUuid ?? user.employeeId;

      // Upload all attachments to Supabase Storage
      final List<Map<String, dynamic>> uploadedAttachments = [];
      for (final entry in _attachmentBytes.entries) {
        final fieldId = entry.key;
        final bytes = entry.value;
        final filename = _attachmentFileNames[fieldId] ?? 'attachment.pdf';

        final url = await DocumentUploadService.instance.uploadDocument(
          tenantId: tenantId,
          employeeId: empId,
          bytes: bytes,
          fileName: filename,
        );

        if (url != null) {
          uploadedAttachments.add({
            'field_id': fieldId,
            'name': filename,
            'url': url,
            'size': bytes.length,
          });
          _formData[fieldId] = url;
        }
      }

      final success = await MoreModulesController.instance.submitServiceRequest(
        definition: widget.definition,
        formData: _formData,
        attachments: uploadedAttachments,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        if (success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✓ Service Request Submitted Successfully!"),
              backgroundColor: AppColors.primary,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to submit request. Please try again."),
              backgroundColor: AppColors.statusError,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildFieldWidget(ServiceFormFieldModel field) {
    switch (field.type) {
      case ServiceFieldType.text:
      case ServiceFieldType.amount:
      case ServiceFieldType.number:
        return TextFormField(
          decoration: InputDecoration(
            hintText: field.placeholder ?? "Enter ${field.label}",
            filled: true,
            fillColor: AppColors.slateBg,
            border: OutlineInputBorder(borderRadius: AppRadius.borderMd, borderSide: BorderSide.none),
          ),
          keyboardType: field.type == ServiceFieldType.number || field.type == ServiceFieldType.amount
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          validator: (val) {
            if (field.required && (val == null || val.trim().isEmpty)) {
              return "Please enter ${field.label}";
            }
            return null;
          },
          onSaved: (val) => _formData[field.id] = val?.trim() ?? '',
        );

      case ServiceFieldType.textarea:
        return TextFormField(
          maxLines: 4,
          decoration: InputDecoration(
            hintText: field.placeholder ?? "Enter details...",
            filled: true,
            fillColor: AppColors.slateBg,
            border: OutlineInputBorder(borderRadius: AppRadius.borderMd, borderSide: BorderSide.none),
          ),
          validator: (val) {
            if (field.required && (val == null || val.trim().isEmpty)) {
              return "Please enter ${field.label}";
            }
            return null;
          },
          onSaved: (val) => _formData[field.id] = val?.trim() ?? '',
        );

      case ServiceFieldType.dropdown:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.slateBg,
            borderRadius: AppRadius.borderMd,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _formData[field.id] ?? (field.options.isNotEmpty ? field.options.first : null),
              isExpanded: true,
              items: field.options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _formData[field.id] = val);
              },
            ),
          ),
        );

      case ServiceFieldType.radio:
        return Column(
          children: field.options.map((opt) {
            final isSelected = _formData[field.id] == opt;
            return InkWell(
              onTap: () => setState(() => _formData[field.id] = opt),
              borderRadius: AppRadius.borderMd,
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.mintBg.withValues(alpha: 0.4) : AppColors.slateBg,
                  borderRadius: AppRadius.borderMd,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                      color: isSelected ? AppColors.primary : AppColors.textMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        opt,
                        style: AppTypography.bodyRegular.copyWith(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );

      case ServiceFieldType.checkbox:
        return CheckboxListTile(
          title: Text(field.label, style: AppTypography.bodyRegular),
          subtitle: field.helpText != null ? Text(field.helpText!, style: AppTypography.caption) : null,
          value: _formData[field.id] == true,
          activeColor: AppColors.primary,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (val) => setState(() => _formData[field.id] = val ?? false),
        );

      case ServiceFieldType.date:
        final selectedDate = _formData[field.id] as DateTime?;
        return InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) {
              setState(() => _formData[field.id] = picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.slateBg,
              borderRadius: AppRadius.borderMd,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedDate != null
                      ? "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}"
                      : (field.placeholder ?? "Select Date"),
                  style: AppTypography.bodyRegular.copyWith(
                    color: selectedDate != null ? AppColors.textPrimary : AppColors.textMuted,
                  ),
                ),
                const Icon(CupertinoIcons.calendar, size: 18, color: AppColors.primary),
              ],
            ),
          ),
        );

      case ServiceFieldType.attachment:
        final hasFile = _attachmentFileNames.containsKey(field.id);
        return InkWell(
          onTap: () => _pickAttachment(field.id),
          borderRadius: AppRadius.borderMd,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: hasFile ? AppColors.primary : AppColors.borderSubtle),
              borderRadius: AppRadius.borderMd,
              color: hasFile ? AppColors.mintBg.withValues(alpha: 0.3) : Colors.white,
            ),
            child: Row(
              children: [
                Icon(
                  hasFile ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.cloud_upload,
                  size: 20,
                  color: hasFile ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasFile ? _attachmentFileNames[field.id]! : (field.placeholder ?? "Upload Document / Photo (PDF/Image)"),
                    style: AppTypography.caption.copyWith(
                      fontWeight: hasFile ? FontWeight.bold : FontWeight.normal,
                      color: hasFile ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.definition;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(def.name, style: AppTypography.titleLarge),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (def.description != null && def.description!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.mintBg,
                    borderRadius: AppRadius.borderMd,
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.info_circle_fill, size: 18, color: AppColors.mintFg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          def.description!,
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Render Dynamic Form Fields
              ...def.formSchema.map((field) {
                if (field.type == ServiceFieldType.checkbox) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildFieldWidget(field),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(field.label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                          if (field.required)
                            const Text(" *", style: TextStyle(color: AppColors.statusError, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (field.helpText != null) ...[
                        const SizedBox(height: 2),
                        Text(field.helpText!, style: AppTypography.caption.copyWith(fontSize: 10, color: AppColors.textMuted)),
                      ],
                      const SizedBox(height: 6),
                      _buildFieldWidget(field),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          "Submit Service Request",
                          style: AppTypography.bodyLarge.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
