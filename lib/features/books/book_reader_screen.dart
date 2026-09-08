import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import '../../models/book.dart';
import '../../services/api_client.dart';
import '../../services/books_service.dart';
import '../common/ui_helpers.dart';

/// قارئ الكتب.
///
/// الكتاب لازم يتحمّل الأول عشان يتقرا. ده مقصود: ملفات الوزارة كبيرة
/// (عشرات الميجات) والطالب غالبًا هيرجع لنفس الكتاب كل يوم، فتحميل مرة
/// أحسن من استهلاك الباقة كل مرة — وبيشتغل في المدرسة من غير نت كمان.
class BookReaderScreen extends StatefulWidget {
  final Book book;
  final BooksService service;

  const BookReaderScreen({
    super.key,
    required this.book,
    required this.service,
  });

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  final _controller = PdfViewerController();

  String? _path;
  bool _checking = true;
  bool _downloading = false;
  DownloadProgress? _progress;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final existing = await widget.service.downloadFor(widget.book.id);
    if (!mounted) return;
    setState(() {
      _path = existing?.filePath;
      _checking = false;
    });
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
    });
    try {
      final download = await widget.service.download(
        widget.book,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _path = download.filePath;
        _downloading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'ما قدرناش ننزّل الكتاب — جرّب تاني';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.book.titleAr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          if (path != null) ...[
            IconButton(
              tooltip: 'اطبع',
              icon: const Icon(Icons.print_outlined),
              onPressed: () => _print(path),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => _onMenu(value, path),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'goto', child: Text('روح لصفحة')),
                PopupMenuItem(value: 'delete', child: Text('امسح من الجهاز')),
              ],
            ),
          ],
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : path == null
              ? _downloadPrompt()
              : PdfViewer.file(
                  path,
                  controller: _controller,
                  params: PdfViewerParams(
                    onPageChanged: (page) {
                      if (page != null && mounted) {
                        setState(() => _page = page);
                      }
                    },
                    errorBannerBuilder: (context, error, stack, documentRef) =>
                        Center(
                      child: EmptyState(
                        icon: Icons.broken_image_outlined,
                        message: 'الملف مش مقروء — امسحه وحمّله تاني',
                      ),
                    ),
                  ),
                ),
      bottomNavigationBar: path == null || widget.book.pageCount == 0
          ? null
          : _PageBar(
              page: _page,
              total: widget.book.pageCount,
              onJump: () => _askForPage(),
            ),
    );
  }

  Widget _downloadPrompt() {
    final size = widget.book.fileSize;
    final megabytes = size > 0 ? (size / (1024 * 1024)).toStringAsFixed(1) : null;
    final fraction = _progress?.fraction;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_download_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              widget.book.titleAr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              megabytes == null
                  ? 'حمّل الكتاب عشان تقراه وتطبعه من غير نت'
                  : 'حجمه $megabytes ميجا. بعد ما تحمّله هيفتح من غير نت.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
            if (_downloading) ...[
              LinearProgressIndicator(value: fraction),
              const SizedBox(height: 10),
              Text(
                fraction == null
                    ? 'بينزّل...'
                    : 'بينزّل ${(fraction * 100).toStringAsFixed(0)}٪',
              ),
            ] else
              FilledButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download),
                label: const Text('حمّل الكتاب'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 48),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onMenu(String value, String path) async {
    switch (value) {
      case 'goto':
        await _askForPage();
      case 'delete':
        await widget.service.deleteDownload(widget.book.id);
        if (mounted) setState(() => _path = null);
    }
  }

  Future<void> _askForPage() async {
    final controller = TextEditingController();
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('روح لصفحة'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.book.pageCount > 0
                ? 'من ١ لـ ${widget.book.pageCount}'
                : 'رقم الصفحة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              int.tryParse(controller.text.trim()),
            ),
            child: const Text('روح'),
          ),
        ],
      ),
    );
    if (page != null && page > 0) {
      await _controller.goToPage(pageNumber: page);
    }
  }

  /// الطباعة بتفتح ورقة النظام، والطالب يقدر يختار الصفحات اللي عايزها
  /// منها — ده أدق من إننا نعمل واجهة نطاقات بنفسنا.
  Future<void> _print(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: widget.book.titleAr,
      );
    } catch (error) {
      if (mounted) showSnack(context, 'الطباعة مش متاحة على الجهاز ده');
    }
  }
}

class _PageBar extends StatelessWidget {
  final int page;
  final int total;
  final VoidCallback onJump;

  const _PageBar({
    required this.page,
    required this.total,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: total > 0 ? (page / total).clamp(0.0, 1.0) : null,
                minHeight: 4,
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onJump,
              child: Text('$page / $total'),
            ),
          ],
        ),
      ),
    );
  }
}
