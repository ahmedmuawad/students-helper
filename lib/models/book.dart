/// تصنيف المادة التعليمية.
enum BookKind {
  /// كتاب الوزارة.
  textbook,

  /// كتاب الأنشطة.
  workbook,

  /// ملزمة.
  booklet,

  /// مراجعة نهائية.
  revision,

  /// نماذج امتحانات.
  exam,

  /// دليل المعلم.
  teacherGuide,

  other;

  String get id {
    // السيرفر بيستخدم snake_case
    if (this == BookKind.teacherGuide) return 'teacher_guide';
    return name;
  }

  static BookKind fromId(String? id) {
    if (id == 'teacher_guide') return BookKind.teacherGuide;
    return BookKind.values.firstWhere(
      (e) => e.name == id,
      orElse: () => BookKind.other,
    );
  }

  String get labelAr {
    switch (this) {
      case BookKind.textbook:
        return 'كتاب الوزارة';
      case BookKind.workbook:
        return 'كتاب الأنشطة';
      case BookKind.booklet:
        return 'ملزمة';
      case BookKind.revision:
        return 'مراجعة';
      case BookKind.exam:
        return 'امتحانات';
      case BookKind.teacherGuide:
        return 'دليل المعلم';
      case BookKind.other:
        return 'أخرى';
    }
  }

  String get labelEn {
    switch (this) {
      case BookKind.textbook:
        return 'Textbook';
      case BookKind.workbook:
        return 'Workbook';
      case BookKind.booklet:
        return 'Booklet';
      case BookKind.revision:
        return 'Revision';
      case BookKind.exam:
        return 'Exams';
      case BookKind.teacherGuide:
        return "Teacher's guide";
      case BookKind.other:
        return 'Other';
    }
  }
}

/// كتاب أو ملزمة متاحة للطالب.
class Book {
  final int id;
  final String titleAr;
  final String titleEn;
  final BookKind kind;
  final int term;
  final String publisher;

  final String subjectId;
  final String subjectNameAr;

  /// لون المادة بصيغة #RRGGBB.
  final String subjectColor;

  final int pageCount;
  final int fileSize;

  /// مسار الملف على السيرفر (نسبي).
  final String fileUrl;

  /// مصدر الملف الأصلي وملاحظة الحقوق — بيتعرضوا للطالب في تفاصيل الكتاب.
  final String sourceUrl;
  final String licenseNote;

  const Book({
    required this.id,
    required this.titleAr,
    this.titleEn = '',
    this.kind = BookKind.textbook,
    this.term = 1,
    this.publisher = '',
    this.subjectId = '',
    this.subjectNameAr = '',
    this.subjectColor = '#2E7D91',
    this.pageCount = 0,
    this.fileSize = 0,
    required this.fileUrl,
    this.sourceUrl = '',
    this.licenseNote = '',
  });

  String localizedTitle(String languageCode) =>
      (languageCode == 'en' && titleEn.isNotEmpty) ? titleEn : titleAr;

  /// حجم الملف بصيغة مقروءة.
  String get sizeLabel {
    if (fileSize <= 0) return '';
    final megabytes = fileSize / (1024 * 1024);
    if (megabytes < 1) return '${(fileSize / 1024).round()} كيلو';
    return '${megabytes.toStringAsFixed(1)} ميجا';
  }

  /// لون المادة كقيمة ARGB.
  int get colorValue {
    final hex = subjectColor.replaceAll('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return 0xFF2E7D91;
    return hex.length == 6 ? (0xFF000000 | parsed) : parsed;
  }

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as int? ?? 0,
        titleAr: json['title_ar'] as String? ?? '',
        titleEn: json['title_en'] as String? ?? '',
        kind: BookKind.fromId(json['kind'] as String?),
        term: json['term'] as int? ?? 1,
        publisher: json['publisher'] as String? ?? '',
        subjectId: json['subject_id'] as String? ?? '',
        subjectNameAr: json['subject_name_ar'] as String? ?? '',
        subjectColor: json['subject_color'] as String? ?? '#2E7D91',
        pageCount: json['page_count'] as int? ?? 0,
        fileSize: json['file_size'] as int? ?? 0,
        fileUrl: json['file_url'] as String? ?? '',
        sourceUrl: json['source_url'] as String? ?? '',
        licenseNote: json['license_note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title_ar': titleAr,
        'title_en': titleEn,
        'kind': kind.id,
        'term': term,
        'publisher': publisher,
        'subject_id': subjectId,
        'subject_name_ar': subjectNameAr,
        'subject_color': subjectColor,
        'page_count': pageCount,
        'file_size': fileSize,
        'file_url': fileUrl,
        'source_url': sourceUrl,
        'license_note': licenseNote,
      };
}

/// حالة تحميل كتاب على الجهاز.
class BookDownload {
  final int bookId;

  /// مسار الملف المحلي بعد التحميل.
  final String filePath;

  final DateTime downloadedAt;
  final int fileSize;

  const BookDownload({
    required this.bookId,
    required this.filePath,
    required this.downloadedAt,
    this.fileSize = 0,
  });

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'filePath': filePath,
        'downloadedAt': downloadedAt.toIso8601String(),
        'fileSize': fileSize,
      };

  factory BookDownload.fromJson(Map<String, dynamic> json) => BookDownload(
        bookId: json['bookId'] as int? ?? 0,
        filePath: json['filePath'] as String? ?? '',
        downloadedAt:
            DateTime.tryParse(json['downloadedAt'] as String? ?? '') ??
                DateTime.now(),
        fileSize: json['fileSize'] as int? ?? 0,
      );
}
