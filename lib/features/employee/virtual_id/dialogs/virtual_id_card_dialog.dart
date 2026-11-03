import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/hrms_models.dart';
import '../widgets/virtual_id_card.dart';

void showVirtualIdCardDialog(BuildContext context, UserModel user) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (context) => VirtualIdCardDialog(user: user),
  );
}

class VirtualIdCardDialog extends StatelessWidget {
  final UserModel user;

  const VirtualIdCardDialog({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      elevation: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Right Close Button
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  button: true,
                  label: "Close virtual ID card",
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        CupertinoIcons.xmark,
                        color: AppColors.pillBlack,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),

              // Virtual ID Card Content (Scrollable if viewport height is tiny)
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: VirtualIdCard(user: user),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
