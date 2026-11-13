import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class OtpPinField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  const OtpPinField({
    super.key,
    required this.controller,
    this.focusNode,
    this.enabled = true,
    this.hasError = false,
    this.onChanged,
    this.onCompleted,
  });

  @override
  State<OtpPinField> createState() => _OtpPinFieldState();
}

class _OtpPinFieldState extends State<OtpPinField> {

  @override
  Widget build(BuildContext context) {
    final baseTheme = PinTheme(
      width: 48,
      height: 54,
      textStyle: AppTypography.titleLarge.copyWith(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );

    final focusedTheme = baseTheme.copyDecorationWith(
      border: Border.all(color: AppColors.textPrimary, width: 1.8),
      color: AppColors.surfaceWhite,
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.14),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );

    final submittedTheme = baseTheme.copyDecorationWith(
      color: AppColors.surfaceWhite,
      border: Border.all(
        color: AppColors.primary,
        width: 1.6,
      ),
    );

    final errorTheme = baseTheme.copyDecorationWith(
      color: Colors.red.shade50,
      border: Border.all(color: AppColors.statusError, width: 1.8),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite ? constraints.maxWidth : 340.0;
        final boxWidth = ((available - 40) / 6).clamp(38.0, 50.0);
        final sizedDefault = baseTheme.copyWith(width: boxWidth);
        final sizedFocused = focusedTheme.copyWith(width: boxWidth);
        final sizedSubmitted = submittedTheme.copyWith(width: boxWidth);
        final sizedError = errorTheme.copyWith(width: boxWidth);

        return Material(
          color: Colors.transparent,
          child: Pinput(
            key: const ValueKey('otp_pinput_field'),
            length: 6,
            controller: widget.controller,
            focusNode: widget.focusNode,
            enabled: widget.enabled,
            autofocus: true,
            forceErrorState: widget.hasError,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            hapticFeedbackType: HapticFeedbackType.lightImpact,
            pinAnimationType: PinAnimationType.scale,
            animationDuration: const Duration(milliseconds: 160),
            animationCurve: Curves.easeOutBack,
            defaultPinTheme: sizedDefault,
            focusedPinTheme: sizedFocused,
            submittedPinTheme: sizedSubmitted,
            errorPinTheme: sizedError,
            separatorBuilder: (_) => const SizedBox(width: 6),
            cursor: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  width: 18,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
            onChanged: (val) => widget.onChanged?.call(val),
            onCompleted: (pin) {
              if (!kIsWeb) {
                HapticFeedback.mediumImpact();
              }
              widget.onCompleted?.call(pin);
            },
            onSubmitted: (pin) => widget.onCompleted?.call(pin),
          ),
        );
      },
    );
  }
}

