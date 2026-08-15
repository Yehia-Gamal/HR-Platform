import 'package:ahla_shabab_management_os/features/mobile_pages/committee_dispute_list_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_disputes_page.dart';
import 'package:flutter/material.dart';

/// بوابة القضايا الموحّدة — تبويبان في صفحة واحدة:
///  1. بوابة القضايا (جميع القضايا + ملخص إحصائي — لجنة/تنفيذي/تشغيل)
///  2. الإجراءات الإدارية (سير العمل: اقتراح → قرار → تنفيذ)
class DisputesPortalPage extends StatelessWidget {
  const DisputesPortalPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('القضايا'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'بوابة القضايا'),
            Tab(text: 'الإجراءات الإدارية'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          CommitteeDisputeListPage(embedded: true),
          ExecutiveDisputesPage(embedded: true),
        ],
      ),
    ),
  );
}
