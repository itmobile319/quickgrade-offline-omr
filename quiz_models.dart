import 'dart:convert';
import 'form_template.dart';

enum MarkStatus {
  correct,
  incorrect,
  blank,
  multipleMarks,
}

/// คำถามอัตนัย / แสดงวิธีทำ สำหรับตอนที่ 2 ของกระดาษคำตอบ
class EssayQuestion {
  final String id;
  final String prompt;
  final int maxScore;
  final int linesCount;

  const EssayQuestion({
    required this.id,
    required this.prompt,
    this.maxScore = 5,
    this.linesCount = 4,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'maxScore': maxScore,
        'linesCount': linesCount,
      };

  factory EssayQuestion.fromJson(Map<String, dynamic> json) => EssayQuestion(
        id: json['id'] as String,
        prompt: json['prompt'] as String,
        maxScore: (json['maxScore'] as num?)?.toInt() ?? 5,
        linesCount: (json['linesCount'] as num?)?.toInt() ?? 4,
      );
}

class QuestionGrade {
  final int questionNumber; // 1-indexed
  final int? selectedChoice; // null if blank
  final int correctChoice;
  final MarkStatus status;
  final List<double> fillRatios;

  const QuestionGrade({
    required this.questionNumber,
    required this.selectedChoice,
    required this.correctChoice,
    required this.status,
    required this.fillRatios,
  });

  Map<String, dynamic> toJson() => {
        'q': questionNumber,
        'sel': selectedChoice,
        'key': correctChoice,
        'status': status.name,
        'ratios': fillRatios,
      };

  factory QuestionGrade.fromJson(Map<String, dynamic> json) => QuestionGrade(
        questionNumber: json['q'] as int,
        selectedChoice: json['sel'] as int?,
        correctChoice: json['key'] as int,
        status: MarkStatus.values.byName(json['status'] as String),
        fillRatios:
            (json['ratios'] as List).map((e) => (e as num).toDouble()).toList(),
      );
}

class ScannedPaper {
  final String id;
  final String quizId;
  final String studentId; // รหัสอ้างอิง 9 หลัก (เช่น 331013109)
  final int score;
  final int essayScore;
  final int totalQuestions;
  final List<QuestionGrade> grades;
  final String? gradedImagePath;
  final DateTime scannedAt;

  const ScannedPaper({
    required this.id,
    required this.quizId,
    required this.studentId,
    required this.score,
    this.essayScore = 0,
    required this.totalQuestions,
    required this.grades,
    this.gradedImagePath,
    required this.scannedAt,
  });

  double get percentage =>
      totalQuestions == 0 ? 0 : (score / totalQuestions) * 100.0;

  int get combinedScore => score + essayScore;

  Map<String, dynamic> toMap() => {
        'id': id,
        'quizId': quizId,
        'studentId': studentId,
        'score': score,
        'essayScore': essayScore,
        'totalQuestions': totalQuestions,
        'gradesJson': jsonEncode(grades.map((g) => g.toJson()).toList()),
        'gradedImagePath': gradedImagePath,
        'scannedAt': scannedAt.toIso8601String(),
      };

  factory ScannedPaper.fromMap(Map<String, dynamic> map) {
    final List<dynamic> decoded = jsonDecode(map['gradesJson'] as String);
    return ScannedPaper(
      id: map['id'] as String,
      quizId: map['quizId'] as String,
      studentId: map['studentId'] as String,
      score: map['score'] as int,
      essayScore: (map['essayScore'] as int?) ?? 0,
      totalQuestions: map['totalQuestions'] as int,
      grades: decoded
          .map((item) => QuestionGrade.fromJson(item as Map<String, dynamic>))
          .toList(),
      gradedImagePath: map['gradedImagePath'] as String?,
      scannedAt: DateTime.parse(map['scannedAt'] as String),
    );
  }
}

class Quiz {
  final String id;
  final String title;
  final String subject;
  final String subjectCode; // รหัสวิชา 5 หลัก เช่น 33101
  final String instructions; // คำอธิบาย/คำชี้แจงบนกระดาษคำตอบ (ไม่เกิน 3 บรรทัด)
  final SheetSize sheetSize;
  final int choicesCount;
  final List<int> answerKey;
  final List<EssayQuestion> essayQuestions;
  final DateTime createdAt;

  const Quiz({
    required this.id,
    required this.title,
    required this.subject,
    this.subjectCode = '33101',
    this.instructions = '',
    required this.sheetSize,
    this.choicesCount = 4,
    required this.answerKey,
    this.essayQuestions = const [],
    required this.createdAt,
  });

  FormTemplate get template => FormTemplate(
        sheetSize: sheetSize,
        choicesCount: choicesCount,
      );

  int get maxEssayScore =>
      essayQuestions.fold(0, (sum, item) => sum + item.maxScore);

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'subject': subject,
        'subjectCode': subjectCode,
        'instructions': instructions,
        'sheetSize': sheetSize.name,
        'choicesCount': choicesCount,
        'answerKeyJson': jsonEncode(answerKey),
        'essayQuestionsJson':
            jsonEncode(essayQuestions.map((e) => e.toJson()).toList()),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Quiz.fromMap(Map<String, dynamic> map) {
    final essayList = map['essayQuestionsJson'] != null
        ? (jsonDecode(map['essayQuestionsJson'] as String) as List)
            .map((e) => EssayQuestion.fromJson(e as Map<String, dynamic>))
            .toList()
        : <EssayQuestion>[];
    return Quiz(
      id: map['id'] as String,
      title: map['title'] as String,
      subject: map['subject'] as String,
      subjectCode: (map['subjectCode'] as String?) ?? '33101',
      instructions: (map['instructions'] as String?) ?? '',
      sheetSize: SheetSize.values.byName(map['sheetSize'] as String),
      choicesCount: map['choicesCount'] as int,
      answerKey: (jsonDecode(map['answerKeyJson'] as String) as List)
          .map((e) => e as int)
          .toList(),
      essayQuestions: essayList,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
