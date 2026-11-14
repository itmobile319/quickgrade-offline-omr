import 'dart:io';
import 'package:camera/camera.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'models/form_template.dart';
import 'models/quiz_models.dart';
import 'services/local_database.dart';
import 'services/omr_scanner_engine.dart';
import 'services/pdf_sheet_generator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZipGradeOfflineApp());
}

class ZipGradeOfflineApp extends StatelessWidget {
  const ZipGradeOfflineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickGrade Offline OMR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  static const String _defaultQuizId = 'default_quiz_v1';

  int _currentTab = 0;
  int _keySubTab = 0; // 0 = เฉลยปรนัย, 1 = โจทย์อัตนัย
  SheetSize _selectedSize = SheetSize.q20;
  int _choicesCount = 4;
  bool _useEnglishLabels = false;
  String _subjectCode = '33101';
  String _subjectName = 'วิทยาศาสตร์พื้นฐาน';
  late List<int> _answerKey;
  List<EssayQuestion> _essayQuestions = [
    const EssayQuestion(
      id: 'e1',
      prompt: 'นกฮูกบินได้เพราะอะไร',
      maxScore: 5,
      linesCount: 4,
    ),
    const EssayQuestion(
      id: 'e2',
      prompt: 'ทำไม แฮดวิคถึงเป็นนกฮูก',
      maxScore: 1,
      linesCount: 1,
    ),
    const EssayQuestion(
      id: 'e3',
      prompt: '"นกเค้าแมว" เป็นนกหรือเป็นแมว เพราะอะไร',
      maxScore: 4,
      linesCount: 3,
    ),
  ];
  List<ScannedPaper> _papers = [];

  @override
  void initState() {
    super.initState();
    _resetKeyForSize(_selectedSize);
    _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    try {
      final quizzes = await LocalDatabase.getQuizzes();
      if (quizzes.isNotEmpty) {
        final q = quizzes.first;
        final savedPapers = await LocalDatabase.getPapersForQuiz(q.id);
        if (!mounted) return;
        setState(() {
          _selectedSize = q.sheetSize;
          _choicesCount = q.choicesCount;
          _subjectCode = q.subjectCode;
          _subjectName = q.subject;
          _answerKey = List<int>.from(q.answerKey);
          _essayQuestions = List<EssayQuestion>.from(q.essayQuestions);
          _papers = savedPapers;
        });
      } else {
        await _persistQuiz();
      }
    } catch (_) {
      // Fallback safely to in-memory defaults
    }
  }

  Future<void> _persistQuiz() async {
    final quiz = Quiz(
      id: _defaultQuizId,
      title: 'แบบทดสอบ ${_selectedSize.questionCount} ข้อ',
      subject: _subjectName,
      subjectCode: _subjectCode,
      sheetSize: _selectedSize,
      choicesCount: _choicesCount,
      answerKey: _answerKey,
      essayQuestions: _essayQuestions,
      createdAt: DateTime.now(),
    );
    await LocalDatabase.saveQuiz(quiz);
  }

  void _resetKeyForSize(SheetSize size) {
    _answerKey = List.generate(size.questionCount, (i) => i % _choicesCount);
  }

  void _changeSheetSize(SheetSize size) {
    setState(() {
      _selectedSize = size;
      _resetKeyForSize(size);
    });
    _persistQuiz();
  }

  FormTemplate _buildTemplate() {
    final labels = _useEnglishLabels
        ? (_choicesCount == 5
            ? const ['A', 'B', 'C', 'D', 'E']
            : const ['A', 'B', 'C', 'D'])
        : (_choicesCount == 5
            ? const ['ก', 'ข', 'ค', 'ง', 'จ']
            : const ['ก', 'ข', 'ค', 'ง']);

    return FormTemplate(
      sheetSize: _selectedSize,
      choicesCount: _choicesCount,
      choiceLabels: labels,
    );
  }

  @override
  Widget build(BuildContext context) {
    final template = _buildTemplate();

    return Scaffold(
      appBar: AppBar(
        title: const Text('QuickGrade OMR (Offline)'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: DropdownButton<int>(
              value: _choicesCount,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 4, child: Text('4 ตัวเลือก')),
                DropdownMenuItem(value: 5, child: Text('5 ตัวเลือก')),
              ],
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _choicesCount = val;
                  _resetKeyForSize(_selectedSize);
                });
                _persistQuiz();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButton<SheetSize>(
              value: _selectedSize,
              underline: const SizedBox(),
              items: SheetSize.values.map((size) {
                return DropdownMenuItem(
                  value: size,
                  child: Text('${size.questionCount} ข้อ'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) _changeSheetSize(val);
              },
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildAnswerSheetPreviewTab(template),
          _buildAnswerKeyAndEssayTab(template),
          _buildScannerTab(template),
          _buildReviewAndAnalyticsTab(template),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (idx) => setState(() => _currentTab = idx),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.description_outlined),
            label: 'กระดาษคำตอบ',
          ),
          const NavigationDestination(
            icon: Icon(Icons.edit_note),
            label: 'เฉลย/อัตนัย',
          ),
          const NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'สแกนตรวจ',
          ),
          NavigationDestination(
            icon: const Icon(Icons.analytics_outlined),
            label: 'ผลสอบ (${_papers.length})',
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerSheetPreviewTab(FormTemplate template) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.print_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_selectedSize.label} • อัตนัย ${_essayQuestions.length} ข้อ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'วิชา: $_subjectName ($_subjectCode)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'สลับ ก-ง / A-D',
                onPressed: () =>
                    setState(() => _useEnglishLabels = !_useEnglishLabels),
                icon: const Icon(Icons.translate),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final pdfBytes =
                      await PdfSheetGenerator.generateAnswerSheetPdf(
                    template: template,
                    quizTitle: 'แบบทดสอบ ${_selectedSize.questionCount} ข้อ',
                    subjectName: _subjectName,
                    subjectCode: _subjectCode,
                    essayQuestions: _essayQuestions,
                  );
                  await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
                },
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('ส่งออก PDF'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio:
                  FormTemplate.canonicalWidth / FormTemplate.canonicalHeight,
              child: Card(
                margin: const EdgeInsets.all(16),
                elevation: 3,
                child: CustomPaint(
                  painter: AnswerSheetCanvasPainter(
                    template: template,
                    essayQuestions: _essayQuestions,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showSubjectSettingsDialog() async {
    final codeCtrl = TextEditingController(text: _subjectCode);
    final nameCtrl = TextEditingController(text: _subjectName);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ตั้งค่าวิชา (หัวกระดาษคำตอบ)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'ชื่อวิชา',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              maxLength: 5,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'รหัสวิชา 5 หลัก (เช่น 33101)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    final newName = nameCtrl.text.trim();
    final newCode = codeCtrl.text.trim().padLeft(5, '0');
    codeCtrl.dispose();
    nameCtrl.dispose();

    if (saved == true) {
      setState(() {
        if (newName.isNotEmpty) _subjectName = newName;
        if (newCode.isNotEmpty) _subjectCode = newCode;
      });
      await _persistQuiz();
    }
  }

  Future<void> _showAddOrEditEssayDialog({int? editIndex}) async {
    final existing = editIndex != null ? _essayQuestions[editIndex] : null;
    final promptCtrl = TextEditingController(text: existing?.prompt ?? '');
    final scoreCtrl =
        TextEditingController(text: (existing?.maxScore ?? 5).toString());
    final linesCtrl =
        TextEditingController(text: (existing?.linesCount ?? 4).toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'เพิ่มข้อสอบอัตนัย' : 'แก้ไขข้อสอบอัตนัย'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: promptCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'โจทย์คำถามอัตนัย',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: scoreCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'คะแนนเต็ม',
                        suffixText: 'คะแนน',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: linesCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'จำนวนบรรทัดตอบ',
                        suffixText: 'บรรทัด',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    final promptText = promptCtrl.text.trim();
    final maxScore = (int.tryParse(scoreCtrl.text.trim()) ?? 5).clamp(1, 100);
    final linesCount = (int.tryParse(linesCtrl.text.trim()) ?? 4).clamp(1, 20);
    promptCtrl.dispose();
    scoreCtrl.dispose();
    linesCtrl.dispose();

    if (saved == true && promptText.isNotEmpty) {
      final item = EssayQuestion(
        id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        prompt: promptText,
        maxScore: maxScore,
        linesCount: linesCount,
      );
      setState(() {
        if (editIndex != null) {
          _essayQuestions[editIndex] = item;
        } else {
          _essayQuestions.add(item);
        }
      });
      await _persistQuiz();
    }
  }

  Widget _buildAnswerKeyAndEssayTab(FormTemplate template) {
    final labels = template.choiceLabels;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: [
                    const ButtonSegment(value: 0, label: Text('เฉลยปรนัย')),
                    ButtonSegment(
                      value: 1,
                      label: Text('โจทย์อัตนัย (${_essayQuestions.length})'),
                    ),
                  ],
                  selected: {_keySubTab},
                  onSelectionChanged: (s) => setState(() => _keySubTab = s.first),
                ),
              ),
              IconButton(
                tooltip: 'ตั้งค่าชื่อ/รหัสวิชา',
                onPressed: _showSubjectSettingsDialog,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: _keySubTab == 0
              ? ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _selectedSize.questionCount,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, qIndex) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              'ข้อที่ ${qIndex + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          ...List.generate(labels.length, (cIndex) {
                            final isSelected = _answerKey[qIndex] == cIndex;
                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _answerKey[qIndex] = cIndex);
                                  _persistQuiz();
                                },
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey.shade200,
                                  foregroundColor:
                                      isSelected ? Colors.white : Colors.black87,
                                  child: Text(labels[cIndex]),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'คะแนนอัตนัยรวม: ${_essayQuestions.fold(0, (s, e) => s + e.maxScore)} คะแนน',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          FilledButton.icon(
                            onPressed: () => _showAddOrEditEssayDialog(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('เพิ่มโจทย์อัตนัย'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _essayQuestions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final q = _essayQuestions[i];
                          return Card(
                            child: ListTile(
                              title: Text('${i + 1}. ${q.prompt}'),
                              subtitle: Text(
                                '${q.maxScore} คะแนน • เว้นที่ตอบ ${q.linesCount} บรรทัด',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () =>
                                        _showAddOrEditEssayDialog(editIndex: i),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    onPressed: () {
                                      setState(
                                          () => _essayQuestions.removeAt(i));
                                      _persistQuiz();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildScannerTab(FormTemplate template) {
    return LiveCameraScannerView(
      template: template,
      answerKey: _answerKey,
      onPaperGraded: (paper) async {
        HapticFeedback.heavyImpact();
        setState(() {
          _papers.insert(0, paper);
        });
        await LocalDatabase.saveScannedPaper(paper);
      },
    );
  }

  Future<void> _exportCsv() async {
    if (_papers.isEmpty) return;
    final rows = <List<dynamic>>[
      [
        'ReferenceCode9',
        'SubjectCode',
        'ClassRoom',
        'StudentNumber',
        'OmrScore',
        'TotalQuestions',
        'EssayScore',
        'CombinedScore',
        'ScannedAt',
      ],
      ..._papers.map((paper) {
        final id = StudentIdentity.fromNineDigits(paper.studentId);
        return [
          id.fullCode,
          id.subjectCode,
          id.displayRoom,
          int.tryParse(id.studentNumber) ?? 0,
          paper.score,
          paper.totalQuestions,
          paper.essayScore,
          paper.combinedScore,
          paper.scannedAt.toIso8601String(),
        ];
      }),
    ];

    final csvText = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'quickgrade_${_subjectCode}_scores.csv'));
    await file.writeAsString(csvText);
    await Share.shareXFiles([XFile(file.path)], text: 'ผลคะแนน $_subjectName');
  }

  Future<void> _showEssayScoreDialog(int index) async {
    final paper = _papers[index];
    final maxEssay = _essayQuestions.fold(0, (s, q) => s + q.maxScore);
    final ctrl = TextEditingController(text: paper.essayScore.toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('กรอกคะแนนอัตนัย (${paper.studentId})'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'คะแนนอัตนัย (เต็ม $maxEssay)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    final newEssayScore = int.tryParse(ctrl.text.trim()) ?? paper.essayScore;
    ctrl.dispose();

    if (saved == true) {
      final updated = ScannedPaper(
        id: paper.id,
        quizId: paper.quizId,
        studentId: paper.studentId,
        score: paper.score,
        essayScore: newEssayScore.clamp(0, 500),
        totalQuestions: paper.totalQuestions,
        grades: paper.grades,
        gradedImagePath: paper.gradedImagePath,
        scannedAt: paper.scannedAt,
      );
      setState(() => _papers[index] = updated);
      await LocalDatabase.saveScannedPaper(updated);
    }
  }

  Widget _buildReviewAndAnalyticsTab(FormTemplate template) {
    if (_papers.isEmpty) {
      return Center(
        child: Text(
          'ยังไม่มีกระดาษที่ตรวจแล้ว (${_papers.length} แผ่น)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ตรวจแล้ว ${_papers.length} แผ่น (แตะเพื่อใส่คะแนนอัตนัย)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              FilledButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('ส่งออก CSV'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _papers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final paper = _papers[index];
              final identity = StudentIdentity.fromNineDigits(paper.studentId);
              return ListTile(
                onTap: () => _showEssayScoreDialog(index),
                leading: CircleAvatar(child: Text(identity.studentNumber)),
                title: Text('รหัสอ้างอิง: ${identity.fullCode}'),
                subtitle: Text(
                  'วิชา ${identity.subjectCode} • ${identity.displayRoom} • เลขที่ ${int.tryParse(identity.studentNumber) ?? 0}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'รวม ${paper.combinedScore} คะแนน',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.green,
                      ),
                    ),
                    Text(
                      'ปรนัย ${paper.score}/${paper.totalQuestions} + อัตนัย ${paper.essayScore}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// หน้าจอกล้องสแกนกระดาษคำตอบแบบ Real-time
class LiveCameraScannerView extends StatefulWidget {
  final FormTemplate template;
  final List<int> answerKey;
  final ValueChanged<ScannedPaper> onPaperGraded;

  const LiveCameraScannerView({
    super.key,
    required this.template,
    required this.answerKey,
    required this.onPaperGraded,
  });

  @override
  State<LiveCameraScannerView> createState() => _LiveCameraScannerViewState();
}

class _LiveCameraScannerViewState extends State<LiveCameraScannerView> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _flashOn = false;
  OmrScanOutput? _lastScan;
  String? _errorMsg;

  Future<void> _startCamera() async {
    setState(() => _errorMsg = null);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMsg = 'ไม่พบกล้องบนอุปกรณ์นี้');
        return;
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isCameraInitialized = true;
      });
    } catch (e) {
      setState(() => _errorMsg = 'ไม่สามารถเปิดกล้องได้: $e');
    }
  }

  Future<void> _captureAndGradeFrame() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final XFile photo = await ctrl.takePicture();
      final Uint8List bytes = await photo.readAsBytes();
      final output = OmrScannerEngine.processFrame(
        imageBytes: bytes,
        template: widget.template,
        answerKey: widget.answerKey,
      );
      if (output != null && mounted) {
        setState(() => _lastScan = output);
        widget.onPaperGraded(
          ScannedPaper(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            quizId: 'default_quiz_v1',
            studentId: output.studentId,
            score: output.score,
            totalQuestions: widget.template.sheetSize.questionCount,
            grades: output.grades,
            scannedAt: DateTime.now(),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'ยังไม่พบจุดมาร์คสีดำครบทั้ง 4 มุม กรุณาเล็งกระดาษให้อยู่ในกรอบ'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_outlined, size: 72, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                'พร้อมสแกนกระดาษคำตอบ (${widget.template.sheetSize.questionCount} ข้อ)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'กดปุ่มด้านล่างเพื่อเปิดกล้องหลังของมือถือ แล้วเล็งจุดสีดำทั้ง 4 มุมให้ตรงกับกรอบเล็ง',
                textAlign: TextAlign.center,
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _startCamera,
                icon: const Icon(Icons.videocam),
                label: const Text('เปิดกล้องสแกนกระดาษคำตอบ'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),
        CustomPaint(
          painter: ViewfinderOverlayPainter(),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_lastScan != null)
                Builder(builder: (context) {
                  final id =
                      StudentIdentity.fromNineDigits(_lastScan!.studentId);
                  return Card(
                    color: Colors.black87,
                    child: ListTile(
                      title: Text(
                        '${id.fullCode} (${id.displayRoom} เลขที่ ${int.tryParse(id.studentNumber) ?? 0}) — ได้ ${_lastScan!.score}/${widget.template.sheetSize.questionCount}',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'วิชา ${id.subjectCode} • บันทึกผลเรียบร้อย พร้อมสแกนแผ่นต่อไป',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton.filledTonal(
                    onPressed: () async {
                      _flashOn = !_flashOn;
                      await _controller?.setFlashMode(
                        _flashOn ? FlashMode.torch : FlashMode.off,
                      );
                      setState(() {});
                    },
                    icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
                  ),
                  FilledButton.icon(
                    onPressed: _isProcessing ? null : _captureAndGradeFrame,
                    icon: const Icon(Icons.center_focus_strong),
                    label: Text(
                        _isProcessing ? 'กำลังประมวลผล...' : 'สแกนแผ่นนี้'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ViewfinderOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    const double padX = 36.0;
    const double padY = 56.0;
    const double box = 34.0;

    final corners = [
      Rect.fromLTWH(padX, padY, box, box),
      Rect.fromLTWH(size.width - padX - box, padY, box, box),
      Rect.fromLTWH(size.width - padX - box, size.height * 0.56 - box, box, box),
      Rect.fromLTWH(padX, size.height * 0.56 - box, box, box),
    ];

    for (final rect in corners) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AnswerSheetCanvasPainter extends CustomPainter {
  final FormTemplate template;
  final List<EssayQuestion> essayQuestions;

  AnswerSheetCanvasPainter({
    required this.template,
    required this.essayQuestions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / FormTemplate.canonicalWidth;
    final scaleY = size.height / FormTemplate.canonicalHeight;

    final markerPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final essayLinePaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const m = FormTemplate.margin;
    const f = FormTemplate.fiducialSize;
    const w = FormTemplate.canonicalWidth;
    final omrBottom = template.omrZoneBottomY;

    // 4 Corner Fiducials (ล้อมเฉพาะโซนปรนัยด้านบน)
    for (final c in [
      [m, m],
      [w - m - f, m],
      [w - m - f, omrBottom - f],
      [m, omrBottom - f],
    ]) {
      canvas.drawRect(
        Rect.fromLTWH(c[0] * scaleX, c[1] * scaleY, f * scaleX, f * scaleY),
        markerPaint,
      );
    }

    // 9-Digit Identity Bubbles (วิชา 5 + ชั้น/ห้อง 2 + เลขที่ 2)
    for (final col in template.getIdentityBubbles()) {
      for (final b in col) {
        canvas.drawCircle(
          Offset(b.x * scaleX, b.y * scaleY),
          b.radius * scaleX,
          strokePaint,
        );
      }
    }

    // Horizontal Transposed Answer Bubbles
    for (final row in template.getQuestionBubbles()) {
      for (final b in row) {
        canvas.drawCircle(
          Offset(b.x * scaleX, b.y * scaleY),
          b.radius * scaleX,
          strokePaint,
        );
      }
    }

    // Subjective / Essay Writing Lines (ด้านล่างนอกกรอบ OMR)
    double curY = omrBottom + 48.0;
    if (essayQuestions.isEmpty) {
      for (double y = curY;
          y <= FormTemplate.canonicalHeight - 70.0;
          y += 42.0) {
        canvas.drawLine(
          Offset(80 * scaleX, y * scaleY),
          Offset((w - 80) * scaleX, y * scaleY),
          essayLinePaint,
        );
      }
    } else {
      for (final q in essayQuestions) {
        curY += 28.0;
        for (int l = 0; l < q.linesCount; l++) {
          if (curY > FormTemplate.canonicalHeight - 40.0) break;
          canvas.drawLine(
            Offset(80 * scaleX, curY * scaleY),
            Offset((w - 80) * scaleX, curY * scaleY),
            essayLinePaint,
          );
          curY += 28.0;
        }
        curY += 16.0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant AnswerSheetCanvasPainter oldDelegate) =>
      oldDelegate.template.sheetSize != template.sheetSize ||
      oldDelegate.template.choicesCount != template.choicesCount ||
      oldDelegate.essayQuestions != essayQuestions;
}
