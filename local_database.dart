import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/quiz_models.dart';

/// ฐานข้อมูล SQLite ในเครื่อง (Offline 100%)
/// เก็บชุดข้อสอบ เฉลย และประวัติกระดาษคำตอบที่สแกนแล้วทั้งหมด
class LocalDatabase {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'zipgrade_offline.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE quizzes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            subject TEXT NOT NULL,
            subjectCode TEXT NOT NULL,
            sheetSize TEXT NOT NULL,
            choicesCount INTEGER NOT NULL,
            answerKeyJson TEXT NOT NULL,
            essayQuestionsJson TEXT NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE scanned_papers (
            id TEXT PRIMARY KEY,
            quizId TEXT NOT NULL,
            studentId TEXT NOT NULL,
            score INTEGER NOT NULL,
            essayScore INTEGER NOT NULL DEFAULT 0,
            totalQuestions INTEGER NOT NULL,
            gradesJson TEXT NOT NULL,
            gradedImagePath TEXT,
            scannedAt TEXT NOT NULL,
            FOREIGN KEY (quizId) REFERENCES quizzes (id) ON DELETE CASCADE
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<void> saveQuiz(Quiz quiz) async {
    final db = await database;
    await db.insert(
      'quizzes',
      quiz.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Quiz>> getQuizzes() async {
    final db = await database;
    final rows = await db.query('quizzes', orderBy: 'createdAt DESC');
    return rows.map((r) => Quiz.fromMap(r)).toList();
  }

  static Future<void> saveScannedPaper(ScannedPaper paper) async {
    final db = await database;
    await db.insert(
      'scanned_papers',
      paper.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<ScannedPaper>> getPapersForQuiz(String quizId) async {
    final db = await database;
    final rows = await db.query(
      'scanned_papers',
      where: 'quizId = ?',
      whereArgs: [quizId],
      orderBy: 'scannedAt DESC',
    );
    return rows.map((r) => ScannedPaper.fromMap(r)).toList();
  }
}
