/// نوع مقدّم الدرس.
enum InstructorKind {
  /// مدرس خصوصي.
  teacher,

  /// سنتر تعليمي.
  center,

  /// منصة أو دروس أونلاين.
  online;

  String get id => name;

  static InstructorKind fromId(String? id) => InstructorKind.values
      .firstWhere((e) => e.name == id, orElse: () => InstructorKind.teacher);
}

/// وسيلة تواصل (تليفون / واتساب / رابط).
class ContactMethod {
  /// نوع الوسيلة: phone, whatsapp, telegram, link.
  final String kind;

  /// الرقم أو الرابط.
  final String value;

  /// وصف اختياري: "الخط الأرضي"، "رقم السكرتارية".
  final String label;

  const ContactMethod({
    required this.kind,
    required this.value,
    this.label = '',
  });

  bool get isPhone => kind == 'phone' || kind == 'whatsapp';

  /// الرابط اللي التطبيق بيفتحه عند الضغط.
  String get uri {
    switch (kind) {
      case 'phone':
        return 'tel:${_digitsOnly(value)}';
      case 'whatsapp':
        return 'https://wa.me/${_digitsOnly(value)}';
      case 'telegram':
        return value.startsWith('http')
            ? value
            : 'https://t.me/${value.replaceAll('@', '')}';
      default:
        return value.startsWith('http') ? value : 'https://$value';
    }
  }

  static String _digitsOnly(String input) =>
      input.replaceAll(RegExp(r'[^0-9+]'), '');

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'value': value,
        'label': label,
      };

  factory ContactMethod.fromJson(Map<String, dynamic> json) => ContactMethod(
        kind: json['kind'] as String? ?? 'phone',
        value: json['value'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );
}

/// مدرس خصوصي أو سنتر — بياناته مخزّنة مرة واحدة وبتترّبط بأكتر من درس،
/// عشان الطالب ما يعيدش إدخال العنوان والتليفون مع كل حصة.
class Instructor {
  final String id;
  final String name;
  final InstructorKind kind;

  /// المادة الأساسية اللي بيدرّسها (اختياري).
  final String subjectId;

  /// العنوان بالتفصيل: "٢٧ ش الجمهورية - أمام مسجد النور - الدور ٣".
  final String address;

  /// اسم المنطقة أو المحافظة للفلترة والبحث.
  final String area;

  /// رابط الموقع على الخريطة (Google Maps أو أي رابط).
  final String mapUrl;

  final List<ContactMethod> contacts;

  /// تكلفة الحصة الافتراضية عند هذا المدرس.
  final double sessionCost;

  final String notes;

  const Instructor({
    required this.id,
    required this.name,
    this.kind = InstructorKind.teacher,
    this.subjectId = '',
    this.address = '',
    this.area = '',
    this.mapUrl = '',
    this.contacts = const [],
    this.sessionCost = 0,
    this.notes = '',
  });

  /// أول رقم تليفون متاح (بنستخدمه في زر الاتصال السريع).
  ContactMethod? get primaryPhone {
    for (final contact in contacts) {
      if (contact.kind == 'phone') return contact;
    }
    for (final contact in contacts) {
      if (contact.isPhone) return contact;
    }
    return null;
  }

  ContactMethod? get whatsapp {
    for (final contact in contacts) {
      if (contact.kind == 'whatsapp') return contact;
    }
    return null;
  }

  bool get hasLocation => address.isNotEmpty || mapUrl.isNotEmpty;

  /// رابط الخريطة، أو بحث بالعنوان لو مفيش رابط محفوظ.
  String get resolvedMapUrl {
    if (mapUrl.isNotEmpty) return mapUrl;
    final query = Uri.encodeComponent(
      [name, address, area].where((part) => part.isNotEmpty).join(' '),
    );
    return 'https://www.google.com/maps/search/?api=1&query=$query';
  }

  Instructor copyWith({
    String? name,
    InstructorKind? kind,
    String? subjectId,
    String? address,
    String? area,
    String? mapUrl,
    List<ContactMethod>? contacts,
    double? sessionCost,
    String? notes,
  }) {
    return Instructor(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      subjectId: subjectId ?? this.subjectId,
      address: address ?? this.address,
      area: area ?? this.area,
      mapUrl: mapUrl ?? this.mapUrl,
      contacts: contacts ?? this.contacts,
      sessionCost: sessionCost ?? this.sessionCost,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'subjectId': subjectId,
        'address': address,
        'area': area,
        'mapUrl': mapUrl,
        'contacts': contacts.map((c) => c.toJson()).toList(),
        'sessionCost': sessionCost,
        'notes': notes,
      };

  factory Instructor.fromJson(Map<String, dynamic> json) => Instructor(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        kind: InstructorKind.fromId(json['kind'] as String?),
        subjectId: json['subjectId'] as String? ?? '',
        address: json['address'] as String? ?? '',
        area: json['area'] as String? ?? '',
        mapUrl: json['mapUrl'] as String? ?? '',
        contacts: ((json['contacts'] as List?) ?? const [])
            .whereType<Map>()
            .map((c) => ContactMethod.fromJson(Map<String, dynamic>.from(c)))
            .toList(),
        sessionCost: (json['sessionCost'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String? ?? '',
      );
}
