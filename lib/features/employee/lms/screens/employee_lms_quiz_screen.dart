import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/lms_course_model.dart';
import '../services/lms_service.dart';

class EmployeeLmsQuizScreen extends StatefulWidget {
  final LmsCourseModel course;

  const EmployeeLmsQuizScreen({super.key, required this.course});

  @override
  State<EmployeeLmsQuizScreen> createState() => _EmployeeLmsQuizScreenState();
}

class _EmployeeLmsQuizScreenState extends State<EmployeeLmsQuizScreen> {
  final Map<int, int> _selectedAnswers = {};
  bool _isSubmitting = false;
  Map<String, dynamic>? _quizResult;
  int? _userCorrectCount;

  void _onOptionSelected(int questionIndex, int optionIndex) {
    if (_quizResult != null) return; // Locked once submitted
    setState(() {
      _selectedAnswers[questionIndex] = optionIndex;
    });
  }

  Future<void> _submitQuiz() async {
    final questions = widget.course.questions;
    if (questions.isEmpty) return;

    if (_selectedAnswers.length < questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please answer all questions before submitting.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    int correct = 0;
    for (int i = 0; i < questions.length; i++) {
      if (_selectedAnswers[i] == questions[i].correctIndex) {
        correct++;
      }
    }

    final scorePercentage = ((correct / questions.length) * 100).roundToDouble();

    final result = await LmsService.instance.submitAssessmentResult(
      widget.course.id,
      scorePercentage,
      widget.course.passingPercentage,
      correctAnswers: correct,
      passingScoreNumber: widget.course.requiredPassingScore,
    );

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _quizResult = result;
        _userCorrectCount = correct;
      });
    }
  }

  void _retryQuiz() {
    setState(() {
      _selectedAnswers.clear();
      _quizResult = null;
      _userCorrectCount = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.course.questions;
    final isPassed = _quizResult?['passed'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Course Assessment',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(_quizResult != null),
        ),
      ),
      body: questions.isEmpty
          ? Center(
              child: Text(
                'No questions configured for this course assessment.',
                style: GoogleFonts.inter(color: Colors.grey),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.course.title,
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF07563D).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Pass Mark: ${widget.course.requiredPassingScore}/${questions.length} correct',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF07563D),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${questions.length} Questions (${widget.course.passingPercentage}%)',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Result Card if submitted
                if (_quizResult != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isPassed ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isPassed ? Colors.green.shade300 : Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPassed ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.xmark_circle_fill,
                          color: isPassed ? Colors.green.shade700 : Colors.red.shade700,
                          size: 36,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPassed ? 'PASSED CONGRATULATIONS!' : 'FAILED ASSESSMENT',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isPassed ? Colors.green.shade900 : Colors.red.shade900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isPassed
                                    ? 'Score: ${_quizResult!['score']}% (${_userCorrectCount ?? 0}/${questions.length} correct) • Course marked Completed!'
                                    : 'Score: ${_quizResult!['score']}% (${_userCorrectCount ?? 0}/${questions.length} correct) • Required: ${widget.course.requiredPassingScore}/${questions.length} correct to pass',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: isPassed ? Colors.green.shade800 : Colors.red.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isPassed)
                          ElevatedButton(
                            onPressed: _retryQuiz,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Questions list
                ...List.generate(questions.length, (qIdx) {
                  final q = questions[qIdx];
                  final userPick = _selectedAnswers[qIdx];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Color(0xFF07563D),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${qIdx + 1}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                q.question,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Options
                        ...List.generate(q.options.length, (optIdx) {
                          final optText = q.options[optIdx];
                          final isSelected = userPick == optIdx;

                          Color bgColor = Colors.white;
                          Color borderColor = Colors.grey.shade200;
                          Color textColor = Colors.black87;

                          if (_quizResult != null) {
                            if (optIdx == q.correctIndex) {
                              bgColor = const Color(0xFFE8F5E9);
                              borderColor = Colors.green;
                              textColor = Colors.green.shade900;
                            } else if (isSelected && optIdx != q.correctIndex) {
                              bgColor = const Color(0xFFFFEBEE);
                              borderColor = Colors.red;
                              textColor = Colors.red.shade900;
                            }
                          } else if (isSelected) {
                            bgColor = const Color(0xFF07563D).withValues(alpha: 0.08);
                            borderColor = const Color(0xFF07563D);
                            textColor = const Color(0xFF07563D);
                          }

                          return GestureDetector(
                            onTap: () => _onOptionSelected(qIdx, optIdx),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? CupertinoIcons.check_mark_circled_solid
                                        : CupertinoIcons.circle,
                                    size: 18,
                                    color: isSelected ? const Color(0xFF07563D) : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      optText,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 8),

                // Submit button
                if (_quizResult == null)
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitQuiz,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF07563D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'Submit Assessment',
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                  )
                else
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF07563D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Back to Course Player',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
