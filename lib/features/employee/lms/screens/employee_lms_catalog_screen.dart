import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/lms_course_model.dart';
import '../services/lms_service.dart';
import 'employee_lms_player_screen.dart';

class EmployeeLmsCatalogScreen extends StatefulWidget {
  const EmployeeLmsCatalogScreen({super.key});

  @override
  State<EmployeeLmsCatalogScreen> createState() => _EmployeeLmsCatalogScreenState();
}

class _EmployeeLmsCatalogScreenState extends State<EmployeeLmsCatalogScreen> {
  List<LmsCourseModel> _courses = [];
  bool _isLoading = true;
  String _selectedTab = 'ALL'; // 'ALL', 'PENDING', 'IN_PROGRESS', 'COMPLETED'

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() => _isLoading = true);
    final list = await LmsService.instance.fetchAssignedCourses();
    if (mounted) {
      setState(() {
        _courses = list;
        _isLoading = false;
      });
    }
  }

  List<LmsCourseModel> get _filteredCourses {
    switch (_selectedTab) {
      case 'PENDING':
        return _courses.where((c) => c.isPending).toList();
      case 'IN_PROGRESS':
        return _courses.where((c) => c.isInProgress).toList();
      case 'COMPLETED':
        return _courses.where((c) => c.isCompleted).toList();
      default:
        return _courses;
    }
  }

  void _openPlayer(LmsCourseModel course) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmployeeLmsPlayerScreen(course: course),
      ),
    );

    if (result == true) {
      _loadCourses();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Learning & LMS Portal',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_clockwise, color: Colors.black87),
            onPressed: _loadCourses,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _buildTabChip('ALL', 'All (${_courses.length})'),
                const SizedBox(width: 8),
                _buildTabChip(
                  'PENDING',
                  'Pending (${_courses.where((c) => c.isPending).length})',
                ),
                const SizedBox(width: 8),
                _buildTabChip(
                  'IN_PROGRESS',
                  'Watching (${_courses.where((c) => c.isInProgress).length})',
                ),
                const SizedBox(width: 8),
                _buildTabChip(
                  'COMPLETED',
                  'Done (${_courses.where((c) => c.isCompleted).length})',
                ),
              ],
            ),
          ),

          // Course List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF07563D)),
                  )
                : _filteredCourses.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _loadCourses,
                        child: ListView(
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.book, size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No courses in this category',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'All assigned corporate trainings will appear here.',
                                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCourses,
                        color: const Color(0xFF07563D),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredCourses.length,
                          itemBuilder: (context, index) {
                            final course = _filteredCourses[index];
                            return _buildCourseCard(course);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(String tabKey, String label) {
    final isSelected = _selectedTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = tabKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF07563D) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildCourseCard(LmsCourseModel course) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail with Play overlay
          GestureDetector(
            onTap: () => _openPlayer(course),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: course.thumbnailUrl.isNotEmpty
                      ? Image.network(
                          course.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade900,
                            child: const Center(
                              child: Icon(CupertinoIcons.play_rectangle_fill, color: Colors.white38, size: 48),
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade900,
                          child: const Center(
                            child: Icon(CupertinoIcons.play_rectangle_fill, color: Colors.white38, size: 48),
                          ),
                        ),
                ),
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.25),
                    child: Center(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF07563D).withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 12),
                          ],
                        ),
                        child: const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
                if (course.isMandatory)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'MANDATORY',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${course.durationMinutes} Mins',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Details Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07563D).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        course.category,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF07563D),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Pass: ${course.passingPercentage}%',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  course.title,
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                // Progress Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      course.isCompleted
                          ? 'Completed (Score: ${course.score?.round()}%)'
                          : course.isFailed
                              ? 'Failed (${course.score?.round()}%)'
                              : course.isInProgress
                                  ? 'Watching'
                                  : 'Not Started',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: course.isCompleted
                            ? Colors.green.shade700
                            : course.isFailed
                                ? Colors.red.shade700
                                : Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '${course.progressPercentage}%',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF07563D)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (course.progressPercentage / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      course.isCompleted
                          ? Colors.green
                          : course.isFailed
                              ? Colors.red
                              : const Color(0xFF07563D),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _openPlayer(course),
                    icon: Icon(
                      course.isCompleted ? CupertinoIcons.checkmark_alt : CupertinoIcons.play_fill,
                      size: 14,
                    ),
                    label: Text(
                      course.isCompleted
                          ? 'Review Course & Quiz'
                          : course.isInProgress
                              ? 'Resume Watching'
                              : 'Watch & Complete',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: course.isCompleted ? Colors.green.shade700 : const Color(0xFF07563D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
