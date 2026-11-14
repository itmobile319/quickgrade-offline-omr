import 'dart:math';
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../models/form_template.dart';
import '../models/quiz_models.dart';

class OmrScanOutput {
  final String studentId;
  final int score;
  final List<QuestionGrade> grades;
  final Uint8List? annotatedPngBytes;

  const OmrScanOutput({
    required this.studentId,
    required this.score,
    required this.grades,
    this.annotatedPngBytes,
  });
}

/// เครื่องมือประมวลผลภาพ OMR แบบ Offline ด้วย OpenCV (opencv_dart)
class OmrScannerEngine {
  /// ค่าสัดส่วนความเข้มของพิกเซลขั้นต่ำที่ถือว่าวงกลมนั้นถูกระบาย (42%)
  static const double fillThreshold = 0.42;

  /// ประมวลผลภาพถ่ายกระดาษคำตอบ 1 แผ่น
  static OmrScanOutput? processFrame({
    required Uint8List imageBytes,
    required FormTemplate template,
    required List<int> answerKey,
  }) {
    final cv.Mat src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
    if (src.isEmpty) return null;

    // 1. แปลงเป็น Grayscale และลด Noise
    final cv.Mat gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
    final cv.Mat blurred = cv.gaussianBlur(gray, (5, 5), 0);

    // 2. Adaptive Thresholding เพื่อแยกหมึก/ดินสอออกจากเงาแสงในห้องเรียน
    final cv.Mat thresh = cv.adaptiveThreshold(
      blurred,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY_INV,
      31,
      10,
    );

    // 3. ค้นหา Fiducial Markers สี่เหลี่ยมดำทั้ง 4 มุม
    final corners = _detectFourCornerFiducials(thresh, src.cols, src.rows);
    if (corners == null) {
      src.dispose();
      gray.dispose();
      blurred.dispose();
      thresh.dispose();
      return null;
    }

    // 4. ทำ Perspective Transform ดัดภาพให้ตรงขนาด 1000 x omrZoneBottomY
    final dstPoints = template.cornerCenters
        .map((p) => cv.Point(p.x.round(), p.y.round()))
        .toList();
    final srcPoints =
        corners.map((p) => cv.Point(p.x.round(), p.y.round())).toList();

    final srcVec = cv.VecPoint.fromList(srcPoints);
    final dstVec = cv.VecPoint.fromList(dstPoints);
    final cv.Mat homography = cv.getPerspectiveTransform(srcVec, dstVec);

    // ดัดภาพเฉพาะโซน OMR ด้านบน (กว้าง 1000 x สูง omrZoneBottomY)
    final (int w, int h) = (
      FormTemplate.canonicalWidth.toInt(),
      template.omrZoneBottomY.ceil(),
    );
    final cv.Mat warpedColor = cv.warpPerspective(src, homography, (w, h));
    final cv.Mat warpedThresh = cv.warpPerspective(thresh, homography, (w, h));

    // 5. อ่านรหัสอ้างอิงตัวตน 9 หลัก (วิชา 5 + ชั้น/ห้อง 2 + เลขที่ 2 เช่น 331013109)
    final String studentId = _readIdentityCode(warpedThresh, template);

    // 6. อ่านวงกลมคำตอบทุกข้อ (20 / 30 / 40 / 50 ข้อ) และตรวจเทียบเฉลย
    final questionGrid = template.getQuestionBubbles();
    final List<QuestionGrade> grades = [];
    int score = 0;

    for (int q = 0; q < questionGrid.length; q++) {
      final rowBubbles = questionGrid[q];
      final List<double> ratios = [];
      final List<int> markedIndices = [];

      for (int c = 0; c < rowBubbles.length; c++) {
        final double ratio = _measureBubbleFillRatio(warpedThresh, rowBubbles[c]);
        ratios.add(ratio);
        if (ratio >= fillThreshold) {
          markedIndices.add(c);
        }
      }

      final int correctChoice = q < answerKey.length ? answerKey[q] : 0;
      int? selectedChoice;
      MarkStatus status;

      if (markedIndices.isEmpty) {
        status = MarkStatus.blank;
      } else if (markedIndices.length > 1) {
        status = MarkStatus.multipleMarks;
        selectedChoice = markedIndices.first;
      } else {
        selectedChoice = markedIndices.first;
        if (selectedChoice == correctChoice) {
          status = MarkStatus.correct;
          score++;
        } else {
          status = MarkStatus.incorrect;
        }
      }

      grades.add(QuestionGrade(
        questionNumber: q + 1,
        selectedChoice: selectedChoice,
        correctChoice: correctChoice,
        status: status,
        fillRatios: ratios,
      ));

      // 7. วาด Overlay สีเขียว (ถูก) / สีแดง (ผิด) / สีเหลือง (เฉลย) ลงบนภาพ
      _drawOverlayForQuestion(
        warpedColor,
        rowBubbles,
        selectedChoice,
        correctChoice,
        status,
      );
    }

    final (_, Uint8List encodedPng) = cv.imencode('.png', warpedColor);

    srcVec.dispose();
    dstVec.dispose();
    homography.dispose();
    src.dispose();
    gray.dispose();
    blurred.dispose();
    thresh.dispose();
    warpedColor.dispose();
    warpedThresh.dispose();

    return OmrScanOutput(
      studentId: studentId,
      score: score,
      grades: grades,
      annotatedPngBytes: encodedPng,
    );
  }

  /// ตรวจหาจุดศูนย์กลางของสี่เหลี่ยม Fiducial 4 มุม (TL, TR, BR, BL)
  static List<Point<double>>? _detectFourCornerFiducials(
    cv.Mat thresh,
    int width,
    int height,
  ) {
    final (contours, _) = cv.findContours(
      thresh,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );

    final List<Point<double>> candidates = [];
    for (final contour in contours) {
      final double area = cv.contourArea(contour);
      if (area < 150 || area > (width * height * 0.05)) continue;

      final double peri = cv.arcLength(contour, true);
      final approx = cv.approxPolyDP(contour, 0.04 * peri, true);
      if (approx.length == 4) {
        final rect = cv.boundingRect(approx);
        final double aspect = rect.width / max(1, rect.height);
        if (aspect >= 0.7 && aspect <= 1.35) {
          candidates.add(Point(
            rect.x + rect.width / 2.0,
            rect.y + rect.height / 2.0,
          ));
        }
      }
    }

    if (candidates.length < 4) return null;

    // จัดกลุ่ม 4 มุมด้วยผลบวกและผลต่างของพิกัด (x+y, x-y)
    candidates.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final Point<double> topLeft = candidates.first;
    final Point<double> bottomRight = candidates.last;

    candidates.sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
    final Point<double> topRight = candidates.first;
    final Point<double> bottomLeft = candidates.last;

    return [topLeft, topRight, bottomRight, bottomLeft];
  }

  /// คำนวณความหนาแน่นของพิกเซลสีดำภายในกรอบวงกลม
  static double _measureBubbleFillRatio(cv.Mat warpedThresh, BubbleCoord b) {
    final int r = (b.radius * 0.78).round();
    final int x0 = (b.x.round() - r).clamp(0, warpedThresh.cols - 1);
    final int y0 = (b.y.round() - r).clamp(0, warpedThresh.rows - 1);
    final int w = min(r * 2, warpedThresh.cols - x0);
    final int h = min(r * 2, warpedThresh.rows - y0);

    if (w <= 0 || h <= 0) return 0.0;
    final cv.Mat roi = warpedThresh.region(cv.Rect(x0, y0, w, h));
    final int nonZero = cv.countNonZero(roi);
    roi.dispose();
    return nonZero / (w * h);
  }

  /// อ่านรหัสอ้างอิงตัวตน 9 หลัก (รหัสวิชา 5 + ชั้น/ห้อง 2 + เลขที่ 2)
  static String _readIdentityCode(cv.Mat warpedThresh, FormTemplate template) {
    final idGrid = template.getIdentityBubbles();
    final StringBuffer buffer = StringBuffer();

    for (final colBubbles in idGrid) {
      int bestDigit = -1;
      double maxRatio = 0.35;
      for (int digit = 0; digit < colBubbles.length; digit++) {
        final double ratio = _measureBubbleFillRatio(warpedThresh, colBubbles[digit]);
        if (ratio > maxRatio) {
          maxRatio = ratio;
          bestDigit = digit;
        }
      }
      buffer.write(bestDigit >= 0 ? bestDigit.toString() : '0');
    }
    return buffer.toString();
  }

  /// วาดวงกลมสีเขียว/แดง/เหลือง ทับภาพที่ตรวจแล้วเหมือน ZipGrade
  static void _drawOverlayForQuestion(
    cv.Mat canvas,
    List<BubbleCoord> rowBubbles,
    int? selected,
    int correct,
    MarkStatus status,
  ) {
    final correctBubble = rowBubbles[correct];
    if (status == MarkStatus.correct) {
      // สีเขียว: ตอบถูก
      cv.circle(
        canvas,
        cv.Point(correctBubble.x.round(), correctBubble.y.round()),
        correctBubble.radius.round() + 3,
        cv.Scalar(40, 200, 40, 255),
        thickness: 3,
      );
    } else {
      // สีเหลือง/ฟ้า: วงตำแหน่งคำตอบที่ถูกต้อง
      cv.circle(
        canvas,
        cv.Point(correctBubble.x.round(), correctBubble.y.round()),
        correctBubble.radius.round() + 3,
        cv.Scalar(0, 195, 255, 255),
        thickness: 3,
      );
      // สีแดง: วงตำแหน่งที่นักเรียนฝนผิด
      if (selected != null && selected < rowBubbles.length) {
        final wrongBubble = rowBubbles[selected];
        cv.circle(
          canvas,
          cv.Point(wrongBubble.x.round(), wrongBubble.y.round()),
          wrongBubble.radius.round() + 3,
          cv.Scalar(40, 40, 235, 255),
          thickness: 3,
        );
      }
    }
  }
}
