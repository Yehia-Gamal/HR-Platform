import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobilePrivacyRequest {
  const MobilePrivacyRequest({
    required this.id,
    required this.number,
    required this.type,
    required this.details,
    required this.status,
    required this.createdAt,
    required this.dueAt,
  });
  factory MobilePrivacyRequest.fromJson(Map<String, dynamic> json) =>
      MobilePrivacyRequest(
        id: json['id'] as String,
        number: (json['request_number'] as num).toInt(),
        type: json['request_type'] as String,
        details: json['details'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        dueAt: json['due_at'] == null
            ? null
            : DateTime.parse(json['due_at'] as String),
      );
  final String id;
  final int number;
  final String type;
  final String details;
  final String status;
  final DateTime createdAt;
  final DateTime? dueAt;
}

final mobilePrivacyRequestsProvider =
    FutureProvider<List<MobilePrivacyRequest>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final response = await client
          .from('privacy_requests')
          .select(
            'id,request_number,request_type,details,status,created_at,due_at',
          )
          .order('created_at', ascending: false);
      return (response as List<dynamic>)
          .map(
            (item) => MobilePrivacyRequest.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
            ),
          )
          .toList(growable: false);
    });

class MobilePrivacyPage extends ConsumerWidget {
  const MobilePrivacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(mobilePrivacyRequestsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogoMark(size: 30),
            const SizedBox(width: 10),
            const Flexible(
              child: Text('الخصوصية وبياناتي', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('طلب جديد'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(mobilePrivacyRequestsProvider),
        child: requests.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 240),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'تعذر تحميل طلبات الخصوصية.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'يرجى المحاولة مرة أخرى.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      ref.invalidate(mobilePrivacyRequestsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (items) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'يمكنك طلب الاطلاع على بياناتك أو تصحيحها أو تقييد استخدامها. كل طلب يُراجع بشريًا ويُسجل في سجل التدقيق.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.privacy_tip_outlined,
                          size: 44,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'لا توجد طلبات سابقة.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ...items.map(
                (item) => Semantics(
                  container: true,
                  label:
                      'طلب رقم ${item.number}، ${_type(item.type)}، الحالة ${_status(item.status)}',
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'طلب #${item.number} · ${_type(item.type)}',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                              MobileStatusPill(item.status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(item.details),
                          const SizedBox(height: 10),
                          Text(
                            'قُدّم ${DateFormat('d MMM y', 'ar').format(item.createdAt)}${item.dueAt == null ? '' : ' · الموعد المتوقع ${DateFormat('d MMM y', 'ar').format(item.dueAt!)}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref) async {
    String type = 'access';
    final controller = TextEditingController();
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'طلب خصوصية جديد',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'نوع الطلب'),
                items: const [
                  DropdownMenuItem(
                    value: 'access',
                    child: Text('الاطلاع على بياناتي'),
                  ),
                  DropdownMenuItem(
                    value: 'correction',
                    child: Text('تصحيح بيانات'),
                  ),
                  DropdownMenuItem(
                    value: 'export',
                    child: Text('نسخة قابلة للتنزيل'),
                  ),
                  DropdownMenuItem(
                    value: 'restriction',
                    child: Text('تقييد المعالجة'),
                  ),
                  DropdownMenuItem(
                    value: 'deletion',
                    child: Text('طلب حذف وفق السياسة'),
                  ),
                  DropdownMenuItem(
                    value: 'objection',
                    child: Text('اعتراض على استخدام البيانات'),
                  ),
                ],
                onChanged: (value) => setState(() => type = value ?? type),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 4,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: 'التفاصيل',
                  hintText: 'اشرح طلبك بوضوح…',
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () async {
                  if (controller.text.trim().length < 10) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('اكتب تفاصيل أوضح.')),
                    );
                    return;
                  }
                  final client = ref.read(supabaseProvider);
                  await client.rpc<dynamic>(
                    'submit_privacy_request',
                    params: {
                      'p_request_type': type,
                      'p_details': controller.text.trim(),
                    },
                  );
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop(true);
                  }
                },
                child: const Text('إرسال الطلب'),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (submitted == true) {
      ref.invalidate(mobilePrivacyRequestsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إرسال طلب الخصوصية.')));
      }
    }
  }

  static String _type(String value) => switch (value) {
    'access' => 'اطلاع',
    'correction' => 'تصحيح',
    'export' => 'تصدير',
    'restriction' => 'تقييد',
    'deletion' => 'حذف',
    'objection' => 'اعتراض',
    _ => value,
  };
  static String _status(String value) => switch (value) {
    'submitted' => 'مقدم',
    'in_review' => 'قيد المراجعة',
    'waiting_requester' => 'بانتظارك',
    'approved' => 'موافق عليه',
    'rejected' => 'مرفوض',
    'completed' => 'مكتمل',
    'cancelled' => 'ملغي',
    _ => value,
  };
}
