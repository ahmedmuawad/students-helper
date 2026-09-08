import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';

/// خطأ تسجيل دخول برسالة عربية مفهومة.
class AuthFailure implements Exception {
  final String message;
  final String code;

  const AuthFailure(this.message, {this.code = ''});

  @override
  String toString() => message;
}

/// المستخدم الحالي بالشكل اللي التطبيق محتاجه.
@immutable
class SignedInUser {
  final String uid;
  final String name;
  final String email;
  final String phone;

  const SignedInUser({
    required this.uid,
    this.name = '',
    this.email = '',
    this.phone = '',
  });

  /// أول اسم للعرض، وإلا الإيميل، وإلا الموبايل.
  String get label {
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return phone;
  }
}

/// تسجيل الدخول عبر Firebase.
///
/// Firebase مسؤول عن **الهوية بس**. بيدّينا توكن موقّع من جوجل، والسيرفر
/// بيتحقق من التوقيع بنفسه قبل ما يسلّم أي بيانات. مفيش أي بيانات طالب
/// بتروح لجوجل — الجدول والدروس والمهام كلهم على سيرفرنا.
class AuthService {
  final FirebaseAuth _auth;
  final ApiClient _api;

  /// معرّف التحقق بالموبايل بين إرسال الكود وإدخاله.
  String? _phoneVerificationId;
  int? _phoneResendToken;

  AuthService(this._api, {FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  /// بيتغيّر مع كل دخول وخروج — الشاشات بتسمعه.
  Stream<SignedInUser?> get userChanges =>
      _auth.idTokenChanges().asyncMap(_adopt);

  SignedInUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : _toUser(user);
  }

  bool get isSignedIn => _auth.currentUser != null;

  SignedInUser _toUser(User user) => SignedInUser(
        uid: user.uid,
        name: user.displayName ?? '',
        email: user.email ?? '',
        phone: user.phoneNumber ?? '',
      );

  /// بيحدّث توكن الـ API مع كل تغيّر في الحساب.
  Future<SignedInUser?> _adopt(User? user) async {
    if (user == null) {
      _api.clearToken();
      return null;
    }
    await refreshToken();
    return _toUser(user);
  }

  /// بيجدّد التوكن ويسلّمه للـ ApiClient.
  ///
  /// Firebase بيجدّد لوحده كل ساعة، بس بننادي دي كمان قبل أي عملية مهمة
  /// عشان ما نبعتش توكن على وشك ينتهي.
  Future<String?> refreshToken({bool force = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      _api.clearToken();
      return null;
    }
    try {
      final token = await user.getIdToken(force);
      _api.setToken(token);
      return token;
    } on FirebaseAuthException catch (error) {
      debugPrint('فشل تجديد التوكن: ${error.code}');
      return null;
    }
  }

  // ----- بالإيميل -----

  Future<SignedInUser> signInWithEmail(String email, String password) async {
    return _guard(() async {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _requireUser(credential.user);
    });
  }

  Future<SignedInUser> registerWithEmail(
    String email,
    String password, {
    String? name,
  }) async {
    return _guard(() async {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null && name != null && name.trim().isNotEmpty) {
        await user.updateDisplayName(name.trim());
        await user.reload();
      }
      return _requireUser(_auth.currentUser ?? user);
    });
  }

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  // ----- بالموبايل -----

  /// بيبعت كود للموبايل. [onAutoVerified] بتتنادى لو أندرويد قرا الرسالة
  /// لوحده وخلّص الدخول من غير ما المستخدم يكتب حاجة.
  Future<void> sendPhoneCode(
    String phoneNumber, {
    required void Function(String message) onFailed,
    required void Function() onCodeSent,
    void Function(SignedInUser user)? onAutoVerified,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: _normalizePhone(phoneNumber),
      timeout: timeout,
      forceResendingToken: _phoneResendToken,
      verificationCompleted: (credential) async {
        if (onAutoVerified == null) return;
        try {
          final result = await _auth.signInWithCredential(credential);
          final user = result.user;
          if (user != null) onAutoVerified(_toUser(user));
        } on FirebaseAuthException catch (error) {
          onFailed(_arabicFor(error));
        }
      },
      verificationFailed: (error) => onFailed(_arabicFor(error)),
      codeSent: (verificationId, resendToken) {
        _phoneVerificationId = verificationId;
        _phoneResendToken = resendToken;
        onCodeSent();
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _phoneVerificationId = verificationId;
      },
    );
  }

  Future<SignedInUser> confirmPhoneCode(String smsCode) async {
    final verificationId = _phoneVerificationId;
    if (verificationId == null) {
      throw const AuthFailure('ابعت الكود الأول');
    }
    return _guard(() async {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      final result = await _auth.signInWithCredential(credential);
      return _requireUser(result.user);
    });
  }

  /// المصريين بيكتبوا رقمهم بصيغ كتير — بنوحّدها للصيغة الدولية.
  static String _normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'[\s\-()]'), '').trim();
    if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('0')) return '+2$digits';       // 01xxxxxxxxx
    if (digits.startsWith('1') && digits.length == 10) {
      return '+20$digits';                                 // 1xxxxxxxxx
    }
    return '+$digits';
  }

  // ----- بجوجل -----

  Future<SignedInUser> signInWithGoogle() async {
    return _guard(() async {
      final google = GoogleSignIn.instance;
      await google.initialize();

      final GoogleSignInAccount account;
      try {
        account = await google.authenticate();
      } on GoogleSignInException catch (error) {
        if (error.code == GoogleSignInExceptionCode.canceled) {
          throw const AuthFailure('اتلغى تسجيل الدخول');
        }
        rethrow;
      }

      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      return _requireUser(result.user);
    });
  }

  // ----- خروج -----

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // مش مهم لو مكانش داخل بجوجل أصلاً
    }
    await _auth.signOut();
    _api.clearToken();
    _phoneVerificationId = null;
    _phoneResendToken = null;
  }

  /// يمسح الحساب من Firebase — بيتنادى بعد ما نمسح البيانات من السيرفر.
  Future<void> deleteAccount() => _guard(() async {
        await _auth.currentUser?.delete();
        _api.clearToken();
      });

  // ----- المساعدات -----

  SignedInUser _requireUser(User? user) {
    if (user == null) {
      throw const AuthFailure('تسجيل الدخول ما تمّش');
    }
    return _toUser(user);
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_arabicFor(error), code: error.code);
    }
  }

  /// رسايل Firebase إنجليزي وتقنية — بنحوّلها لكلام الطالب يفهمه.
  static String _arabicFor(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'الإيميل مش مكتوب صح';
      case 'user-disabled':
        return 'الحساب ده متوقف';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'الإيميل أو كلمة السر غلط';
      case 'email-already-in-use':
        return 'الإيميل ده مسجّل قبل كده — سجّل دخول';
      case 'weak-password':
        return 'كلمة السر ضعيفة — خليها ٦ حروف على الأقل';
      case 'operation-not-allowed':
        return 'طريقة الدخول دي مش مفعّلة على السيرفر';
      case 'invalid-phone-number':
        return 'رقم الموبايل مش مكتوب صح';
      case 'invalid-verification-code':
        return 'الكود غلط — راجعه وجرّب تاني';
      case 'session-expired':
        return 'الكود انتهت صلاحيته — اطلب واحد جديد';
      case 'too-many-requests':
        return 'حاولت كتير — استنى شوية وجرّب تاني';
      case 'network-request-failed':
        return 'مفيش اتصال بالإنترنت';
      case 'requires-recent-login':
        return 'سجّل دخول تاني الأول عشان تعمل العملية دي';
      default:
        return 'حصلت مشكلة في تسجيل الدخول (${error.code})';
    }
  }
}
