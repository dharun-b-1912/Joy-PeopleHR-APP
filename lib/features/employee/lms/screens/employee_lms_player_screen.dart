import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../../models/lms_course_model.dart';
import '../services/lms_service.dart';
import 'employee_lms_quiz_screen.dart';

class EmployeeLmsPlayerScreen extends StatefulWidget {
  final LmsCourseModel course;

  const EmployeeLmsPlayerScreen({super.key, required this.course});

  @override
  State<EmployeeLmsPlayerScreen> createState() => _EmployeeLmsPlayerScreenState();
}

class _EmployeeLmsPlayerScreenState extends State<EmployeeLmsPlayerScreen> {
  // Static in-memory cache to guarantee synchronous, instant playback resumption across re-entries
  static final Map<String, int> _positionCache = {};

  late YoutubePlayerController _controller;
  late LmsCourseModel _course;
  StreamSubscription<YoutubeVideoState>? _positionSubscription;
  StreamSubscription<YoutubePlayerValue>? _valueSubscription;

  int _maxSecondsWatched = 0;
  int _currentProgress = 0;
  int _resumeSeconds = 0;
  bool _watchCompleted = false;
  bool _hasInitialSeeked = false;

  String _formatSeconds(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s < 10 ? '0' : ''}$s';
  }

  @override
  void initState() {
    super.initState();
    _course = widget.course;
    _currentProgress = _course.progressPercentage;
    if (_course.isCompleted || _currentProgress >= 100) {
      _watchCompleted = true;
    }

    // Determine resume position synchronously from static cache or current progress percentage
    int initialResumeSec = _positionCache[_course.id] ?? 0;
    if (initialResumeSec == 0 && _currentProgress > 0) {
      final totalSec = (_course.durationMinutes > 0 ? _course.durationMinutes : 5) * 60;
      initialResumeSec = ((_currentProgress / 100.0) * totalSec).round();
    }

    _resumeSeconds = initialResumeSec;
    _maxSecondsWatched = initialResumeSec;

    final initialVideoId = _course.videoId.isNotEmpty ? _course.videoId : 'dQw4w9WgXcQ';

    _controller = YoutubePlayerController.fromVideoId(
      videoId: initialVideoId,
      autoPlay: true,
      startSeconds: initialResumeSec > 0 ? initialResumeSec.toDouble() : null,
      params: const YoutubePlayerParams(
        showControls: true,
        mute: false,
        showFullscreenButton: true,
        enableCaption: true,
        strictRelatedVideos: true, // Only allow related videos from same channel (blocks random YouTube recommendations)
        showVideoAnnotations: false, // Disables popup annotations, end-screen promos, and cards
      ),
    );

    _loadAsyncResumePosition();

    // Listen to current position for anti-skip protection and position updates
    _positionSubscription = _controller.videoStateStream.listen((s) => _onPositionUpdate(s.position));

    // Listen to player state (playing, ended, etc.)
    _valueSubscription = _controller.stream.listen(_onPlayerValueUpdate);
  }

  Future<void> _loadAsyncResumePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSec = prefs.getInt('lms_resume_sec_${_course.id}') ?? 0;
      if (savedSec > _resumeSeconds && mounted) {
        setState(() {
          _resumeSeconds = savedSec;
          _maxSecondsWatched = savedSec;
        });
        _positionCache[_course.id] = savedSec;
        _controller.seekTo(seconds: savedSec.toDouble(), allowSeekAhead: true);
      }
    } catch (_) {}
  }

  void _onPositionUpdate(Duration position) async {
    final currentSec = position.inSeconds;
    final double totalDurationSec = await _controller.duration;

    if (totalDurationSec > 0) {
      // If player starts near 0 while we have a resume point, jump to it immediately
      if (!_hasInitialSeeked && _resumeSeconds > 0) {
        _hasInitialSeeked = true;
        if (currentSec < _resumeSeconds - 2) {
          _controller.seekTo(seconds: _resumeSeconds.toDouble(), allowSeekAhead: true);
          return;
        }
      }

      // Anti-skip enforcement:
      // If user seeks forward beyond watched point by >2s, force seek back
      if (!_watchCompleted && currentSec > _maxSecondsWatched + 2) {
        _controller.seekTo(seconds: _maxSecondsWatched.toDouble(), allowSeekAhead: false);
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Anti-skip enabled: Please watch the training without skipping forward.'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.black87,
            ),
          );
        }
        return;
      }

      if (currentSec > _maxSecondsWatched) {
        _maxSecondsWatched = currentSec;
        _positionCache[_course.id] = currentSec;
        SharedPreferences.getInstance().then((p) => p.setInt('lms_resume_sec_${_course.id}', currentSec));
      }

      final pct = ((_maxSecondsWatched / totalDurationSec) * 100).clamp(0, 100).toInt();

      if (pct > _currentProgress && mounted) {
        setState(() {
          _currentProgress = pct;
        });

        // Persist to Supabase periodically (milestones or end)
        if (pct % 15 == 0 || pct >= 100) {
          LmsService.instance.updateWatchProgress(_course.id, pct);
        }
      }

      if (pct >= 98 && !_watchCompleted) {
        _markCompleted();
      }
    }
  }

  void _onPlayerValueUpdate(YoutubePlayerValue value) {
    if (value.playerState == PlayerState.playing && !_hasInitialSeeked && _resumeSeconds > 0) {
      _hasInitialSeeked = true;
      _controller.seekTo(seconds: _resumeSeconds.toDouble(), allowSeekAhead: true);
    }
    if (value.playerState == PlayerState.ended && !_watchCompleted) {
      _markCompleted();
    }
  }

  void _markCompleted() {
    if (!mounted || _watchCompleted) return;
    setState(() {
      _watchCompleted = true;
      _currentProgress = 100;
    });
    LmsService.instance.updateWatchProgress(_course.id, 100);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 Video completed! Assessment is now unlocked.'),
        backgroundColor: Color(0xFF07563D),
      ),
    );
  }

  Future<void> _openQuiz() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmployeeLmsQuizScreen(course: _course),
      ),
    );

    if (result == true) {
      final updatedCourses = await LmsService.instance.fetchAssignedCourses();
      final fresh = updatedCourses.firstWhere((c) => c.id == _course.id, orElse: () => _course);
      if (mounted) {
        setState(() {
          _course = fresh;
        });
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _valueSubscription?.cancel();
    _controller.close();
    SharedPreferences.getInstance().then((p) => p.setInt('lms_resume_sec_${_course.id}', _maxSecondsWatched));
    if (_currentProgress > 0) {
      LmsService.instance.updateWatchProgress(_course.id, _currentProgress);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Course Video Player',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
      body: Column(
        children: [
          // Player Area
          AspectRatio(
            aspectRatio: 16 / 9,
            child: YoutubePlayer(controller: _controller),
          ),

          // Details & Anti-Skip Panel
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Course Title & Category
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF07563D).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _course.category,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF07563D),
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (_course.isMandatory)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'MANDATORY',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _course.title,
                        style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.black87),
                      ),
                      if (_course.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _course.description,
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600, height: 1.3),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Resume Position Indicator Banner
                if (_resumeSeconds > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA5D6A7)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(CupertinoIcons.arrow_counterclockwise, size: 14, color: Color(0xFF07563D)),
                            const SizedBox(width: 6),
                            Text(
                              'Resumed from ${_formatSeconds(_resumeSeconds)}',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF07563D)),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () {
                            _positionCache.remove(_course.id);
                            SharedPreferences.getInstance().then((p) => p.remove('lms_resume_sec_${_course.id}'));
                            setState(() {
                              _resumeSeconds = 0;
                              _maxSecondsWatched = 0;
                            });
                            _controller.seekTo(seconds: 0, allowSeekAhead: true);
                          },
                          child: Text(
                            'Restart 0:00',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600, decoration: TextDecoration.underline),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Progress & Anti-Skip Status Banner
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(CupertinoIcons.shield_fill, size: 16, color: Color(0xFF07563D)),
                              const SizedBox(width: 6),
                              Text(
                                'Anti-Skip Verification',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          Text(
                            '$_currentProgress%',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF07563D),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (_currentProgress / 100).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF07563D)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _course.questions.isNotEmpty
                            ? (_watchCompleted
                                ? '✓ Full video watch recorded. You are ready to take the assessment.'
                                : 'Complete watching the video without skipping to unlock the assessment.')
                            : (_watchCompleted
                                ? '✓ Video watch recorded (100%). Tap Complete Training to finish.'
                                : 'Complete watching the video without skipping to finish training.'),
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Assessment Status Card
                if (_course.isCompleted)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.check_mark_circled_solid, color: Colors.green, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Course Completed & Verified',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.green.shade900),
                              ),
                              if (_course.score != null)
                                Text(
                                  'Assessment Score: ${_course.score}% (Passed)',
                                  style: GoogleFonts.inter(fontSize: 12, color: Colors.green.shade800),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_course.isFailed)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.red, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Assessment Failed (${_course.score}%)',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.red.shade900),
                              ),
                              Text(
                                'Required pass score: ${_course.passingPercentage}%. Please re-attempt.',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // Action Button: Complete Training (No Quiz) or Take Assessment
                if (_course.questions.isEmpty)
                  ElevatedButton.icon(
                    onPressed: (_watchCompleted && !_course.isCompleted)
                        ? () async {
                            final success = await LmsService.instance.markCourseCompletedWithoutQuiz(_course.id);
                            if (!mounted || !context.mounted) return;
                            if (success) {
                              setState(() {
                                _course = _course.copyWith(
                                  status: 'COMPLETED',
                                  progressPercentage: 100,
                                );
                              });
                              showCupertinoDialog(
                                context: context,
                                builder: (ctx) => CupertinoAlertDialog(
                                  title: const Text('Training Completed!'),
                                  content: const Text('Congratulations! You have completed watching this training module.'),
                                  actions: [
                                    CupertinoDialogAction(
                                      isDefaultAction: true,
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        if (mounted) {
                                          Navigator.pop(context, true);
                                        }
                                      },
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          }
                        : null,
                    icon: Icon(_course.isCompleted ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.check_mark, size: 18),
                    label: Text(
                      _course.isCompleted ? 'Training Completed ✓' : 'Complete Training',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF07563D),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: _watchCompleted ? 3 : 0,
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: (_watchCompleted || _course.isCompleted || _course.isFailed) ? _openQuiz : null,
                    icon: const Icon(CupertinoIcons.doc_text_fill, size: 18),
                    label: Text(
                      _course.isCompleted
                          ? 'Review Assessment'
                          : _course.isFailed
                              ? 'Re-attempt Assessment'
                              : 'Take Assessment (Need ${_course.requiredPassingScore}/${_course.questions.length} to pass)',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF07563D),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: _watchCompleted ? 3 : 0,
                    ),
                  ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
