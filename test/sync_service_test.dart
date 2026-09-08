import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:students_helper/data/local_store.dart';
import 'package:students_helper/services/api_client.dart';
import 'package:students_helper/services/sync_service.dart';

/// سيرفر وهمي بيسجّل الطلبات ويرد بالمكتوب.
class _FakeServer extends http.BaseClient {
  final List<Map<String, dynamic>> requests = [];
  final List<Map<String, dynamic>> responses;
  int _index = 0;

  _FakeServer(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request && request.body.isNotEmpty
        ? jsonDecode(request.body)
        : null;
    requests.add({
      'method': request.method,
      'path': request.url.path,
      'query': request.url.queryParameters,
      'body': body,
    });

    final response = responses[_index.clamp(0, responses.length - 1)];
    _index++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(response))),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

Map<String, dynamic> emptyReply({int revision = 0, bool hasMore = false}) => {
      'revision': revision,
      'records': <dynamic>[],
      'has_more': hasMore,
      'rejected': <String>[],
      'server_time': DateTime.now().toIso8601String(),
    };

Map<String, dynamic> reply(
  List<Map<String, dynamic>> records, {
  required int revision,
  bool hasMore = false,
}) =>
    {
      'revision': revision,
      'records': records,
      'has_more': hasMore,
      'rejected': <String>[],
      'server_time': DateTime.now().toIso8601String(),
    };

Map<String, dynamic> serverRecord(
  String kind,
  String id,
  Map<String, dynamic> payload, {
  int revision = 1,
  bool deleted = false,
}) =>
    {
      'kind': kind,
      'id': id,
      'payload': payload,
      'updated_at': DateTime.now().toIso8601String(),
      'deleted': deleted,
      'revision': revision,
    };

Future<(SyncService, LocalStore, _FakeServer)> makeService(
  List<Map<String, dynamic>> responses, {
  Map<String, Object> seed = const {},
}) async {
  SharedPreferences.setMockInitialValues(seed);
  final store = await LocalStore.open();
  final server = _FakeServer(responses);
  final api = ApiClient(client: server)..setToken('dev:ahmed');
  return (SyncService(api, store), store, server);
}

void main() {
  group('طابور التعديلات', () {
    test('التعديل بيتسجّل ويستنى المزامنة', () async {
      final (sync, _, _) = await makeService([emptyReply()]);
      expect(sync.hasPending, isFalse);

      await sync.markChanged(RecordKind.task, 't1');
      expect(sync.pendingCount, 1);
    });

    test('تعديلين لنفس السجل بيتجمعوا في واحد', () async {
      final (sync, _, _) = await makeService([emptyReply()]);
      await sync.markChanged(RecordKind.task, 't1');
      await sync.markChanged(RecordKind.task, 't1');
      expect(sync.pendingCount, 1);
    });

    test('الطابور بيعيش بعد قفل التطبيق', () async {
      final (first, store, _) = await makeService([emptyReply()]);
      await first.markChanged(RecordKind.task, 't1');

      // خدمة جديدة على نفس التخزين = التطبيق اتفتح تاني
      final api = ApiClient(client: _FakeServer([emptyReply()]));
      final revived = SyncService(api, store);
      expect(revived.pendingCount, 1);
    });

    test('المعرّف الفاضي بيتتجاهل', () async {
      final (sync, _, _) = await makeService([emptyReply()]);
      await sync.markChanged(RecordKind.task, '');
      expect(sync.hasPending, isFalse);
    });
  });

  group('الرفع', () {
    test('بيبعت اللي في الطابور بمحتواه', () async {
      final (sync, _, server) = await makeService([emptyReply(revision: 1)]);
      await sync.markChanged(RecordKind.task, 't1');

      await sync.sync(
        collect: (kind, id) => {'title': 'واجب الجبر'},
        apply: (_) async {},
      );

      final sent = server.requests.single['body'] as Map;
      final records = sent['records'] as List;
      expect(records, hasLength(1));
      expect(records.first['kind'], 'task');
      expect(records.first['id'], 't1');
      expect(records.first['payload']['title'], 'واجب الجبر');
      expect(records.first['deleted'], isFalse);
    });

    test('الطابور بيتنضّف بعد الرفع', () async {
      final (sync, _, _) = await makeService([emptyReply(revision: 1)]);
      await sync.markChanged(RecordKind.task, 't1');
      await sync.sync(collect: (_, __) => {'a': 1}, apply: (_) async {});
      expect(sync.hasPending, isFalse);
    });

    test('السجل اللي اتمسح محليًا بيتبعت كمحذوف', () async {
      final (sync, _, server) = await makeService([emptyReply(revision: 1)]);
      await sync.markChanged(RecordKind.task, 't1');

      // collect بيرجّع null = مش موجود محليًا
      await sync.sync(collect: (_, __) => null, apply: (_) async {});

      final records =
          (server.requests.single['body'] as Map)['records'] as List;
      expect(records.first['deleted'], isTrue);
    });

    test('الحذف الصريح بيتبعت كمحذوف', () async {
      final (sync, _, server) = await makeService([emptyReply(revision: 1)]);
      await sync.markChanged(RecordKind.task, 't1', deleted: true);
      await sync.sync(collect: (_, __) => {'a': 1}, apply: (_) async {});

      final records =
          (server.requests.single['body'] as Map)['records'] as List;
      expect(records.first['deleted'], isTrue);
    });
  });

  group('السحب', () {
    test('السجلات الجاية بتتسلّم للتطبيق', () async {
      final (sync, _, _) = await makeService([
        reply([serverRecord('task', 't9', {'title': 'من جهاز تاني'})],
            revision: 5),
      ]);

      final applied = <RemoteRecord>[];
      final result = await sync.sync(
        collect: (_, __) => null,
        apply: (records) async => applied.addAll(records),
      );

      expect(result.pulled, 1);
      expect(applied.single.id, 't9');
      expect(applied.single.payload['title'], 'من جهاز تاني');
    });

    test('المؤشر بيتحفظ فالمزامنة الجاية تفاضلية', () async {
      final (sync, store, server) = await makeService([
        reply([serverRecord('task', 't1', {'a': 1})], revision: 7),
        emptyReply(revision: 7),
      ]);

      await sync.sync(collect: (_, __) => null, apply: (_) async {});
      expect(sync.cursor, 7);
      expect(store.readInt(StoreKeys.syncCursor), 7);

      await sync.sync(collect: (_, __) => null, apply: (_) async {});
      expect((server.requests.last['body'] as Map)['since'], 7);
    });

    test('has_more بيخلّيه يكمّل لحد ما يخلص', () async {
      final (sync, _, server) = await makeService([
        reply([serverRecord('task', 't1', {'a': 1})],
            revision: 1, hasMore: true),
        reply([serverRecord('task', 't2', {'a': 2}, revision: 2)],
            revision: 2, hasMore: true),
        reply([serverRecord('task', 't3', {'a': 3}, revision: 3)],
            revision: 3),
      ]);

      final result = await sync.sync(
        collect: (_, __) => null,
        apply: (_) async {},
      );

      expect(result.pulled, 3);
      // أول طلب POST، واللي بعده GET
      expect(server.requests.first['method'], 'POST');
      expect(server.requests[1]['method'], 'GET');
    });

    test('رقم نسخة مش بيتقدّم بيوقف اللفة بدل ما تفضل للأبد', () async {
      final (sync, _, server) = await makeService([
        // السيرفر بيقول "فيه كمان" بس الرقم ما اتغيّرش — غلط من ناحيته
        reply([serverRecord('task', 't1', {'a': 1})],
            revision: 0, hasMore: true),
      ]);

      await sync.sync(collect: (_, __) => null, apply: (_) async {})
          .timeout(const Duration(seconds: 5));

      expect(server.requests, hasLength(1));
    });

    test('السجل المحذوف بيوصل بعلامته', () async {
      final (sync, _, _) = await makeService([
        reply([serverRecord('task', 't1', {}, deleted: true)], revision: 3),
      ]);

      final applied = <RemoteRecord>[];
      await sync.sync(
        collect: (_, __) => null,
        apply: (records) async => applied.addAll(records),
      );
      expect(applied.single.deleted, isTrue);
    });

    test('سجل بنوع مش معروف بيتتخطى مش بيوقّع المزامنة', () async {
      final (sync, _, _) = await makeService([
        reply([
          serverRecord('task', 't1', {'a': 1}),
          {'kind': 'حاجة_جديدة', 'id': 'x', 'payload': {}, 'revision': 2},
        ], revision: 2),
      ]);

      final applied = <RemoteRecord>[];
      final result = await sync.sync(
        collect: (_, __) => null,
        apply: (records) async => applied.addAll(records),
      );
      expect(result.ok, isTrue);
      expect(applied, hasLength(1));
    });
  });

  group('من غير نت أو حساب', () {
    test('من غير تسجيل دخول مفيش مزامنة', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final api = ApiClient(client: _FakeServer([emptyReply()]));
      final sync = SyncService(api, store);   // من غير توكن

      final result = await sync.sync(collect: (_, __) => null, apply: (_) async {});
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('التعديلات بتفضل في الطابور لو الرفع فشل', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final api = ApiClient(client: _BrokenServer())..setToken('dev:ahmed');
      final sync = SyncService(api, store);

      await sync.markChanged(RecordKind.task, 't1');
      final result = await sync.sync(
        collect: (_, __) => {'a': 1},
        apply: (_) async {},
      );

      expect(result.offline, isTrue);
      expect(sync.pendingCount, 1, reason: 'التعديل ماينفعش يضيع');
    });
  });
}

/// سيرفر بيرمي خطأ اتصال.
class _BrokenServer extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(const SocketFailure());
}

class SocketFailure implements Exception {
  const SocketFailure();
}
