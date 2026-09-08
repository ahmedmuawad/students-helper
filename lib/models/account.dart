/// دور الحساب في التطبيق.
enum AccountRole {
  /// الطالب — صاحب البيانات الأساسي.
  student,

  /// ولي الأمر — بيتابع أولاده بصلاحيات محدودة.
  guardian,

  /// المدرس — بيرفع المناهج والمهام لطلابه.
  teacher;

  String get id => name;

  static AccountRole fromId(String? id) => AccountRole.values.firstWhere(
        (e) => e.name == id,
        orElse: () => AccountRole.student,
      );
}

/// صلة القرابة بين ولي الأمر والطالب.
enum GuardianRelation {
  father,
  mother,
  brother,
  sister,
  other;

  String get id => name;

  static GuardianRelation fromId(String? id) => GuardianRelation.values
      .firstWhere((e) => e.name == id, orElse: () => GuardianRelation.other);
}

/// حالة طلب الربط بين ولي الأمر والطالب.
enum LinkStatus {
  /// الطلب اتبعت والطالب لسه ما وافقش.
  pending,

  /// الطالب وافق والربط شغّال.
  accepted,

  /// الطالب رفض الطلب.
  rejected,

  /// الربط اتفك بعد ما كان شغّال.
  revoked;

  String get id => name;

  static LinkStatus fromId(String? id) => LinkStatus.values.firstWhere(
        (e) => e.name == id,
        orElse: () => LinkStatus.pending,
      );
}

/// الصلاحيات اللي ولي الأمر يقدر يشوفها عن الطالب.
///
/// كل صلاحية منفصلة عشان الطالب (أو ولي الأمر حسب سن الطالب) يقدر يتحكم
/// في اللي بيتشاف — ده مهم جدًا مع طلاب المرحلة الثانوية.
class GuardianPermissions {
  final bool viewTimetable;
  final bool viewLessons;
  final bool viewTasks;
  final bool viewGrades;
  final bool viewAttendance;
  final bool viewStudyStats;

  /// متابعة مصاريف الدروس الخصوصية.
  final bool viewLessonCosts;

  /// استقبال إشعار لما مهمة تتأخر أو امتحان يقرب.
  final bool receiveAlerts;

  /// إضافة مهام للطالب (مش بس المشاهدة).
  final bool canAssignTasks;

  const GuardianPermissions({
    this.viewTimetable = true,
    this.viewLessons = true,
    this.viewTasks = true,
    this.viewGrades = true,
    this.viewAttendance = true,
    this.viewStudyStats = false,
    this.viewLessonCosts = true,
    this.receiveAlerts = true,
    this.canAssignTasks = false,
  });

  /// الحد الأدنى: متابعة بدون تفاصيل شخصية.
  static const GuardianPermissions minimal = GuardianPermissions(
    viewTimetable: true,
    viewLessons: true,
    viewTasks: false,
    viewGrades: false,
    viewAttendance: true,
    viewStudyStats: false,
    viewLessonCosts: true,
    receiveAlerts: true,
    canAssignTasks: false,
  );

  GuardianPermissions copyWith({
    bool? viewTimetable,
    bool? viewLessons,
    bool? viewTasks,
    bool? viewGrades,
    bool? viewAttendance,
    bool? viewStudyStats,
    bool? viewLessonCosts,
    bool? receiveAlerts,
    bool? canAssignTasks,
  }) {
    return GuardianPermissions(
      viewTimetable: viewTimetable ?? this.viewTimetable,
      viewLessons: viewLessons ?? this.viewLessons,
      viewTasks: viewTasks ?? this.viewTasks,
      viewGrades: viewGrades ?? this.viewGrades,
      viewAttendance: viewAttendance ?? this.viewAttendance,
      viewStudyStats: viewStudyStats ?? this.viewStudyStats,
      viewLessonCosts: viewLessonCosts ?? this.viewLessonCosts,
      receiveAlerts: receiveAlerts ?? this.receiveAlerts,
      canAssignTasks: canAssignTasks ?? this.canAssignTasks,
    );
  }

  Map<String, dynamic> toJson() => {
        'viewTimetable': viewTimetable,
        'viewLessons': viewLessons,
        'viewTasks': viewTasks,
        'viewGrades': viewGrades,
        'viewAttendance': viewAttendance,
        'viewStudyStats': viewStudyStats,
        'viewLessonCosts': viewLessonCosts,
        'receiveAlerts': receiveAlerts,
        'canAssignTasks': canAssignTasks,
      };

  factory GuardianPermissions.fromJson(Map<String, dynamic> json) =>
      GuardianPermissions(
        viewTimetable: json['viewTimetable'] as bool? ?? true,
        viewLessons: json['viewLessons'] as bool? ?? true,
        viewTasks: json['viewTasks'] as bool? ?? true,
        viewGrades: json['viewGrades'] as bool? ?? true,
        viewAttendance: json['viewAttendance'] as bool? ?? true,
        viewStudyStats: json['viewStudyStats'] as bool? ?? false,
        viewLessonCosts: json['viewLessonCosts'] as bool? ?? true,
        receiveAlerts: json['receiveAlerts'] as bool? ?? true,
        canAssignTasks: json['canAssignTasks'] as bool? ?? false,
      );
}

/// ربط بين حساب ولي أمر وحساب طالب.
///
/// الربط بيتعمل بكود مؤقت الطالب بيولّده ويدّيه لولي أمره — وولي الأمر
/// بيدخّله عشان يطلب الربط، والطالب بيوافق. كده محدش يقدر يربط نفسه
/// بطالب من غير علمه.
class GuardianLink {
  final String id;

  /// معرّف حساب ولي الأمر (Firebase UID).
  final String guardianUid;

  final String guardianName;

  /// معرّف الطالب.
  final String studentId;

  final String studentName;

  final GuardianRelation relation;
  final LinkStatus status;
  final GuardianPermissions permissions;

  final DateTime createdAt;
  final DateTime? respondedAt;

  const GuardianLink({
    required this.id,
    required this.guardianUid,
    this.guardianName = '',
    required this.studentId,
    this.studentName = '',
    this.relation = GuardianRelation.other,
    this.status = LinkStatus.pending,
    this.permissions = const GuardianPermissions(),
    required this.createdAt,
    this.respondedAt,
  });

  bool get isActive => status == LinkStatus.accepted;

  GuardianLink copyWith({
    String? guardianName,
    String? studentName,
    GuardianRelation? relation,
    LinkStatus? status,
    GuardianPermissions? permissions,
    DateTime? respondedAt,
  }) {
    return GuardianLink(
      id: id,
      guardianUid: guardianUid,
      guardianName: guardianName ?? this.guardianName,
      studentId: studentId,
      studentName: studentName ?? this.studentName,
      relation: relation ?? this.relation,
      status: status ?? this.status,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'guardianUid': guardianUid,
        'guardianName': guardianName,
        'studentId': studentId,
        'studentName': studentName,
        'relation': relation.name,
        'status': status.name,
        'permissions': permissions.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'respondedAt': respondedAt?.toIso8601String(),
      };

  factory GuardianLink.fromJson(Map<String, dynamic> json) => GuardianLink(
        id: json['id'] as String,
        guardianUid: json['guardianUid'] as String? ?? '',
        guardianName: json['guardianName'] as String? ?? '',
        studentId: json['studentId'] as String? ?? '',
        studentName: json['studentName'] as String? ?? '',
        relation: GuardianRelation.fromId(json['relation'] as String?),
        status: LinkStatus.fromId(json['status'] as String?),
        permissions: json['permissions'] == null
            ? const GuardianPermissions()
            : GuardianPermissions.fromJson(
                Map<String, dynamic>.from(json['permissions'] as Map),
              ),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        respondedAt: json['respondedAt'] == null
            ? null
            : DateTime.tryParse(json['respondedAt'] as String),
      );
}
