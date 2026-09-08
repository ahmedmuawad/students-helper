import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/instructor.dart';
import '../common/ui_helpers.dart';

/// كارت بيانات المدرس / السنتر مع أزرار تواصل سريعة.
///
/// الفكرة إن الطالب (أو ولي الأمر) يقدر يتصل أو يفتح العنوان على الخريطة
/// بضغطة واحدة من جوّه الدرس، بدل ما يدوّر على الرقم في التليفون.
class InstructorCard extends StatelessWidget {
  final Instructor instructor;
  final VoidCallback? onEdit;

  /// عرض مختصر (سطر واحد) بدل الكارت الكامل.
  final bool compact;

  const InstructorCard({
    super.key,
    required this.instructor,
    this.onEdit,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = instructor.primaryPhone;
    final whatsapp = instructor.whatsapp;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(_kindIcon, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instructor.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _kindLabel,
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 19),
                    onPressed: onEdit,
                  ),
              ],
            ),

            if (instructor.address.isNotEmpty ||
                instructor.area.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 16, color: scheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [instructor.address, instructor.area]
                          .where((part) => part.isNotEmpty)
                          .join(' - '),
                      style: TextStyle(fontSize: 12.5, color: scheme.outline),
                    ),
                  ),
                ],
              ),
            ],

            if (!compact && instructor.sessionCost > 0) ...[
              const SizedBox(height: 8),
              Pill(
                '${instructor.sessionCost.toStringAsFixed(0)} ج.م للحصة',
                color: scheme.primary,
                icon: Icons.payments_outlined,
              ),
            ],

            const SizedBox(height: 12),

            // أزرار التواصل السريع
            Row(
              children: [
                if (phone != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.call,
                      label: 'اتصال',
                      onTap: () => _open(context, phone.uri),
                    ),
                  ),
                if (phone != null && whatsapp != null) const SizedBox(width: 8),
                if (whatsapp != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.chat_bubble_outline,
                      label: 'واتساب',
                      onTap: () => _open(context, whatsapp.uri),
                    ),
                  ),
                if (instructor.hasLocation) ...[
                  if (phone != null || whatsapp != null)
                    const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.map_outlined,
                      label: 'الخريطة',
                      onTap: () => _open(context, instructor.resolvedMapUrl),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData get _kindIcon {
    switch (instructor.kind) {
      case InstructorKind.teacher:
        return Icons.person;
      case InstructorKind.center:
        return Icons.apartment;
      case InstructorKind.online:
        return Icons.videocam;
    }
  }

  String get _kindLabel {
    switch (instructor.kind) {
      case InstructorKind.teacher:
        return 'مدرس خصوصي';
      case InstructorKind.center:
        return 'سنتر';
      case InstructorKind.online:
        return 'أونلاين';
    }
  }

  /// فتح رابط خارجي (اتصال / واتساب / خريطة) مع رسالة واضحة لو فشل.
  static Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      showSnack(context, 'الرابط غير صالح');
      return;
    }
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        showSnack(context, 'مفيش تطبيق يقدر يفتح ده');
      }
    } catch (_) {
      if (context.mounted) showSnack(context, 'تعذّر فتح الرابط');
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(38),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        foregroundColor: scheme.primary,
      ),
    );
  }
}
