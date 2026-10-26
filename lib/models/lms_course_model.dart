/// Represents a Quiz Question in a Course Assessment
class QuizQuestionModel {
  final String id;
  final String question;
  final List<String> options;
  final int correctIndex;

  const QuizQuestionModel({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
  });

  factory QuizQuestionModel.fromJson(Map<String, dynamic> json) {
    return QuizQuestionModel(
      id: json['id']?.toString() ?? '',
      question: json['question']?.toString() ?? '',
      options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      correctIndex: int.tryParse(json['correctIndex']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'options': options,
    'correctIndex': correctIndex,
  };
}

/// Represents an LMS Course with live YouTube metadata, anti-skip state,
/// and assessment pass/fail constraint.
class LmsCourseModel {
  final String id;
  final String organizationId;
  final String title;
  final String code;
  final String category;
  final bool isMandatory;
  final int durationMinutes;
  final bool isActive;
  final DateTime? createdAt;

  // Rich metadata
  final String videoId;
  final String youtubeUrl;
  final String thumbnailUrl;
  final int passingPercentage;
  final String description;
  final List<QuizQuestionModel> questions;

  // User enrollment state
  final String? enrollmentId;
  final int progressPercentage;
  final double? score;
  final String status; // 'ENROLLED' | 'IN_PROGRESS' | 'COMPLETED' | 'FAILED'
  final DateTime? completedAt;

  const LmsCourseModel({
    required this.id,
    required this.organizationId,
    required this.title,
    required this.code,
    required this.category,
    required this.isMandatory,
    required this.durationMinutes,
    required this.isActive,
    this.createdAt,
    required this.videoId,
    required this.youtubeUrl,
    required this.thumbnailUrl,
    required this.passingPercentage,
    required this.description,
    required this.questions,
    this.enrollmentId,
    this.progressPercentage = 0,
    this.score,
    this.status = 'ENROLLED',
    this.completedAt,
  });

  bool get isCompleted => status == 'COMPLETED';
  bool get isFailed => status == 'FAILED';
  bool get isInProgress => progressPercentage > 0 && !isCompleted && !isFailed;
  bool get isPending => progressPercentage == 0 && !isCompleted && !isFailed;

  LmsCourseModel copyWith({
    int? progressPercentage,
    double? score,
    String? status,
    DateTime? completedAt,
  }) {
    return LmsCourseModel(
      id: id,
      organizationId: organizationId,
      title: title,
      code: code,
      category: category,
      isMandatory: isMandatory,
      durationMinutes: durationMinutes,
      isActive: isActive,
      createdAt: createdAt,
      videoId: videoId,
      youtubeUrl: youtubeUrl,
      thumbnailUrl: thumbnailUrl,
      passingPercentage: passingPercentage,
      description: description,
      questions: questions,
      enrollmentId: enrollmentId,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      score: score ?? this.score,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
