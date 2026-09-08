import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/sync_service.dart';
import 'app_state.dart';

/// حالة تسجيل الدخول والمزامنة اللي الشاشات بتسمعها.
///
/// التطبيق **بيشتغل من غير حساب**. الحساب بيضيف حاجتين بس: المزامنة بين
/// الأجهزة، ومتابعة ولي الأمر. عشان كده مفيش أي شاشة بتتقفل لو المستخدم
/// مش مسجّل — بس بيظهر تنبيه إن البيانات على الجهاز ده بس.
class AuthState extends ChangeNotifier {
  final AuthService? _auth;
  final AppState _app;

  StreamSubscription<SignedInUser?>? _subscription;
  Timer? _timer;

  SignedInUser? _user;
  bool _busy = false;
  String? _lastError;
  SyncResult? _lastSync;

  /// فاضية لو Firebase مش متظبط على الجهاز ده.
  final String? setupProblem;

  AuthState({
    required AppState app,
    AuthService? auth,
    this.setupProblem,
  })  : _app = app,
        _auth = auth {
    final service = _auth;
    if (service != null) {
      _user = service.currentUser;
      _subscription = service.userChanges.listen(_onUserChanged);
    }
  }

  SignedInUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get isBusy => _busy;
  String? get lastError => _lastError;
  SyncResult? get lastSync => _lastSync;
  DateTime? get lastSyncAt => _app.syncService?.lastSyncAt;
  int get pendingCount => _app.syncService?.pendingCount ?? 0;

  /// هل تسجيل الدخول متاح أصلاً على الجهاز ده؟
  bool get isAvailable => _auth != null && setupProblem == null;

  Future<void> _onUserChanged(SignedInUser? user) async {
    final wasSignedOut = _user == null;
    _user = user;
    notifyListeners();

    if (user == null) {
      _stopTimer();
      return;
    }

    // أول دخول على الجهاز ده: نرفع اللي الطالب عمله قبل الحساب بدل
    // ما يضيع.
    if (wasSignedOut) {
      await _app.markEverythingForUpload();
    }
    unawaited(syncNow());
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    // مزامنة دورية خفيفة — أي تعديل بيتبعت في أقل من ٥ دقايق حتى لو
    // المستخدم ما قفلش التطبيق.
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// بتتنادى لما التطبيق يرجع للواجهة.
  Future<void> onResumed() async {
    if (!isSignedIn) return;
    await _auth?.refreshToken();
    await syncNow();
  }

  Future<SyncResult> syncNow() async {
    if (!isSignedIn) return const SyncResult(error: 'مش مسجّل دخول');
    final result = await _app.syncNow();
    _lastSync = result;
    notifyListeners();
    return result;
  }

  // ----- العمليات -----

  Future<bool> _run(Future<void> Function() action) async {
    if (_auth == null) {
      _lastError = setupProblem ?? 'تسجيل الدخول مش متاح دلوقتي';
      notifyListeners();
      return false;
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthFailure catch (error) {
      _lastError = error.message;
      return false;
    } catch (error) {
      debugPrint('خطأ غير متوقع في تسجيل الدخول: $error');
      _lastError = 'حصلت مشكلة — جرّب تاني';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithEmail(String email, String password) =>
      _run(() => _auth!.signInWithEmail(email, password));

  Future<bool> registerWithEmail(String email, String password, String name) =>
      _run(() => _auth!.registerWithEmail(email, password, name: name));

  Future<bool> sendPasswordReset(String email) =>
      _run(() => _auth!.sendPasswordReset(email));

  Future<bool> signInWithGoogle() => _run(() => _auth!.signInWithGoogle());

  Future<bool> sendPhoneCode(
    String phone, {
    required void Function() onCodeSent,
  }) =>
      _run(() => _auth!.sendPhoneCode(
            phone,
            onCodeSent: onCodeSent,
            onFailed: (message) {
              _lastError = message;
              notifyListeners();
            },
          ));

  Future<bool> confirmPhoneCode(String code) =>
      _run(() => _auth!.confirmPhoneCode(code));

  /// خروج: بيمسح التوكن والطابور، والبيانات المحلية بتفضل زي ما هي.
  Future<void> signOut() async {
    await _auth?.signOut();
    await _app.syncService?.reset();
    _user = null;
    _stopTimer();
    notifyListeners();
  }

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stopTimer();
    super.dispose();
  }
}
