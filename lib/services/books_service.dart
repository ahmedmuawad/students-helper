import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/local_store.dart';
import '../models/book.dart';
import 'api_client.dart';

/// تقدّم تحميل ملف.
class DownloadProgress {
  final int received;
  final int total;

  const DownloadProgress(this.received, this.total);

  /// نسبة التقدّم من 0 إلى 1، أو null لو الحجم الكلي مش معروف.
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

/// مكتبة الكتب: الجلب من السيرفر، التحميل للجهاز، والقراءة بدون نت.
class BooksService {
  final ApiClient _api;
  final LocalStore _store;
  final http.Client _http;

  BooksService(this._api, this._store, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  static const String _downloadsKey = 'book_downloads';
  static const String _cachedLibraryKey = 'book_library_cache';

  // ---------------------------------------------------------------- الجلب

  /// كتب الطالب حسب صفه ونظامه.
  ///
  /// بترجّع النسخة المحفوظة محليًا لو مفيش نت، عشان المكتبة تفضل مفتوحة.
  Future<List<Book>> fetchLibrary({
    int? gradeLevel,
    String? systemId,
    String? language,
    int? term,
  }) async {
    try {
      final data = await _api.get('/api/v1/library', query: {
        if (gradeLevel != null) 'grade_level': gradeLevel,
        if (systemId != null && systemId.isNotEmpty) 'system_id': systemId,
        if (language != null && language.isNotEmpty) 'language': language,
        if (term != null) 'term': term,
      });

      if (data is! List) return cachedLibrary();

      final books = data
          .whereType<Map>()
          .map((item) => Book.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);

      await _cacheLibrary(books);
      return books;
    } on ApiException {
      // مفيش نت أو السيرفر واقع — نرجّع آخر نسخة اتحفظت.
      return cachedLibrary();
    }
  }

  /// آخر قائمة كتب اتحفظت محليًا.
  List<Book> cachedLibrary() =>
      _store.readList(_cachedLibraryKey, Book.fromJson);

  Future<void> _cacheLibrary(List<Book> books) =>
      _store.writeList(_cachedLibraryKey, books, (b) => b.toJson());

  // ---------------------------------------------------------------- التحميل

  /// الكتب المحمّلة على الجهاز.
  List<BookDownload> downloads() =>
      _store.readList(_downloadsKey, BookDownload.fromJson);

  /// هل الكتاب متحمّل ولسه موجود على القرص؟
  Future<BookDownload?> downloadFor(int bookId) async {
    for (final download in downloads()) {
      if (download.bookId != bookId) continue;
      if (await File(download.filePath).exists()) return download;
      // الملف اتمسح من برّه التطبيق — ننضّف السجل.
      await _removeDownloadRecord(bookId);
      return null;
    }
    return null;
  }

  /// تحميل كتاب للقراءة بدون نت.
  Future<BookDownload> download(
    Book book, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    final existing = await downloadFor(book.id);
    if (existing != null) return existing;

    final directory = await _booksDirectory();
    final target = File('${directory.path}/book_${book.id}.pdf');
    final temporary = File('${target.path}.part');

    final uri = Uri.parse(
      book.fileUrl.startsWith('http')
          ? book.fileUrl
          : '${ApiClient.baseUrl}${book.fileUrl}',
    );

    final request = http.Request('GET', uri);
    final response = await _http.send(request);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'تعذّر تحميل الكتاب');
    }

    final total = response.contentLength ?? book.fileSize;
    var received = 0;
    final sink = temporary.openWrite();

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received, total));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // التحميل بيتم على ملف مؤقت وبيتنقل في الآخر، عشان لو الاتصال قطع
    // ما نفضلش بملف ناقص التطبيق يفتكره سليم.
    await temporary.rename(target.path);

    final record = BookDownload(
      bookId: book.id,
      filePath: target.path,
      downloadedAt: DateTime.now(),
      fileSize: received,
    );
    await _saveDownloadRecord(record);
    return record;
  }

  /// حذف نسخة الكتاب من الجهاز.
  Future<void> deleteDownload(int bookId) async {
    final download = await downloadFor(bookId);
    if (download != null) {
      try {
        await File(download.filePath).delete();
      } on FileSystemException catch (error) {
        debugPrint('تعذّر حذف ملف الكتاب: $error');
      }
    }
    await _removeDownloadRecord(bookId);
  }

  /// إجمالي المساحة اللي بتاخدها الكتب المحمّلة.
  Future<int> totalDownloadedBytes() async {
    var total = 0;
    for (final download in downloads()) {
      final file = File(download.filePath);
      if (await file.exists()) total += await file.length();
    }
    return total;
  }

  Future<Directory> _booksDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/books');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<void> _saveDownloadRecord(BookDownload record) async {
    final list = downloads().where((d) => d.bookId != record.bookId).toList()
      ..add(record);
    await _store.writeList(_downloadsKey, list, (d) => d.toJson());
  }

  Future<void> _removeDownloadRecord(int bookId) async {
    final list = downloads().where((d) => d.bookId != bookId).toList();
    await _store.writeList(_downloadsKey, list, (d) => d.toJson());
  }

  void dispose() => _http.close();
}

/// مفاتيح تخزين المكتبة.
extension BooksStoreKeys on StoreKeys {
  static const downloads = 'book_downloads';
  static const libraryCache = 'book_library_cache';
}

/// أدوات مساعدة لقراءة قائمة الكتب من JSON مخزّن.
List<Book> decodeBooks(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((item) => Book.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}
