import 'package:ahla_shabab_management_os/features/mobile_pages/people_hub_page.dart';
import 'package:flutter/material.dart';

/// تم توحيد إدارة وسجل الموظفين والدليل والهيكل في [PeopleHubPage].
/// تم الإبقاء على هذا المكون للتوافق الكامل.
class MobileEmployeesPage extends StatelessWidget {
  const MobileEmployeesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PeopleHubPage(initialTab: 1);
  }
}
