import '../models/account.dart';
import 'api_client.dart';

/// كود ربط مؤقت يولّده الطالب.
class LinkCode {
  final String code;
  final DateTime expiresAt;
  final int ttlMinutes;

  const LinkCode({
    required this.code,
    required this.expiresAt,
    required this.ttlMinutes,
  });

  /// الوقت المتبقي قبل انتهاء الكود.
  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isExpired => remaining == Duration.zero;

  /// عرض الكود مقسّم (123 456) عشان يبقى أسهل في القراءة والنطق.
  String get formatted =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

  factory LinkCode.fromJson(Map<String, dynamic> json) => LinkCode(
        code: json['code'] as String? ?? '',
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ??
            DateTime.now(),
        ttlMinutes: json['ttl_minutes'] as int? ?? 15,
      );
}

/// ربط ولي أمر بطالب كما يرجّعه السيرفر.
class GuardianLinkSummary {
  final int id;
  final LinkStatus status;
  final GuardianRelation relation;
  final String guardianName;
  final String studentName;
  final DateTime createdAt;

  const GuardianLinkSummary({
    required this.id,
    required this.status,
    required this.relation,
    required this.guardianName,
    required this.studentName,
    required this.createdAt,
  });

  bool get isPending => status == LinkStatus.pending;
  bool get isActive => status == LinkStatus.accepted;

  factory GuardianLinkSummary.fromJson(Map<String, dynamic> json) =>
      GuardianLinkSummary(
        id: json['id'] as int? ?? 0,
        status: LinkStatus.fromId(json['status'] as String?),
        relation: GuardianRelation.fromId(json['relation'] as String?),
        guardianName: json['guardian_name'] as String? ?? '',
        studentName: json['student_name'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// عمليات ربط ولي الأمر بالطالب.
///
/// آلية الربط: الطالب بيولّد كود قصير ويدّيه لولي أمره، ولي الأمر بيدخّله
/// فيتبعت طلب، والطالب لازم يوافق. كده محدش يقدر يربط نفسه بطالب من غير
/// علمه، والطالب يقدر يفك الربط في أي وقت.
class GuardianService {
  final ApiClient _api;

  const GuardianService(this._api);

  /// الطالب: يولّد كود جديد (بيلغي أي كود قديم لسه صالح).
  Future<LinkCode> generateCode() async {
    final data = await _api.post('/api/v1/link-codes');
    return LinkCode.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// ولي الأمر: يدخّل الكود ويطلب الربط.
  Future<GuardianLinkSummary> redeemCode({
    required String code,
    required GuardianRelation relation,
  }) async {
    final data = await _api.post(
      '/api/v1/links/redeem',
      body: {'code': code.replaceAll(' ', ''), 'relation': relation.id},
    );
    return GuardianLinkSummary.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// كل الروابط اللي الحساب طرف فيها.
  Future<List<GuardianLinkSummary>> myLinks() async {
    final data = await _api.get('/api/v1/links');
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) =>
            GuardianLinkSummary.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  /// الطالب: يوافق أو يرفض، ويحدد الصلاحيات المسموحة.
  Future<GuardianLinkSummary> respond({
    required int linkId,
    required bool accept,
    GuardianPermissions? permissions,
  }) async {
    final data = await _api.post(
      '/api/v1/links/$linkId/respond?accept=$accept',
      body: permissions?.toJson(),
    );
    return GuardianLinkSummary.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// أي طرف يقدر يفك الربط.
  Future<void> revoke(int linkId) => _api.delete('/api/v1/links/$linkId');
}
