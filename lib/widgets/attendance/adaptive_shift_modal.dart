import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/shift_adaptive_service.dart';

class AdaptiveShiftModal extends StatefulWidget {
  final CompanyShift detectedShift;
  final List<CompanyShift> availableShifts;
  final String locationName;
  final double? distanceMeters;

  const AdaptiveShiftModal({
    super.key,
    required this.detectedShift,
    required this.availableShifts,
    required this.locationName,
    this.distanceMeters,
  });

  /// Displays the modal bottom sheet and returns the confirmed CompanyShift or null if canceled
  static Future<CompanyShift?> show({
    required BuildContext context,
    required CompanyShift detectedShift,
    required List<CompanyShift> availableShifts,
    required String locationName,
    double? distanceMeters,
  }) {
    return showModalBottomSheet<CompanyShift>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AdaptiveShiftModal(
        detectedShift: detectedShift,
        availableShifts: availableShifts,
        locationName: locationName,
        distanceMeters: distanceMeters,
      ),
    );
  }

  @override
  State<AdaptiveShiftModal> createState() => _AdaptiveShiftModalState();
}

class _AdaptiveShiftModalState extends State<AdaptiveShiftModal> {
  late CompanyShift _selectedShift;
  bool _showAvailableShifts = true;

  @override
  void initState() {
    super.initState();
    _selectedShift = widget.detectedShift;
  }

  bool get _isAutoDetectedSelected => _selectedShift.id == widget.detectedShift.id;

  String get _distanceDisplay {
    if (widget.distanceMeters == null) return "0m";
    if (widget.distanceMeters! < 1) return "0m";
    if (widget.distanceMeters! >= 1000) {
      return "${(widget.distanceMeters! / 1000).toStringAsFixed(1)}km";
    }
    return "${widget.distanceMeters!.toStringAsFixed(0)}m";
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final otherShifts = widget.availableShifts
        .where((s) => s.id != widget.detectedShift.id)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Header: Clock Icon + Title & Subtitle
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDDF4EC), // Soft mint circle
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.schedule_rounded,
                        color: Color(0xFF0F766E), // Deep emerald
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Confirm Shift Check-In",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Auto-detected for your current work window",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Auto-Detected Nearest Shift Hero Card
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedShift = widget.detectedShift;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isAutoDetectedSelected
                          ? const Color(0xFF2DD4BF) // Mint highlight border
                          : const Color(0xFFE2E8F0),
                      width: _isAutoDetectedSelected ? 1.5 : 1.0,
                    ),
                    boxShadow: _isAutoDetectedSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF2DD4BF).withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge & Distance Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCCFBF1), // Mint pill
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.auto_awesome,
                                  size: 13,
                                  color: Color(0xFF0F766E),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  "AUTO-DETECTED NEAREST",
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F766E),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "• $_distanceDisplay away",
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Shift Name
                      Text(
                        widget.detectedShift.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Timing & Code
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_outlined,
                            size: 15,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "${widget.detectedShift.formattedRange}  •  ${widget.detectedShift.code.isNotEmpty ? widget.detectedShift.code : 'GEN-10'}",
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Location
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.locationName.isNotEmpty
                                  ? widget.locationName
                                  : 'Joy Corporate Solutions Private Limited (HQ)',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w400,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Available Factory Shifts Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Available Factory Shifts",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showAvailableShifts = !_showAvailableShifts;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _showAvailableShifts ? "Hide" : "Show",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0D9488),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // List of Alternative Factory Shifts
              if (_showAvailableShifts && otherShifts.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: otherShifts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final shift = otherShifts[index];
                      final isSelected = shift.id == _selectedShift.id;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedShift = shift;
                          });
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFF0FDFA) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Circular Radio Selector
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF0D9488)
                                        : const Color(0xFFCBD5E1),
                                    width: 1.5,
                                  ),
                                  color: isSelected
                                      ? const Color(0xFF0D9488)
                                      : Colors.transparent,
                                ),
                                child: isSelected
                                    ? Center(
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 14),

                              // Shift Name & Timing
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      shift.name,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      shift.formattedRange,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Bottom Actions: Cancel & Confirm
              Row(
                children: [
                  // Cancel Button
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          foregroundColor: const Color(0xFF475569),
                          backgroundColor: Colors.white,
                          elevation: 0,
                        ),
                        child: Text(
                          "Cancel",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Confirm & Check In Button
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(_selectedShift),
                        icon: const Icon(
                          Icons.check,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          "Confirm & Check In",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E), // Deep emerald
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
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
