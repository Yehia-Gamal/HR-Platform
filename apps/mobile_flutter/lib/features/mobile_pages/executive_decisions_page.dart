import 'package:flutter/material.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_announcement_page.dart';

/// تم توحيد صفحة إصدار القرارات مع صفحة نشر التعاميم والإعلانات
/// في صفحة موحدة غنية بالميزات [ExecutiveAnnouncementPage].
/// تم الإبقاء على هذا المكون للتوافقية الكاملة.
class ExecutiveDecisionsPage extends StatelessWidget {
  const ExecutiveDecisionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ExecutiveAnnouncementPage(initialType: 'decision');
  }
}
