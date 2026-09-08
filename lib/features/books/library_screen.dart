import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/enums.dart';
import '../../services/api_client.dart';
import '../../services/books_service.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';
import 'book_reader_screen.dart';

/// مكتبة كتب الطالب — كتب الوزارة والملازم والمراجعات.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final BooksService _books;

  List<Book> _all = const [];
  bool _loading = true;
  bool _fromCache = false;
  String? _error;

  int? _term;
  BookKind? _kind;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _books = context.read<BooksService>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final profile = context.read<AppState>().profile;
    try {
      final books = await _books.fetchLibrary(
        gradeLevel: profile?.gradeLevel,
        systemId: profile?.educationSystem.id,
        language: profile?.schoolLanguage.id,
      );
      if (!mounted) return;
      setState(() {
        _all = books;
        _loading = false;
        // لو رجّعت المخزّن، يبقى مفيش نت — بنقول للطالب بدل ما يستنى
        _fromCache = books.isNotEmpty && _books.cachedLibrary().length == books.length;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _all = _books.cachedLibrary();
        _loading = false;
        _error = _all.isEmpty ? error.message : null;
        _fromCache = _all.isNotEmpty;
      });
    }
  }

  List<Book> get _visible {
    final needle = _search.trim().toLowerCase();
    return _all.where((book) {
      if (_term != null && book.term != _term) return false;
      if (_kind != null && book.kind != _kind) return false;
      if (needle.isEmpty) return true;
      return book.titleAr.toLowerCase().contains(needle) ||
          book.subjectNameAr.toLowerCase().contains(needle);
    }).toList(growable: false);
  }

  /// الكتب مجمّعة بالمادة — أسهل بكتير من قايمة طويلة.
  Map<String, List<Book>> get _bySubject {
    final grouped = <String, List<Book>>{};
    for (final book in _visible) {
      grouped.putIfAbsent(book.subjectNameAr, () => []).add(book);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppState>().profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المكتبة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            tooltip: 'المحمّل على الجهاز',
            icon: const Icon(Icons.download_done_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DownloadedBooksScreen(service: _books),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(profile?.gradeLevel),
      ),
    );
  }

  Widget _buildBody(int? gradeLevel) {
    if (_all.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.menu_book_outlined,
            message: _error ??
                (gradeLevel == null
                    ? 'حدّد صفك الدراسي الأول عشان نجيب كتبك'
                    : 'مفيش كتب متاحة لصفك دلوقتي'),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('جرّب تاني'),
            ),
          ),
        ],
      );
    }

    final grouped = _bySubject;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (_fromCache)
          const _OfflineBanner(),
        _Filters(
          term: _term,
          kind: _kind,
          kinds: _all.map((b) => b.kind).toSet().toList()..sort(
            (a, b) => a.index.compareTo(b.index),
          ),
          onSearch: (value) => setState(() => _search = value),
          onTerm: (value) => setState(() => _term = value),
          onKind: (value) => setState(() => _kind = value),
        ),
        const SizedBox(height: 8),
        if (grouped.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: EmptyState(
              icon: Icons.search_off,
              message: 'مفيش كتاب بالمواصفات دي',
            ),
          ),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              entry.key,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          for (final book in entry.value)
            _BookTile(
              book: book,
              service: _books,
              onOpen: () => _open(book),
            ),
        ],
      ],
    );
  }

  Future<void> _open(Book book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookReaderScreen(book: book, service: _books),
      ),
    );
    if (mounted) setState(() {});   // حالة التحميل ممكن تكون اتغيّرت
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'بتشوف آخر قائمة اتحفظت. الكتب المحمّلة بتتفتح عادي من غير نت.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final int? term;
  final BookKind? kind;
  final List<BookKind> kinds;
  final ValueChanged<String> onSearch;
  final ValueChanged<int?> onTerm;
  final ValueChanged<BookKind?> onKind;

  const _Filters({
    required this.term,
    required this.kind,
    required this.kinds,
    required this.onSearch,
    required this.onTerm,
    required this.onKind,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: onSearch,
          decoration: const InputDecoration(
            hintText: 'دوّر على مادة أو كتاب',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('الترم الأول'),
                selected: term == 1,
                onSelected: (on) => onTerm(on ? 1 : null),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('الترم التاني'),
                selected: term == 2,
                onSelected: (on) => onTerm(on ? 2 : null),
              ),
              if (kinds.length > 1) ...[
                const SizedBox(width: 14),
                for (final option in kinds) ...[
                  FilterChip(
                    label: Text(option.labelAr),
                    selected: kind == option,
                    onSelected: (on) => onKind(on ? option : null),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BookTile extends StatelessWidget {
  final Book book;
  final BooksService service;
  final VoidCallback onOpen;

  const _BookTile({
    required this.book,
    required this.service,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BookDownload?>(
      future: service.downloadFor(book.id),
      builder: (context, snapshot) {
        final downloaded = snapshot.data != null;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Container(
              width: 42,
              height: 54,
              decoration: BoxDecoration(
                color: _color(book.subjectColor).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _color(book.subjectColor).withValues(alpha: 0.5),
                ),
              ),
              child: Icon(
                Icons.menu_book,
                color: _color(book.subjectColor),
                size: 22,
              ),
            ),
            title: Text(
              book.titleAr,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 10,
                runSpacing: 2,
                children: [
                  _Meta(icon: Icons.category_outlined, text: book.kind.labelAr),
                  if (book.pageCount > 0)
                    _Meta(
                      icon: Icons.description_outlined,
                      text: '${book.pageCount} صفحة',
                    ),
                  _Meta(
                    icon: Icons.event_note_outlined,
                    text: 'الترم ${book.term == 1 ? 'الأول' : 'التاني'}',
                  ),
                ],
              ),
            ),
            trailing: Icon(
              downloaded ? Icons.offline_pin : Icons.chevron_left,
              color: downloaded ? Colors.green : null,
            ),
            onTap: onOpen,
          ),
        );
      },
    );
  }

  static Color _color(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return const Color(0xFF2E7D91);
    return Color(cleaned.length <= 6 ? 0xFF000000 | value : value);
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

/// الكتب المحمّلة على الجهاز والمساحة اللي بتاخدها.
class DownloadedBooksScreen extends StatefulWidget {
  final BooksService service;

  const DownloadedBooksScreen({super.key, required this.service});

  @override
  State<DownloadedBooksScreen> createState() => _DownloadedBooksScreenState();
}

class _DownloadedBooksScreenState extends State<DownloadedBooksScreen> {
  @override
  Widget build(BuildContext context) {
    final downloads = widget.service.downloads();
    final library = widget.service.cachedLibrary();

    return Scaffold(
      appBar: AppBar(title: const Text('المحمّل على الجهاز')),
      body: downloads.isEmpty
          ? const EmptyState(
              icon: Icons.download_outlined,
              message: 'مفيش كتب محمّلة لسه.\nحمّل كتاب عشان تقراه من غير نت.',
            )
          : ListView.separated(
              itemCount: downloads.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final download = downloads[index];
                final book = library
                    .where((b) => b.id == download.bookId)
                    .cast<Book?>()
                    .firstWhere((b) => true, orElse: () => null);
                return ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(book?.titleAr ?? 'كتاب #${download.bookId}'),
                  subtitle: Text(_size(download.fileSize)),
                  trailing: IconButton(
                    tooltip: 'امسح من الجهاز',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.service.deleteDownload(download.bookId);
                      if (context.mounted) setState(() {});
                    },
                  ),
                );
              },
            ),
    );
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميجا';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} كيلو';
  }
}
