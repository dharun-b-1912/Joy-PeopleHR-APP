import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/attendance_time_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/klarna_tokens.dart';
import '../../../../models/break_models.dart';
import '../../../../repositories/supabase/supabase_attendance_repository.dart';
import 'my_day_timeline_screen.dart';

class BreakHistoryScreen extends StatefulWidget {
  const BreakHistoryScreen({super.key});

  @override
  State<BreakHistoryScreen> createState() => _BreakHistoryScreenState();
}

class _BreakHistoryScreenState extends State<BreakHistoryScreen> {
  final _repo = SupabaseAttendanceRepository();
  String _categoryFilter = 'ALL';
  bool _loading = true;
  List<BreakEventModel> _events = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    final empId = UserService.instance.currentUser.resolvedEmployeeId;
    final rows = await _repo.fetchBreakHistoryRange(
      employeeId: empId,
      fromDate: _fmtDate(from),
      toDate: _fmtDate(now),
    );
    if (!mounted) return;
    setState(() {
      _events = rows.map(BreakEventModel.fromMap).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _categoryFilter == 'ALL'
        ? _events
        : _events.where((e) => e.category.code == _categoryFilter).toList();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        title: const Text(
          'Break History (30 Days)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _catChip('ALL', 'All'),
                  ...BreakCategory.values.map((c) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _catChip(c.code, c.label.replaceAll(' Break', '')),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Text(
                  'No break records found for the selected filter.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              )
            else
              ...filtered.map((ev) {
                final color = ev.category.themeColor;
                final startStr = AttendanceTimeService.formatAttendanceTime(ev.startedAt);
                final endStr = ev.endedAt != null
                    ? AttendanceTimeService.formatAttendanceTime(ev.endedAt!)
                    : 'Active';
                final dateStr = _fmtDate(ev.startedAt);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ListTile(
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => MyDayTimelineScreen(
                          initialDate: DateTime(
                            ev.startedAt.year,
                            ev.startedAt.month,
                            ev.startedAt.day,
                          ),
                        ),
                      ),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(ev.category.icon, color: color, size: 19),
                    ),
                    title: Text(
                      '${ev.category.label} · $dateStr',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      '$startStr → $endStr · ${ev.isPaid ? "Paid" : "Unpaid"}'
                      '${ev.isExcess ? " · Exceeded Limit" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: ev.isExcess ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                      ),
                    ),
                    trailing: Text(
                      '${ev.durationMinutes ?? ev.elapsedMinutesAt(DateTime.now())}m',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: color,
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _catChip(String code, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _categoryFilter == code,
      selectedColor: const Color(0xFFECFDF5),
      onSelected: (_) => setState(() => _categoryFilter = code),
    );
  }
}
