import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/klarna_tokens.dart';

/// LocationProminentDisclosureDialog
///
/// Prominent In-App Disclosure for Location Data Collection & Usage.
/// Strictly compliant with Google Play User Data Policy & Prominent Disclosure Requirement.
///
/// Discloses:
/// 1. Exactly what data is collected: Location data (fine & background).
/// 2. How the data is used: Geofence verification for attendance clock-in/out & shift tracking.
/// 3. Background disclosure: "even when the app is closed or not in use".
/// 4. Explicit affirmative user consent (Agree & Continue vs Deny).
class LocationProminentDisclosureDialog extends StatelessWidget {
  const LocationProminentDisclosureDialog({super.key});

  /// Displays the prominent disclosure dialog and returns true if user consented, false otherwise.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Affirmative consent required — no dismiss on tap outside
      builder: (BuildContext ctx) => const LocationProminentDisclosureDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 16,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header Icon & Title ─────────────────────────────────
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.location_solid,
                    size: 32,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "Location Data Usage Disclosure",
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 19,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "How JOY PeopleHR accesses & uses your location data",
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // ── Main Disclosure Body ────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.skyBg.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "JOY PeopleHR accesses and collects location data to:",
                      style: AppTypography.bodyRegular.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const _DisclosureBullet(
                      icon: CupertinoIcons.checkmark_seal_fill,
                      title: "Workplace Geofence Verification",
                      description:
                          "Validate that you are physically present within your company's authorized office, factory, or site boundary during check-in and check-out punches.",
                    ),
                    const SizedBox(height: 10),
                    const _DisclosureBullet(
                      icon: CupertinoIcons.clock_fill,
                      title: "Shift Attendance & Duty Tracking",
                      description:
                          "Accurately calculate on-duty work duration, branch check-ins, and prevent fraudulent or remote attendance logs.",
                    ),
                    const SizedBox(height: 10),
                    const _DisclosureBullet(
                      icon: CupertinoIcons.location_circle_fill,
                      title: "Background Location Collection",
                      highlight: true,
                      description:
                          "JOY PeopleHR collects location data to enable automated geofence attendance verification and continuous shift validation even when the app is closed or not in use.",
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Privacy & Security Guarantee ────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.mintBg.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      CupertinoIcons.shield_fill,
                      size: 16,
                      color: AppColors.mintFg,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Your location data is encrypted in transit and at rest. It is strictly accessible only to your employer's HR and payroll administrators, and is never shared with third parties or advertisers.",
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Explicit Consent Actions ────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop(false);
                      },
                      child: const Text(
                        "Deny",
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop(true);
                      },
                      child: const Text(
                        "Agree & Continue",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
  }
}

class _DisclosureBullet extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool highlight;

  const _DisclosureBullet({
    required this.icon,
    required this.title,
    required this.description,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 15,
            color: highlight ? AppColors.primary : AppColors.primaryAccent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                fontSize: 11.5,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: "$title: ",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: description,
                  style: highlight
                      ? const TextStyle(fontWeight: FontWeight.w600)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
