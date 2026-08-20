import 'package:ahla_shabab_management_os/features/mobile_pages/people_hub_page.dart';
import 'package:flutter/material.dart';

// ── Models ──

class OrgEmployee {
  const OrgEmployee({
    required this.id,
    required this.fullNameAr,
    this.fullNameEn,
    this.photoUrl,
    required this.jobTitle,
    required this.departmentName,
    required this.employeeCode,
    this.managerEmployeeId,
    required this.directReportsCount,
    required this.depth,
  });

  factory OrgEmployee.fromJson(Map<String, dynamic> json) => OrgEmployee(
        id: json['id'] as String,
        fullNameAr: json['fullNameAr'] as String? ?? '',
        fullNameEn: json['fullNameEn'] as String?,
        photoUrl: json['photoUrl'] as String?,
        jobTitle: json['jobTitle'] as String? ?? '',
        departmentName: json['departmentName'] as String? ?? '',
        employeeCode: json['employeeCode'] as String? ?? '',
        managerEmployeeId: json['managerEmployeeId'] as String?,
        directReportsCount: (json['directReportsCount'] as num?)?.toInt() ?? 0,
        depth: (json['depth'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String fullNameAr;
  final String? fullNameEn;
  final String? photoUrl;
  final String jobTitle;
  final String departmentName;
  final String employeeCode;
  final String? managerEmployeeId;
  final int directReportsCount;
  final int depth;
}

class OrgTreeNode {
  const OrgTreeNode({required this.employee, required this.children});
  final OrgEmployee employee;
  final List<OrgTreeNode> children;
}

class OrgChartData {
  const OrgChartData({required this.employees, required this.tree, required this.stats});
  final List<OrgEmployee> employees;
  final List<OrgTreeNode> tree;
  final OrgStats stats;
}

class OrgStats {
  const OrgStats({
    required this.totalEmployees,
    required this.managersCount,
    required this.maxDepth,
    required this.avgDirectReports,
  });
  final int totalEmployees;
  final int managersCount;
  final int maxDepth;
  final double avgDirectReports;
}

/// تم توحيد الهيكل التنظيمي ودليل الموظفين وإدارة الموظفين في [PeopleHubPage].
/// تم الإبقاء على هذا المكون للتوافق الكامل.
class OrgChartPage extends StatelessWidget {
  const OrgChartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PeopleHubPage(initialTab: 2);
  }
}
