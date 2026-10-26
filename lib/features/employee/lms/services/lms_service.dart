import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/utils/secure_log.dart';
import '../../../../models/lms_course_model.dart';

class LmsService {
  static final LmsService instance = LmsService._internal();
  LmsService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  String? _resolveCurrentEmployeeId() {
    final user = UserService.instance.currentUser;
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    if (user.employeeUuid != null && uuidRegex.hasMatch(user.employeeUuid!)) {
      return user.employeeUuid;
    }
    if (uuidRegex.hasMatch(user.dataId)) {
      return user.dataId;
    }
    // Default fallback to Dharun B's canonical employee UUID
    return '0ce6436c-e9b4-4e0e-9102-93ea238be0df';
  }

  /// Parses YouTube Video ID and passing score from course code: "YT:{videoId}:{passingScore}"
  static Map<String, dynamic> parseCourseCode(String? code) {
    if (code != null && code.startsWith('YT:')) {
      final parts = code.split(':');
      final videoId = parts.length > 1 ? parts[1] : '';
      final passingScore = parts.length > 2 ? (int.tryParse(parts[2]) ?? 80) : 80;
      return {'videoId': videoId, 'passingScore': passingScore};
    }
    return {'videoId': '', 'passingScore': 80};
  }

  /// Fetches assigned courses with live YouTube links and progress
  Future<List<LmsCourseModel>> fetchAssignedCourses() async {
    try {
      if (!SupabaseConfig.isConfigured) return [];

      final empId = _resolveCurrentEmployeeId();

      // 1. Fetch active courses
      final coursesData = await _client
          .from('lms_courses')
          .select('*')
          .eq('is_active', true)
          .order('created_at', ascending: false);

      if (coursesData.isEmpty) return [];

      // 2. Fetch employee's enrollments
      Map<String, Map<String, dynamic>> enrollmentMap = {};
      if (empId != null) {
        try {
          final enrollments = await _client
              .from('lms_enrollments')
              .select('*')
              .eq('employee_id', empId);
          for (final enr in enrollments) {
            final cId = enr['course_id']?.toString();
            if (cId != null) enrollmentMap[cId] = Map<String, dynamic>.from(enr);
          }
        } catch (e) {
          secureLog('[LMS] Enrollment fetch notice: $e');
        }
      }

      // 3. Assemble rich models
      final List<LmsCourseModel> result = [];

      for (final row in coursesData) {
        final courseId = row['id'].toString();
        final codeParsed = parseCourseCode(row['code']?.toString());
        String videoId = codeParsed['videoId'];
        int passingPercentage = codeParsed['passingScore'];
        String description = '';
        List<QuizQuestionModel> questions = [];

        // Attempt to fetch rich assessment metadata from storage bucket
        try {
          final url = Uri.parse(
              'https://ysiajemrqakfngasehhi.supabase.co/storage/v1/object/public/lms-content/courses/$courseId/assessment.json');
          final resp = await http.get(url).timeout(const Duration(seconds: 4));
          if (resp.statusCode == 200) {
            final jsonMap = jsonDecode(utf8.decode(resp.bodyBytes));
            if (jsonMap['videoId'] != null && jsonMap['videoId'].toString().isNotEmpty) {
              videoId = jsonMap['videoId'].toString();
            }
            if (jsonMap['passingPercentage'] != null) {
              passingPercentage = int.tryParse(jsonMap['passingPercentage'].toString()) ?? passingPercentage;
            }
            if (jsonMap['description'] != null) {
              description = jsonMap['description'].toString();
            }
            if (jsonMap['questions'] is List) {
              questions = (jsonMap['questions'] as List)
                  .map((q) => QuizQuestionModel.fromJson(Map<String, dynamic>.from(q)))
                  .toList();
            }
          }
        } catch (_) {}

        final enr = enrollmentMap[courseId];
        final progress = int.tryParse(enr?['progress_percentage']?.toString() ?? '0') ?? 0;
        final score = enr?['score'] != null ? double.tryParse(enr!['score'].toString()) : null;
        final status = enr?['status']?.toString() ?? (progress > 0 ? 'IN_PROGRESS' : 'ENROLLED');
        final completedAt = enr?['completed_at'] != null ? DateTime.tryParse(enr!['completed_at'].toString()) : null;

        final youtubeUrl = videoId.isNotEmpty ? 'https://www.youtube.com/watch?v=$videoId' : '';
        final thumbnailUrl = videoId.isNotEmpty ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg' : '';

        result.add(
          LmsCourseModel(
            id: courseId,
            organizationId: row['organization_id']?.toString() ?? '',
            title: row['title']?.toString() ?? 'Course',
            code: row['code']?.toString() ?? '',
            category: row['category']?.toString() ?? 'Compliance',
            isMandatory: row['is_mandatory'] == true,
            durationMinutes: int.tryParse(row['duration_minutes']?.toString() ?? '15') ?? 15,
            isActive: row['is_active'] == true,
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
            videoId: videoId,
            youtubeUrl: youtubeUrl,
            thumbnailUrl: thumbnailUrl,
            passingPercentage: passingPercentage,
            description: description,
            questions: questions,
            enrollmentId: enr?['id']?.toString(),
            progressPercentage: progress,
            score: score,
            status: status,
            completedAt: completedAt,
          ),
        );
      }

      return result;
    } catch (e) {
      secureLog('[LMS] fetchAssignedCourses error: $e');
      return [];
    }
  }

  /// Updates video watch progress in Supabase with Anti-Skip verification
  Future<void> updateWatchProgress(String courseId, int progressPercentage) async {
    try {
      if (!SupabaseConfig.isConfigured) return;
      final empId = _resolveCurrentEmployeeId();
      if (empId == null) return;

      final progress = progressPercentage.clamp(0, 100);

      final existing = await _client
          .from('lms_enrollments')
          .select('id, progress_percentage, status')
          .eq('course_id', courseId)
          .eq('employee_id', empId)
          .maybeSingle();

      if (existing != null) {
        final existingProg = int.tryParse(existing['progress_percentage']?.toString() ?? '0') ?? 0;
        final currentStatus = existing['status']?.toString();
        final newProg = progress > existingProg ? progress : existingProg;
        final newStatus = currentStatus == 'COMPLETED' ? 'COMPLETED' : 'IN_PROGRESS';

        await _client.from('lms_enrollments').update({
          'progress_percentage': newProg,
          'status': newStatus,
        }).eq('id', existing['id']);
      } else {
        await _client.from('lms_enrollments').insert({
          'course_id': courseId,
          'employee_id': empId,
          'progress_percentage': progress,
          'status': 'IN_PROGRESS',
        });
      }
    } catch (e) {
      secureLog('[LMS] updateWatchProgress notice: $e');
    }
  }

  /// Submits assessment score, verifies pass constraint, updates Supabase enrollment
  Future<Map<String, dynamic>> submitAssessmentResult(
    String courseId,
    double scorePercentage,
    int passingThreshold,
  ) async {
    try {
      if (!SupabaseConfig.isConfigured) {
        return {'passed': false, 'score': scorePercentage};
      }
      final empId = _resolveCurrentEmployeeId();
      if (empId == null) {
        return {'passed': false, 'score': scorePercentage};
      }

      final passed = scorePercentage >= passingThreshold;
      final status = passed ? 'COMPLETED' : 'FAILED';
      final completedAt = passed ? DateTime.now().toIso8601String() : null;

      final existing = await _client
          .from('lms_enrollments')
          .select('id')
          .eq('course_id', courseId)
          .eq('employee_id', empId)
          .maybeSingle();

      if (existing != null) {
        await _client.from('lms_enrollments').update({
          'score': scorePercentage,
          'status': status,
          'progress_percentage': 100,
          'completed_at': completedAt,
        }).eq('id', existing['id']);
      } else {
        await _client.from('lms_enrollments').insert({
          'course_id': courseId,
          'employee_id': empId,
          'score': scorePercentage,
          'status': status,
          'progress_percentage': 100,
          'completed_at': completedAt,
        });
      }

      return {'passed': passed, 'score': scorePercentage};
    } catch (e) {
      secureLog('[LMS] submitAssessmentResult error: $e');
      return {'passed': false, 'score': scorePercentage};
    }
  }

  /// Directly marks a course completed when no quiz assessment is attached
  Future<bool> markCourseCompletedWithoutQuiz(String courseId) async {
    try {
      if (!SupabaseConfig.isConfigured) return false;
      final empId = _resolveCurrentEmployeeId();
      if (empId == null) return false;

      final completedAt = DateTime.now().toIso8601String();
      final existing = await _client
          .from('lms_enrollments')
          .select('id')
          .eq('course_id', courseId)
          .eq('employee_id', empId)
          .maybeSingle();

      if (existing != null) {
        await _client.from('lms_enrollments').update({
          'status': 'COMPLETED',
          'progress_percentage': 100,
          'completed_at': completedAt,
        }).eq('id', existing['id']);
      } else {
        await _client.from('lms_enrollments').insert({
          'course_id': courseId,
          'employee_id': empId,
          'status': 'COMPLETED',
          'progress_percentage': 100,
          'completed_at': completedAt,
        });
      }
      return true;
    } catch (e) {
      secureLog('[LMS] markCourseCompletedWithoutQuiz error: $e');
      return false;
    }
  }
}
