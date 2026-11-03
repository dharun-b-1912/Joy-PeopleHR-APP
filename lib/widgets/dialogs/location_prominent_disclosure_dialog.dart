import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/klarna_tokens.dart';

/// LocationProminentDisclosureDialog
///
/// Fully compliant with Google Play Prominent Disclosure & Consent Requirement
/// for Location and Background Location access.
///
/// Google Play Policy Checklist:
/// 1. App-specific naming: "JOY PeopleHR collects location data..."
/// 2. Mandatory wording: "...even when the app is closed or not in use"
/// 3. Clear description of data usage (geofencing, attendance, payroll validation)
/// 4. Negative declaration (never shared with 3rd parties or used for ads)
/// 5. Affirmative user action ("Agree & Continue" vs "Deny")
/// 6. Triggered IMMEDIATELY BEFORE the OS runtime permission request
class LocationProminentDisclosureDialog extends StatelessWidget {
  const LocationProminentDisclosureDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const LocationProminentDisclosureDialog(),
    );
    return result ?? false;
  }

  @override
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: screenHeight * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Icon Header
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
                ),
                child: const Icon(
                  CupertinoIcons.location_solid,
                  size: 22,
                  color: Color(0xFF15803D),
                ),
              ),
              const SizedBox(height: 8),

              // Title
              Text(
                "Location Data Usage Disclosure",
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 3),

              // Subtitle
              Text(
                "How JOY PeopleHR accesses, collects, and uses your location data",
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // 2. Scrollable Body Content
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Prominent Disclosure Box (Google Play Mandatory Lead Statement)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Mandatory Google Play Background Location Sentence
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    CupertinoIcons.info_circle_fill,
                                    size: 14,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      "JOY PeopleHR collects location data to enable workplace geofence verification, attendance check-in & check-out, and on-duty shift tracking even when the app is closed or not in use.",
                                      style: AppTypography.bodyRegular.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                        color: const Color(0xFF1E3A8A),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Section: Data Collected
                            _buildUsageRow(
                              icon: CupertinoIcons.placemark_fill,
                              iconColor: const Color(0xFF0F766E),
                              title: "Data Collected",
                              description:
                                  "Precise GPS coordinates (latitude, longitude) and location timestamps.",
                            ),
                            const SizedBox(height: 8),

                            // Feature 1: Geofence Verification
                            _buildUsageRow(
                              icon: CupertinoIcons.checkmark_shield_fill,
                              iconColor: const Color(0xFF15803D),
                              title: "Workplace Geofence Verification",
                              description:
                                  "Validates that you are physically present within your company's authorized office, factory, or project boundary during check-in and check-out punches.",
                            ),
                            const SizedBox(height: 8),

                            // Feature 2: Shift Attendance & Duty Tracking
                            _buildUsageRow(
                              icon: CupertinoIcons.clock_fill,
                              iconColor: const Color(0xFF2563EB),
                              title: "Shift Attendance & Duty Calculation",
                              description:
                                  "Accurately calculates on-duty working hours, branch check-ins, and generates verified attendance records for payroll processing.",
                            ),
                            const SizedBox(height: 8),

                            // Feature 3: On-Duty Validation
                            _buildUsageRow(
                              icon: CupertinoIcons.arrow_2_circlepath,
                              iconColor: const Color(0xFFD97706),
                              title: "Continuous Shift Validation",
                              description:
                                  "Periodically verifies location during active shift hours to confirm on-duty presence even when the app is minimized or the screen is off.",
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Data Privacy & Non-Sharing Guarantee
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFDCFCE7)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              CupertinoIcons.lock_shield_fill,
                              size: 14,
                              color: Color(0xFF15803D),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Your location data is encrypted in transit and at rest. It is accessible strictly to your employer's authorized HR administrators and is never sold, shared with third parties, or used for advertising.",
                                style: AppTypography.caption.copyWith(
                                  fontSize: 10.5,
                                  color: const Color(0xFF166534),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 3. Fixed Action Buttons: Always visible & accessible
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        "Deny",
                        style: AppTypography.bodyRegular.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5132),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        "Agree & Continue",
                        style: AppTypography.bodyRegular.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.white,
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

  Widget _buildUsageRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTypography.caption.copyWith(
                  fontSize: 11,
                  color: const Color(0xFF475569),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
