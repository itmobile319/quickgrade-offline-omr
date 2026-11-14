import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/form_template.dart';
import '../models/quiz_models.dart';

/// สร้างไฟล์ PDF กระดาษคำตอบแบบ Hybrid (A4) พร้อมโจทย์อัตนัยที่ครูพิมพ์ในแอป
/// - ครึ่งบน: รหัสอ้างอิง 9 หลัก (วิชา 5 + ชั้น/ห้อง 2 + เลขที่ 2) + ช้อยส์แนวนอน (แบบที่ 2)
/// - ครึ่งล่าง: พิมพ์โจทย์ข้อสอบอัตนัยภาษาไทย/อังกฤษ + คะแนนเต็ม + เส้นบรรทัดให้พร้อมแจกสอบทันที
class PdfSheetGenerator {
  static Future<pw.ThemeData?> _loadThaiTheme() async {
    try {
      final regData = await rootBundle.load('assets/fonts/Sarabun-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Sarabun-Bold.ttf');
      return pw.ThemeData.withFont(
        base: pw.Font.ttf(regData),
        bold: pw.Font.ttf(boldData),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> generateAnswerSheetPdf({
    required FormTemplate template,
    required String quizTitle,
    required String subjectName,
    String subjectCode = '33101',
    String instructions = '',
    List<EssayQuestion> essayQuestions = const [],
    Uint8List? customLogoBytes,
  }) async {
    final theme = await _loadThaiTheme();
    final pdf = pw.Document(theme: theme);
    final pw.MemoryImage? customLogo =
        customLogoBytes != null ? pw.MemoryImage(customLogoBytes) : null;
    final idGrid = template.getIdentityBubbles();
    final questionGrid = template.getQuestionBubbles();

    final double scaleX = PdfPageFormat.a4.width / FormTemplate.canonicalWidth;
    final double scaleY = PdfPageFormat.a4.height / FormTemplate.canonicalHeight;
    final double omrHeightPt = template.omrZoneBottomY * scaleY;
    final int totalEssayPoints =
        essayQuestions.fold(0, (sum, q) => sum + q.maxScore);
    final int perStrip = template.sheetSize.questionsPerStrip;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          double toPdfY(double y) => PdfPageFormat.a4.height - (y * scaleY);

          return pw.Stack(
            children: [
              // Layer 1: Vector OMR Zone (บน)
              pw.CustomPaint(
                size: PdfPoint(PdfPageFormat.a4.width, PdfPageFormat.a4.height),
                painter: (PdfGraphics canvas, PdfPoint size) {
                  // 1. 4 Corner Fiducial Markers (ล้อมเฉพาะโซนปรนัยด้านบน)
                  canvas.setFillColor(PdfColors.black);
                  const double m = FormTemplate.margin;
                  const double f = FormTemplate.fiducialSize;
                  const double w = FormTemplate.canonicalWidth;
                  final double omrBottom = template.omrZoneBottomY;

                  for (final c in [
                    [m, m],
                    [w - m - f, m],
                    [w - m - f, omrBottom - f],
                    [m, omrBottom - f],
                  ]) {
                    canvas.drawRect(
                      c[0] * scaleX,
                      toPdfY(c[1] + f),
                      f * scaleX,
                      f * scaleY,
                    );
                    canvas.fillPath();
                  }

                  // 2. กรอบหัวกระดาษฝั่งซ้าย + กรอบรหัส 3 ส่วนฝั่งขวา (รหัสวิชา, ชั้น/ห้อง, เลขที่)
                  canvas.setStrokeColor(PdfColors.grey800);
                  canvas.setLineWidth(1.0);
                  canvas.drawRect(
                      92 * scaleX, toPdfY(376), 396 * scaleX, 286 * scaleY);
                  canvas.strokePath();
                  canvas.drawRect(
                      502 * scaleX, toPdfY(376), 386 * scaleX, 286 * scaleY);
                  canvas.strokePath();

                  // กรอบย่อยแยกส่วน: รหัสวิชา (5), ชั้น/ห้อง (2), เลขที่ (2)
                  canvas.setStrokeColor(PdfColors.grey700);
                  canvas.setLineWidth(0.85);
                  for (final sec in const [
                    [514.0, 184.0],
                    [713.0, 73.0],
                    [801.0, 73.0],
                  ]) {
                    canvas.drawRect(
                        sec[0] * scaleX, toPdfY(370), sec[1] * scaleX, 272 * scaleY);
                    canvas.strokePath();
                    canvas.drawLine(
                      sec[0] * scaleX,
                      toPdfY(126),
                      (sec[0] + sec[1]) * scaleX,
                      toPdfY(126),
                    );
                    canvas.strokePath();
                  }

                  // 3. วงกลมรหัสอ้างอิง 9 หลัก (วิชา 5 + ชั้น/ห้อง 2 + เลขที่ 2)
                  canvas.setStrokeColor(PdfColors.grey800);
                  canvas.setLineWidth(1.0);
                  for (final col in idGrid) {
                    for (final bubble in col) {
                      canvas.drawEllipse(
                        bubble.x * scaleX,
                        toPdfY(bubble.y),
                        bubble.radius * scaleX,
                        bubble.radius * scaleY,
                      );
                      canvas.strokePath();
                    }
                  }

                  // 4. วงกลมคำตอบแนวนอนแบบที่ 2 (20 / 30 / 40 / 50 ข้อ)
                  for (final qRow in questionGrid) {
                    for (final b in qRow) {
                      canvas.drawEllipse(
                        b.x * scaleX,
                        toPdfY(b.y),
                        b.radius * scaleX,
                        b.radius * scaleY,
                      );
                      canvas.strokePath();
                    }
                  }

                  // 5. เส้นคั่นทุกๆ 5 ข้อในแต่ละแถบ กันตาลาย
                  canvas.setStrokeColor(PdfColors.grey500);
                  canvas.setLineWidth(0.75);
                  for (int qIdx = 0; qIdx + 1 < questionGrid.length; qIdx++) {
                    final int colInStrip = qIdx % perStrip;
                    if (colInStrip % 5 == 4 && colInStrip + 1 < perStrip) {
                      final double midX = (questionGrid[qIdx].first.x +
                              questionGrid[qIdx + 1].first.x) /
                          2.0;
                      final double topY = questionGrid[qIdx].first.y - 24.0;
                      final double bottomY = questionGrid[qIdx].last.y +
                          questionGrid[qIdx].last.radius +
                          4.0;
                      canvas.drawLine(
                        midX * scaleX,
                        toPdfY(topY),
                        midX * scaleX,
                        toPdfY(bottomY),
                      );
                      canvas.strokePath();
                    }
                  }
                },
              ),

              // Layer 1.5: ข้อความหัวกระดาษ + โลโก้ผู้ใช้ (ถ้ามี) + คำชี้แจง 3 บรรทัด
              pw.Positioned(
                left: 102 * scaleX,
                top: 96 * scaleY,
                child: pw.SizedBox(
                  width: 376 * scaleX,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (customLogo != null)
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Container(
                              width: 32,
                              height: 32,
                              child: pw.Image(
                                customLogo,
                                fit: pw.BoxFit.contain,
                              ),
                            ),
                            pw.SizedBox(width: 8),
                            pw.Expanded(
                              child: pw.Text(
                                quizTitle,
                                maxLines: 2,
                                style: pw.TextStyle(
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold),
                              ),
                            ),
                          ],
                        )
                      else
                        pw.Text(
                          quizTitle,
                          maxLines: 2,
                          style: pw.TextStyle(
                              fontSize: 11.5, fontWeight: pw.FontWeight.bold),
                        ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'ชื่อ-สกุล: ___________________________________',
                        style: const pw.TextStyle(fontSize: 9.2),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'วิชา: $subjectName ($subjectCode)',
                        maxLines: 1,
                        style: const pw.TextStyle(fontSize: 8.8),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'ห้อง: ม.___/___   เลขที่: ___',
                        style: const pw.TextStyle(fontSize: 8.8),
                      ),
                      if (instructions.trim().isNotEmpty) ...[
                        pw.SizedBox(height: 5),
                        pw.Container(height: 0.6, color: PdfColors.grey300),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          instructions.trim(),
                          maxLines: 3,
                          style: const pw.TextStyle(
                            fontSize: 8.0,
                            color: PdfColors.grey800,
                            lineSpacing: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Label หัวกรอบย่อย 3 ส่วน (รหัสวิชา, ชั้น/ห้อง, เลขที่)
              pw.Positioned(
                left: 514 * scaleX,
                top: 100 * scaleY,
                child: pw.SizedBox(
                  width: 184 * scaleX,
                  child: pw.Center(
                    child: pw.Text(
                      'รหัสวิชา (5)',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
              ),
              pw.Positioned(
                left: 713 * scaleX,
                top: 100 * scaleY,
                child: pw.SizedBox(
                  width: 73 * scaleX,
                  child: pw.Center(
                    child: pw.Text(
                      'ชั้น/ห้อง',
                      style: pw.TextStyle(
                          fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
              ),
              pw.Positioned(
                left: 801 * scaleX,
                top: 100 * scaleY,
                child: pw.SizedBox(
                  width: 73 * scaleX,
                  child: pw.Center(
                    child: pw.Text(
                      'เลขที่',
                      style: pw.TextStyle(
                          fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
              ),

              // ตัวเลขข้อเหนือแต่ละคอลัมน์ในแถบแนวนอน
              for (int qIdx = 0; qIdx < questionGrid.length; qIdx++)
                pw.Positioned(
                  left: (questionGrid[qIdx].first.x - 10) * scaleX,
                  top: (questionGrid[qIdx].first.y - 24) * scaleY,
                  child: pw.SizedBox(
                    width: 20 * scaleX,
                    child: pw.Center(
                      child: pw.Text(
                        '${qIdx + 1}',
                        style: pw.TextStyle(
                          fontSize: perStrip >= 25 ? 6.5 : 7.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

              // ตัวอักษรตัวเลือก (ก ข ค ง / A B C D) ด้านซ้ายของแต่ละแถบ
              for (int strip = 0; strip < template.sheetSize.strips; strip++)
                for (int cIdx = 0; cIdx < template.choicesCount; cIdx++)
                  pw.Positioned(
                    left: 102 * scaleX,
                    top: (questionGrid[strip * perStrip][cIdx].y - 6) * scaleY,
                    child: pw.Text(
                      template.choiceLabels[cIdx],
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),

              // Layer 2: ตอนที่ 2 ข้อสอบอัตนัย (ข้อความคำถามจริง + เส้นบรรทัด)
              pw.Positioned(
                top: omrHeightPt + 10,
                left: 26,
                right: 26,
                bottom: 24,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Divider(color: PdfColors.grey500, thickness: 0.8),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            'ตอนที่ 2: ข้อสอบอัตนัย — $subjectName ($subjectCode)',
                            style: pw.TextStyle(
                              fontSize: 10.5,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey700),
                          ),
                          child: pw.Text(
                            'คะแนนอัตนัย: _____ / $totalEssayPoints',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    if (essayQuestions.isEmpty)
                      ...List.generate(
                        8,
                        (_) => pw.Container(
                          height: 24,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                  color: PdfColors.grey400, width: 0.6),
                            ),
                          ),
                        ),
                      )
                    else
                      ...essayQuestions.asMap().entries.map((entry) {
                        final idx = entry.key + 1;
                        final q = entry.value;
                        return pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 6),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                '$idx. ${q.prompt} (${q.maxScore} คะแนน)',
                                style: pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              ...List.generate(
                                q.linesCount,
                                (_) => pw.Container(
                                  height: 17,
                                  decoration: const pw.BoxDecoration(
                                    border: pw.Border(
                                      bottom: pw.BorderSide(
                                        color: PdfColors.grey400,
                                        width: 0.6,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
