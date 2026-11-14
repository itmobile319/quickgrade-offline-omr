import 'dart:math';

/// ขนาดกระดาษคำตอบแบบแนวนอน (Transposed Grid) + เผื่อพื้นที่อัตนัยด้านล่าง
enum SheetSize {
  q20(20, '20 ข้อ (1 แถบ x 20 ข้อ)', 1, 20),
  q30(30, '30 ข้อ (2 แถบ x 15 ข้อ)', 2, 15),
  q40(40, '40 ข้อ (2 แถบ x 20 ข้อ)', 2, 20),
  q50(50, '50 ข้อ (2 แถบ x 25 ข้อ)', 2, 25);

  final int questionCount;
  final String label;
  final int strips; // จำนวนแถบแนวนอน (1 หรือ 2 แถบ)
  final int questionsPerStrip; // จำนวนข้อต่อ 1 แถบแนวนอน

  const SheetSize(
    this.questionCount,
    this.label,
    this.strips,
    this.questionsPerStrip,
  );
}

/// ข้อมูลตัวตนที่ถอดรหัสจากเลข 9 หลัก (เช่น 331013109)
class StudentIdentity {
  final String fullCode; // 331013109
  final String subjectCode; // 33101 (5 หลัก)
  final String grade; // 3 (1 หลัก)
  final String room; // 1 (1 หลัก)
  final String studentNumber; // 09 (2 หลัก)

  const StudentIdentity({
    required this.fullCode,
    required this.subjectCode,
    required this.grade,
    required this.room,
    required this.studentNumber,
  });

  factory StudentIdentity.fromNineDigits(String code) {
    final normalized = code.padRight(9, '0').substring(0, 9);
    return StudentIdentity(
      fullCode: normalized,
      subjectCode: normalized.substring(0, 5),
      grade: normalized.substring(5, 6),
      room: normalized.substring(6, 7),
      studentNumber: normalized.substring(7, 9),
    );
  }

  String get displayRoom => 'ม.$grade/$room';
}

/// พิกัดของวงกลม 1 ดวง บนระนาบมาตรฐาน 1000 x 1414 (สัดส่วน A4)
class BubbleCoord {
  final double x;
  final double y;
  final double radius;

  const BubbleCoord({
    required this.x,
    required this.y,
    required this.radius,
  });
}

/// โครงสร้างพิกัดกระดาษคำตอบแบบ Hybrid:
/// - โซนบน: หัวกระดาษ + รหัสอ้างอิง 9 หลัก (วิชา 5 + ชั้น/ห้อง 2 + เลขที่ 2) + ช้อยส์แนวนอน (แบบที่ 2)
/// - ล้อมด้วย Fiducial Markers 4 มุม เฉพาะโซนปรนัยด้านบน
/// - โซนล่าง: พื้นที่เขียนข้อสอบอัตนัย / แสดงวิธีทำ (นอกกรอบ OMR)
class FormTemplate {
  static const double canonicalWidth = 1000.0;
  static const double canonicalHeight = 1414.0;
  static const double fiducialSize = 34.0;
  static const double margin = 44.0;

  final SheetSize sheetSize;
  final int choicesCount; // 4 (ก-ง / A-D) หรือ 5 (ก-จ / A-E)
  final List<String> choiceLabels;

  FormTemplate({
    required this.sheetSize,
    this.choicesCount = 4,
    List<String>? choiceLabels,
  }) : choiceLabels = choiceLabels ??
            (choicesCount == 5
                ? const ['ก', 'ข', 'ค', 'ง', 'จ']
                : const ['ก', 'ข', 'ค', 'ง']);

  /// ความสูงของ 1 แถบแนวนอน
  double get stripHeight => choicesCount == 5 ? 185.0 : 160.0;

  /// ตำแหน่ง Y ด้านล่างของโซน OMR (ขึ้นกับ 1 แถบ หรือ 2 แถบ)
  double get omrZoneBottomY {
    const double stripsStartY = 395.0;
    const double stripGap = 18.0;
    final double totalStripsHeight =
        sheetSize.strips * stripHeight + (sheetSize.strips - 1) * stripGap;
    return stripsStartY + totalStripsHeight + 24.0;
  }

  /// จุดศูนย์กลางของ Fiducial Markers 4 มุม (ล้อมเฉพาะโซนปรนัยด้านบน)
  List<Point<double>> get cornerCenters => [
        const Point(margin + fiducialSize / 2, margin + fiducialSize / 2), // TL
        const Point(canonicalWidth - margin - fiducialSize / 2,
            margin + fiducialSize / 2), // TR
        Point(canonicalWidth - margin - fiducialSize / 2,
            omrZoneBottomY - fiducialSize / 2), // BR (ขอบล่างโซนปรนัย)
        Point(margin + fiducialSize / 2,
            omrZoneBottomY - fiducialSize / 2), // BL (ขอบล่างโซนปรนัย)
      ];

  /// พิกัดวงกลมรหัสอ้างอิงตัวตน 9 หลัก:
  /// - หลัก 0..4: รหัสวิชา (5 หลัก เช่น 33101)
  /// - หลัก 5..6: ชั้นและห้อง (2 หลัก เช่น 31 = ม.3/1)
  /// - หลัก 7..8: เลขที่ (2 หลัก เช่น 09 = เลขที่ 9)
  List<List<BubbleCoord>> getIdentityBubbles() {
    const double startY = 152.0;
    const double rowGap = 23.0;
    const double radius = 9.2;

    const List<double> colXs = [
      // รหัสวิชา 5 หลัก
      532.0, 569.0, 606.0, 643.0, 680.0,
      // ชั้น/ห้อง 2 หลัก (เว้นวรรคกลุ่ม 14px)
      731.0, 768.0,
      // เลขที่ 2 หลัก (เว้นวรรคกลุ่ม 14px)
      819.0, 856.0,
    ];

    return List.generate(colXs.length, (col) {
      return List.generate(10, (digit) {
        return BubbleCoord(
          x: colXs[col],
          y: startY + digit * rowGap,
          radius: radius,
        );
      });
    });
  }

  /// พิกัดวงกลมคำตอบแบบที่ 2 (Transposed Horizontal Grid):
  /// เลขข้อเรียงแนวนอนซ้าย->ขวา, ตัวเลือก (ก ข ค ง จ) เรียงแนวตั้งบน->ล่าง
  /// คืนค่าเป็น [questionIndex 0..N-1][choiceIndex 0..choicesCount-1]
  List<List<BubbleCoord>> getQuestionBubbles() {
    const double stripsStartY = 395.0;
    const double stripGap = 18.0;
    const double startX = 148.0;
    const double rowGap = 27.0;

    final int perStrip = sheetSize.questionsPerStrip;
    final double colSpacing =
        perStrip <= 15 ? 46.0 : (perStrip <= 20 ? 35.5 : 29.0);
    final double bubbleRadius =
        perStrip <= 15 ? 11.5 : (perStrip <= 20 ? 10.5 : 9.6);

    return List.generate(sheetSize.questionCount, (qIndex) {
      final int stripIdx = qIndex ~/ perStrip;
      final int colInStrip = qIndex % perStrip;

      // แบ่งช่วงไฟทุกๆ 5 ข้อ เพื่อให้อ่านง่ายไม่หลงแถว
      final double groupOffset = (colInStrip ~/ 5) * 6.0;
      final double cx = startX + colInStrip * colSpacing + groupOffset;
      final double stripTopY = stripsStartY + stripIdx * (stripHeight + stripGap);
      final double firstChoiceY = stripTopY + 38.0;

      return List.generate(choicesCount, (cIndex) {
        return BubbleCoord(
          x: cx,
          y: firstChoiceY + cIndex * rowGap,
          radius: bubbleRadius,
        );
      });
    });
  }
}
