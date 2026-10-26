import 'package:flutter_test/flutter_test.dart';
import 'package:workforce_os/models/lms_course_model.dart';
import 'package:workforce_os/features/employee/lms/services/lms_service.dart';

void main() {
  group('LMS Workflow & Business Logic Tests', () {
    test('LmsService.parseCourseCode parses YouTube code YT:<videoId>:<passingScore> correctly', () {
      final res = LmsService.parseCourseCode('YT:sBws8MSXN7A:80');
      expect(res['videoId'], 'sBws8MSXN7A');
      expect(res['passingScore'], 80);

      final resCustom = LmsService.parseCourseCode('YT:dQw4w9WgXcQ:75');
      expect(resCustom['videoId'], 'dQw4w9WgXcQ');
      expect(resCustom['passingScore'], 75);

      final resFallback = LmsService.parseCourseCode('GENERAL-101');
      expect(resFallback['videoId'], '');
      expect(resFallback['passingScore'], 80);
    });

    test('LmsCourseModel instantiates with YouTube metadata and calculated properties', () {
      final parsed = LmsService.parseCourseCode('YT:sBws8MSXN7A:80');
      final videoId = parsed['videoId'] as String;
      final passingScore = parsed['passingScore'] as int;

      final course = LmsCourseModel(
        id: 'ebe141d0-8726-4086-aa68-0c9d0a8a1598',
        organizationId: '0c621892-e938-4707-9957-13534ea32c19',
        title: 'Workplace Safety, Ergonomics & Emergency Evacuation 2026',
        code: 'YT:sBws8MSXN7A:80',
        category: 'Mandatory Compliance',
        isMandatory: true,
        durationMinutes: 45,
        isActive: true,
        videoId: videoId,
        youtubeUrl: 'https://www.youtube.com/watch?v=$videoId',
        thumbnailUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
        passingPercentage: passingScore,
        description: 'Mandatory workplace safety guidelines.',
        questions: [],
        progressPercentage: 0,
        status: 'ENROLLED',
      );

      expect(course.id, 'ebe141d0-8726-4086-aa68-0c9d0a8a1598');
      expect(course.title, 'Workplace Safety, Ergonomics & Emergency Evacuation 2026');
      expect(course.videoId, 'sBws8MSXN7A');
      expect(course.passingPercentage, 80);
      expect(course.isPending, isTrue);
      expect(course.isInProgress, isFalse);
      expect(course.isCompleted, isFalse);

      final inProgress = course.copyWith(progressPercentage: 50, status: 'IN_PROGRESS');
      expect(inProgress.isInProgress, isTrue);
      expect(inProgress.isPending, isFalse);

      final completed = course.copyWith(progressPercentage: 100, status: 'COMPLETED', score: 100.0);
      expect(completed.isCompleted, isTrue);
      expect(completed.score, 100.0);
    });

    test('QuizQuestionModel parses JSON questions accurately', () {
      final json = {
        'id': 'q1',
        'question': 'What is the primary action in case of fire?',
        'options': ['Take elevator', 'Use stairs calmly', 'Hide in office', 'Ignore alarm'],
        'correctIndex': 1,
      };

      final q = QuizQuestionModel.fromJson(json);
      expect(q.id, 'q1');
      expect(q.question, 'What is the primary action in case of fire?');
      expect(q.options.length, 4);
      expect(q.correctIndex, 1);
    });

    test('Quiz assessment evaluation determines pass/fail against threshold constraint', () {
      final questions = [
        const QuizQuestionModel(
          id: 'q1',
          question: 'What is the primary action in case of fire?',
          options: ['Take elevator', 'Use stairs calmly', 'Hide', 'Ignore'],
          correctIndex: 1,
        ),
        const QuizQuestionModel(
          id: 'q2',
          question: 'What is the recommended ergonomic monitor height?',
          options: ['Above head', 'At eye level', 'On floor', 'Behind keyboard'],
          correctIndex: 1,
        ),
        const QuizQuestionModel(
          id: 'q3',
          question: 'How often should you take eye breaks?',
          options: ['Every 20 mins', 'Never', 'Every 5 hours', 'Once a day'],
          correctIndex: 0,
        ),
        const QuizQuestionModel(
          id: 'q4',
          question: 'Where is the assembly point located?',
          options: ['In cafeteria', 'Main parking lawn', 'Restroom', 'Roof'],
          correctIndex: 1,
        ),
      ];

      // 4 out of 4 correct = 100%
      int score4 = 0;
      final userAnswersAllCorrect = {0: 1, 1: 1, 2: 0, 3: 1};
      for (int i = 0; i < questions.length; i++) {
        if (userAnswersAllCorrect[i] == questions[i].correctIndex) {
          score4++;
        }
      }
      final percentage100 = (score4 / questions.length * 100).round();
      expect(percentage100, 100);
      expect(percentage100 >= 80, isTrue); // PASS

      // 3 out of 4 correct = 75%
      int score3 = 0;
      final userAnswers75 = {0: 1, 1: 1, 2: 0, 3: 0}; // question 4 wrong
      for (int i = 0; i < questions.length; i++) {
        if (userAnswers75[i] == questions[i].correctIndex) {
          score3++;
        }
      }
      final percentage75 = (score3 / questions.length * 100).round();
      expect(percentage75, 75);
      expect(percentage75 >= 80, isFalse); // FAIL against 80% passing threshold
      expect(percentage75 >= 70, isTrue); // PASS against 70% threshold
    });

    test('Anti-skip threshold logic detects forward skip violations', () {
      double maxWatchTime = 35.0; // Employee has watched up to 35s

      bool isForwardSkip(double currentPosition) {
        return currentPosition > maxWatchTime + 2.0;
      }

      expect(isForwardSkip(36.0), isFalse); // Normal 1s progression
      expect(isForwardSkip(37.0), isFalse); // 2s progression
      expect(isForwardSkip(45.0), isTrue);  // Forward skip attempt!
      expect(isForwardSkip(120.0), isTrue); // Major skip forward!
      expect(isForwardSkip(10.0), isFalse); // Allowed to seek backwards
    });
  });
}
