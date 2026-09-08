import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/local_store.dart';
import 'api_client.dart';

/// نوع السجل زي ما السيرفر بيعرفه.
enum RecordKind {
  profile,
  subject,
  period,
  lesson,
  instructor,
  task;

  static RecordKind? fromId(String? id) {
    for (final kind in RecordKind.values) {
      if (kind.name == id) return kind;
    }
    return null;
  }
}

/// تعديل محلي لسه ما اتبعتش للسيرفر.
@immutable
class PendingChange {
  final RecordKind kind;
  final String id;

  /// وقت التعديل بساعة الجهاز — السيرفر بيحسم بيه التعارض.
  final DateTime at;
  final bool deleted;

  const PendingChange({
    required this.kind,
    required this.id,
    required this.at,
    this.deleted = false,
  });

  String get key => '${kind.name}:$id';

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'id': id,
        'at': at.toIso8601String(),
        'deleted': deleted,
      };

  static PendingChange? fromJson(Map<String, dynamic> json) {
    final kind = RecordKind.fromId(json['kind'] as String?);
    final id = json['id'] as String?;
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (kind == null || id == null || id.isEmpty || at == null) return null;
    return PendingChange(
      kind: kind,
      id: id,
      at: at,
      deleted: json['deleted'] as bool? ?? false,
    );
  }
}

/// سجل جاي من السيرفر.
@immutable
class RemoteRecord {
  final RecordKind kind;
  final String id;
  final Map<String, dynamic> payload;
  final bool deleted;
  final int revision;

  const RemoteRecord({
    required this.kind,
    required this.id,
    required this.payload,
    required this.deleted,
    required this.revision,
  });

  static RemoteRecord? fromJson(Map<String, dynamic> json) {
    final kind = RecordKind.fromId(json['kind'] as String?);
    final id = json['id'] as String?;
    if (kind == null || id == null || id.isEmpty) return null;
    final payload = json['payload'];
    return RemoteRecord(
      kind: kind,
      id: id,
      payload: payload is Map ? Map<String, dynamic>.from(payload) : const {},
      deleted: json['deleted'] as bool? ?? false,
      revision: json['revision'] as int? ?? 0,
    );
  }
}

/// نتيجة جولة مزامنة واحدة.
@immutable
class SyncResult {
  final int pushed;
  final int pulled;
  final bool offline;
  final String? error;

  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.offline = false,
    this.error,
  });

  bool get ok => error == null && !offline;
  bool get changedAnything => pulled > 0;
}

/// مزامنة بيانات الطالب مع السيرفر.
///
/// التطبيق أوفلاين أولًا: كل تعديل بيتكتب محليًا **الأول** وبيتسجّل في
/// طابور، والمزامنة بتحصل بعدين لما يبقى فيه نت وتسجيل دخول. يعني الطالب
/// مش بيستنى السيرفر في أي شاشة.
///
/// الطابور بيتخزّن على القرص، فلو التطبيق اتقفل قبل ما يزامن، التعديلات
/// بتفضل مستنية وبتتبعت أول ما يفتح تاني.
class SyncService {
  final ApiClient _api;
  final LocalStore _store;

  /// آخر رقم نسخة شفناه من السيرفر.
  int _cursor = 0;

  /// التعديلات اللي لسه ما اتبعتتش، بالمفتاح "النوع:المعرّف".
  final Map<String, PendingChange> _pending = {};

  bool _syncing = false;

  SyncService(this._api, this._store) {
    _load();
  }

  int get cursor => _cursor;
  int get pendingCount => _pending.length;
  bool get hasPending => _pending.isNotEmpty;
  bool get isSyncing => _syncing;

  // ----- الطابور -----

  void _load() {
    _cursor = _store.readInt(StoreKeys.syncCursor);
    final raw = _store.readString(StoreKeys.syncPending);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final change = PendingChange.fromJson(Map<String, dynamic>.from(item));
        if (change != null) _pending[change.key] = change;
      }
    } on FormatException {
      // طابور تالف — بنبدأ من جديد بدل ما التطبيق يقع
      _pending.clear();
    }
  }

  Future<void> _savePending() => _store.writeString(
        StoreKeys.syncPending,
        jsonEncode(_pending.values.map((c) => c.toJson()).toList()),
      );

  /// يسجّل إن السجل ده اتعدّل ومحتاج يتبعت.
  ///
  /// آخر تعديل هو اللي بيتسجّل — مفيش داعي نبعت كل خطوة وسط، السيرفر
  /// محتاج الحالة النهائية بس.
  Future<void> markChanged(RecordKind kind, String id,
      {bool deleted = false}) async {
    if (id.isEmpty) return;
    final change = PendingChange(
      kind: kind,
      id: id,
      at: DateTime.now().toUtc(),
      deleted: deleted,
    );
    _pending[change.key] = change;
    await _savePending();
  }

  /// يمسح الطابور والمؤشر — بيتنادى عند تسجيل الخروج.
  Future<void> reset() async {
    _pending.clear();
    _cursor = 0;
    await _store.remove(StoreKeys.syncPending);
    await _store.remove(StoreKeys.syncCursor);
  }

  // ----- المزامنة -----

  /// جولة مزامنة: بيبعت اللي في الطابور وبيجيب اللي اتغيّر.
  ///
  /// [collect] بيدّينا محتوى السجل من الحالة المحلية، أو null لو اتمسح.
  /// [apply] بيطبّق سجل جاي من السيرفر على الحالة المحلية.
  Future<SyncResult> sync({
    required Map<String, dynamic>? Function(RecordKind kind, String id) collect,
    required Future<void> Function(List<RemoteRecord> records) apply,
  }) async {
    if (_syncing) return const SyncResult();
    if (!_api.isAuthenticated) {
      return const SyncResult(error: 'محتاج تسجيل دخول للمزامنة');
    }

    _syncing = true;
    try {
      return await _runOnce(collect: collect, apply: apply);
    } on ApiException catch (error) {
      return SyncResult(
        offline: error.isOffline,
        error: error.isOffline ? null : error.message,
      );
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> _runOnce({
    required Map<String, dynamic>? Function(RecordKind kind, String id) collect,
    required Future<void> Function(List<RemoteRecord> records) apply,
  }) async {
    // اللقطة دي هي اللي هنبعتها. أي تعديل يحصل أثناء الطلب بيفضل في
    // الطابور ويتبعت في الجولة الجاية — مش بننظّف الطابور كله أعمى.
    final sending = List<PendingChange>.from(_pending.values);
    final records = <Map<String, dynamic>>[];

    for (final change in sending) {
      final payload = change.deleted ? null : collect(change.kind, change.id);
      records.add({
        'kind': change.kind.name,
        'id': change.id,
        'payload': payload ?? const <String, dynamic>{},
        'updated_at': change.at.toIso8601String(),
        // السجل اللي اتمسح من الحالة المحلية بيتبعت كمحذوف حتى لو
        // الطابور مسجّله تعديل عادي
        'deleted': change.deleted || payload == null,
      });
    }

    // جولة واحدة: بنبعت اللي عندنا وبناخد أول دفعة من اللي اتغيّر،
    // وبعدها بنكمّل سحب لو السيرفر قال إن فيه كمان.
    var pulled = 0;
    var since = _cursor;

    dynamic data = await _api.post('/api/v1/sync', body: {
      'since': since,
      'records': records,
    });

    while (true) {
      if (data is! Map) break;
      final body = Map<String, dynamic>.from(data);

      final incoming = <RemoteRecord>[];
      for (final item in (body['records'] as List? ?? const [])) {
        if (item is! Map) continue;
        final record = RemoteRecord.fromJson(Map<String, dynamic>.from(item));
        if (record != null) incoming.add(record);
      }

      if (incoming.isNotEmpty) {
        await apply(incoming);
        pulled += incoming.length;
      }

      final revision = body['revision'] as int? ?? since;
      final hasMore = body['has_more'] as bool? ?? false;
      // شرط `revision > since` بيمنع لفة لا نهائية لو السيرفر رجّع نفس
      // الرقم ومعاه has_more بالغلط
      if (!hasMore || revision <= since) {
        since = revision;
        break;
      }
      since = revision;
      data = await _api.get('/api/v1/sync', query: {'since': since});
    }

    // نشيل بس اللي بعتناه فعلاً — أي تعديل جديد أثناء الطلب بيفضل
    for (final change in sending) {
      final current = _pending[change.key];
      if (current != null && !current.at.isAfter(change.at)) {
        _pending.remove(change.key);
      }
    }
    await _savePending();

    _cursor = since;
    await _store.writeInt(StoreKeys.syncCursor, _cursor);
    await _store.writeString(
      StoreKeys.lastSyncAt,
      DateTime.now().toIso8601String(),
    );

    return SyncResult(pushed: sending.length, pulled: pulled);
  }

  DateTime? get lastSyncAt {
    final raw = _store.readString(StoreKeys.lastSyncAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
