import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// خطأ راجع من السيرفر برسالة مفهومة للمستخدم.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  /// هل المشكلة إن المستخدم مش مسجّل دخول؟
  bool get isUnauthorized => statusCode == 401;

  /// هل المشكلة إن مفيش نت؟
  bool get isOffline => statusCode == 0;

  @override
  String toString() => message;
}

/// عميل الاتصال بسيرفر التطبيق.
///
/// التطبيق **أوفلاين أولًا**: كل الشاشات بتشتغل من التخزين المحلي، والعميل
/// ده بيستخدم للمزامنة والمحتوى اللي جاي من السيرفر (الكتب، المناهج،
/// ربط ولي الأمر، الاشتراكات).
class ApiClient {
  /// عنوان السيرفر.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://student-helper.stop4web.online',
  );

  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _http;

  /// توكن Firebase الحالي — بيتحدّث بعد تسجيل الدخول.
  String? _token;

  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  void setToken(String? token) => _token = token;

  void clearToken() => _token = null;

  Map<String, String> _headers({bool json = true}) {
    return {
      if (json) 'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      if (_token != null && _token!.isNotEmpty)
        'Authorization': 'Bearer $_token',
    };
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleaned = query?.map((key, value) => MapEntry(key, '$value'))
      ?..removeWhere((_, value) => value.isEmpty || value == 'null');
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: (cleaned == null || cleaned.isEmpty) ? null : cleaned,
    );
  }

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(0, 'السيرفر مش بيرد — جرّب تاني');
    } catch (error) {
      debugPrint('فشل الاتصال بالسيرفر: $error');
      throw const ApiException(0, 'مفيش اتصال بالإنترنت');
    }

    final body = response.body;
    dynamic decoded;
    if (body.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    // FastAPI بيرجّع الرسالة في المفتاح detail
    var message = 'حصل خطأ (${response.statusCode})';
    if (decoded is Map && decoded['detail'] != null) {
      final detail = decoded['detail'];
      message = detail is String ? detail : detail.toString();
    }
    throw ApiException(response.statusCode, message);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers(json: false)));

  Future<dynamic> post(String path, {Object? body}) => _send(
        () => _http.post(
          _uri(path),
          headers: _headers(),
          body: body == null ? null : jsonEncode(body),
        ),
      );

  Future<dynamic> patch(String path, {Object? body}) => _send(
        () => _http.patch(
          _uri(path),
          headers: _headers(),
          body: body == null ? null : jsonEncode(body),
        ),
      );

  Future<dynamic> delete(String path) =>
      _send(() => _http.delete(_uri(path), headers: _headers(json: false)));

  void dispose() => _http.close();
}
