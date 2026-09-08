import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:students_helper/data/local_store.dart';
import 'package:students_helper/models/enums.dart';
import 'package:students_helper/models/instructor.dart';
import 'package:students_helper/models/private_lesson.dart';
import 'package:students_helper/models/school_period.dart';
import 'package:students_helper/models/study_task.dart';
import 'package:students_helper/models/subject.dart';
import 'package:students_helper/services/api_client.dart';
import 'package:students_helper/services/sync_service.dart';
import 'package:students_helper/state/app_state.dart';

Future<(AppState, SyncService)> makeApp() async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  final sync = SyncService(ApiClient(), store);
  final app = AppState(store, sync: sync);
  await app.load();
  return (app, sync);
}

StudyTask task(String id, {String title = 'واجب', bool done = false}) =>
    StudyTask(
      id: id,
      title: title,
      type: TaskType.homework,
      priority: TaskPriority.normal,
      subjectId: 'math',
      isDone: done,
      createdAt: DateTime(2026, 9, 1),
    );

void main() {
  group('التعديلات بتتسجّل للمزامنة', () {
    test('إضافة مهمة بتتسجّل', () async {
      final (app, sync) = await makeApp();
      await app.upsertTask(task('t1'));
      await Future<void>.delayed(Duration.zero);
      expect(sync.pendingCount, 1);
    });

    test('حذف مهمة بيتسجّل كحذف', () async {
      final (app, sync) = await makeApp();
      await app.upsertTask(task('t1'));
      await app.syncService!.reset();
      await app.deleteTask('t1');
      await Future<void>.delayed(Duration.zero);
      expect(sync.pendingCount, 1);
    });

    test('تعليم المهمة كمنتهية بيتسجّل', () async {
      final (app, sync) = await makeApp();
      await app.upsertTask(task('t1'));
      await sync.reset();
      await app.toggleTaskDone('t1');
      await Future<void>.delayed(Duration.zero);
      expect(sync.pendingCount, 1);
    });

    test('كل أنواع السجلات بتتسجّل', () async {
      final (app, sync) = await makeApp();
      await app.upsertSubject(const Subject(id: 's1', nameAr: 'رياضيات', nameEn: 'Math'));
      await app.upsertPeriod(const SchoolPeriod(
        id: 'p1',
        weekday: DateTime.sunday,
        periodNumber: 1,
        subjectId: 's1',
        startMinutes: 480,
        endMinutes: 525,
      ));
      await app.upsertInstructor(const Instructor(id: 'i1', name: 'أ. سامي'));
      await app.upsertLesson(const PrivateLesson(
        id: 'l1',
        subjectId: 's1',
        weekday: DateTime.monday,
        startMinutes: 960,
        endMinutes: 1050,
      ));
      await app.upsertTask(task('t1'));
      await Future<void>.delayed(Duration.zero);

      expect(sync.pendingCount, 5);
    });
  });

  group('المحتوى اللي بيتبعت', () {
    test('collectRecord بيرجّع نفس اللي في التطبيق', () async {
      final (app, _) = await makeApp();
      await app.upsertTask(task('t1', title: 'مراجعة الفصل الأول'));

      final payload = app.collectRecord(RecordKind.task, 't1');
      expect(payload, isNotNull);
      expect(payload!['title'], 'مراجعة الفصل الأول');
    });

    test('السجل المحذوف بيرجّع null', () async {
      final (app, _) = await makeApp();
      expect(app.collectRecord(RecordKind.task, 'مش-موجود'), isNull);
    });
  });

  group('اللي جاي من السيرفر', () {
    test('مهمة جديدة بتتضاف', () async {
      final (app, _) = await makeApp();
      await app.applyRemote([
        RemoteRecord(
          kind: RecordKind.task,
          id: 't9',
          payload: task('t9', title: 'من جهاز تاني').toJson(),
          deleted: false,
          revision: 1,
        ),
      ]);
      expect(app.tasks, hasLength(1));
      expect(app.tasks.single.title, 'من جهاز تاني');
    });

    test('التعديل بيستبدل مش بيكرّر', () async {
      final (app, _) = await makeApp();
      await app.upsertTask(task('t1', title: 'قديم'));
      await app.applyRemote([
        RemoteRecord(
          kind: RecordKind.task,
          id: 't1',
          payload: task('t1', title: 'جديد').toJson(),
          deleted: false,
          revision: 2,
        ),
      ]);
      expect(app.tasks, hasLength(1));
      expect(app.tasks.single.title, 'جديد');
    });

    test('الحذف من السيرفر بيمسح محليًا', () async {
      final (app, _) = await makeApp();
      await app.upsertTask(task('t1'));
      await app.applyRemote([
        RemoteRecord(
          kind: RecordKind.task,
          id: 't1',
          payload: const {},
          deleted: true,
          revision: 3,
        ),
      ]);
      expect(app.tasks, isEmpty);
    });

    test('اللي جاي من السيرفر ما بيترجعش له تاني', () async {
      final (app, sync) = await makeApp();
      await sync.reset();
      await app.applyRemote([
        RemoteRecord(
          kind: RecordKind.task,
          id: 't9',
          payload: task('t9').toJson(),
          deleted: false,
          revision: 1,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(sync.hasPending, isFalse,
          reason: 'لو اتسجّل هيفضل يروح ويرجع للأبد');
    });

    test('سجل تالف بيتتخطى والباقي بيعدّي', () async {
      final (app, _) = await makeApp();
      await app.applyRemote([
        RemoteRecord(
          kind: RecordKind.task,
          id: 'تالف',
          payload: const {'title': 42},   // النوع غلط
          deleted: false,
          revision: 1,
        ),
        RemoteRecord(
          kind: RecordKind.task,
          id: 't1',
          payload: task('t1', title: 'سليم').toJson(),
          deleted: false,
          revision: 2,
        ),
      ]);
      expect(app.tasks.map((t) => t.title), contains('سليم'));
    });

    test('البيانات بتعيش بعد إعادة الفتح', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final first = AppState(store, sync: SyncService(ApiClient(), store));
      await first.load();
      await first.applyRemote([
        RemoteRecord(
          kind: RecordKind.task,
          id: 't1',
          payload: task('t1', title: 'محفوظة').toJson(),
          deleted: false,
          revision: 1,
        ),
      ]);

      final reopened = AppState(store);
      await reopened.load();
      expect(reopened.tasks.single.title, 'محفوظة');
    });
  });

  group('أول تسجيل دخول', () {
    test('اللي اتعمل قبل الحساب بيتعلّم كله للرفع', () async {
      final (app, sync) = await makeApp();
      await app.upsertTask(task('t1'));
      await app.upsertTask(task('t2'));
      await app.upsertSubject(const Subject(id: 's1', nameAr: 'علوم', nameEn: 'Science'));
      await sync.reset();                     // زي ما لسه سجّل دخول

      await app.markEverythingForUpload();
      expect(sync.pendingCount, 3);
    });
  });
}
