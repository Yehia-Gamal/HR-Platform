import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ExecutiveRiskCenterPage extends ConsumerStatefulWidget {
  const ExecutiveRiskCenterPage({super.key});

  @override
  ConsumerState<ExecutiveRiskCenterPage> createState() =>
      _ExecutiveRiskCenterPageState();
}

class _ExecutiveRiskCenterPageState
    extends ConsumerState<ExecutiveRiskCenterPage> {
  int section = 0;
  String severity = 'all';

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(mobileExecutiveCommandCenterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('مركز المخاطر والحوادث')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(mobileExecutiveCommandCenterProvider),
        child: data.when(
          loading: () => LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ),
          error: (error, _) => LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 52,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        humanizeError(error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: () => ref.invalidate(
                          mobileExecutiveCommandCenterProvider,
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(MobileExecutiveCommandCenter data) {
    final scheme = Theme.of(context).colorScheme;
    final criticalRisks = data.risks
        .where((item) => item.severity == 'critical')
        .length;
    final criticalIncidents = data.incidents
        .where((item) => item.severity == 'critical')
        .length;
    final risks = severity == 'all'
        ? data.risks
        : data.risks.where((item) => item.severity == severity).toList();
    final incidents = severity == 'all'
        ? data.incidents
        : data.incidents.where((item) => item.severity == severity).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                scheme.error,
                Color.alphaBlend(
                  scheme.error.withValues(alpha: .82),
                  Colors.black,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  color: scheme.onError.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  color: scheme.onError,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المخاطر تحت السيطرة',
                      style: TextStyle(
                        color: scheme.onError,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الأعلى شدة أولًا مع المالك والحالة وآخر تحديث.',
                      style: TextStyle(
                        color: scheme.onError.withValues(alpha: .76),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        MetricGrid(
          cards: [
            ('مخاطر مفتوحة', data.risks.length.toString(), Icons.trending_up, null),
            (
              'مخاطر حرجة',
              criticalRisks.toString(),
              Icons.warning_amber_rounded,
              null,
            ),
            (
              'حوادث نشطة',
              data.incidents.length.toString(),
              Icons.report_outlined,
              null,
            ),
            (
              'حوادث حرجة',
              criticalIncidents.toString(),
              Icons.crisis_alert_rounded,
              null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.trending_up_rounded),
              label: Text('المخاطر'),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.crisis_alert_outlined),
              label: Text('الحوادث'),
            ),
          ],
          selected: {section},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => section = value.first),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filter('all', 'كل الشدات'),
              _filter('critical', 'حرجة'),
              _filter('high', 'مرتفعة'),
              _filter('medium', 'متوسطة'),
              _filter('low', 'منخفضة'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              section == 0
                  ? 'عدد المخاطر: ${risks.length}'
                  : 'عدد الحوادث: ${incidents.length}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (severity != 'all')
              TextButton.icon(
                onPressed: () => setState(() => severity = 'all'),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('مسح التصفية'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (section == 0) _risks(risks) else _incidents(incidents),
      ],
    );
  }

  Widget _filter(String value, String label) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 7),
    child: ChoiceChip(
      label: Text(label),
      selected: severity == value,
      onSelected: (_) => setState(() => severity = value),
    ),
  );

  Widget _risks(List<ExecutiveRiskItem> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const MobileSectionHeader(
        title: 'سجل المخاطر الحية',
        subtitle: 'الاحتمالية والأثر وخطة المعالجة الحالية.',
      ),
      const SizedBox(height: 10),
      if (items.isEmpty)
        const _RiskEmpty(message: 'لا توجد مخاطر مطابقة للتصفية.')
      else
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showRisk(item),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _SeverityBadge(item.severity),
                          const Spacer(),
                          MobileStatusPill(_statusPill(item.status)),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (item.description != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          item.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MiniMeta(
                            label: 'الاحتمال',
                            value: _level(item.likelihood),
                          ),
                          const SizedBox(width: 8),
                          _MiniMeta(label: 'الأثر', value: _level(item.impact)),
                          const Spacer(),
                          if (item.ownerName != null)
                            Flexible(
                              child: Text(
                                item.ownerName!,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _incidents(List<ExecutiveIncidentItem> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const MobileSectionHeader(
        title: 'الحوادث النشطة',
        subtitle: 'البلاغات المفتوحة أو الجاري التحقيق فيها.',
      ),
      const SizedBox(height: 10),
      if (items.isEmpty)
        const _RiskEmpty(message: 'لا توجد حوادث مطابقة للتصفية.')
      else
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: _severityColor(
                    context,
                    item.severity,
                  ).withValues(alpha: .12),
                  child: Icon(
                    Icons.crisis_alert_rounded,
                    color: _severityColor(context, item.severity),
                  ),
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${_incidentStatus(item.status)} · ${DateFormat('d MMM، h:mm a', 'ar').format(item.createdAt.toLocal())}',
                ),
                trailing: _SeverityBadge(item.severity),
                onTap: () => _showIncident(item),
              ),
            ),
          ),
        ),
    ],
  );

  void _showRisk(ExecutiveRiskItem item) => _showDetails(
    title: item.title,
    description: item.description,
    rows: [
      ('الشدة', _level(item.severity)),
      ('الاحتمالية', _level(item.likelihood)),
      ('الأثر', _level(item.impact)),
      ('الحالة', _riskStatus(item.status)),
      ('المالك', item.ownerName ?? 'غير مسند'),
    ],
  );

  void _showIncident(ExecutiveIncidentItem item) => _showDetails(
    title: item.title,
    description: item.description,
    rows: [
      ('الشدة', _level(item.severity)),
      ('الحالة', _incidentStatus(item.status)),
      ('المبلّغ', item.reporterName ?? 'غير محدد'),
      (
        'تاريخ البلاغ',
        DateFormat('d MMMM y، h:mm a', 'ar').format(item.createdAt.toLocal()),
      ),
    ],
  );

  void _showDetails({
    required String title,
    required String? description,
    required List<(String, String)> rows,
  }) => showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(description),
            ],
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: rows
                    .map(
                      (row) => ListTile(
                        dense: true,
                        title: Text(row.$1),
                        trailing: Text(
                          row.$2,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _statusPill(String value) => switch (value) {
    'open' => 'urgent',
    'mitigating' => 'pending',
    'accepted' => 'approved',
    _ => value,
  };

  static String _riskStatus(String value) => switch (value) {
    'open' => 'مفتوحة',
    'mitigating' => 'قيد المعالجة',
    'accepted' => 'مقبولة',
    'closed' => 'مغلقة',
    _ => value,
  };

  static String _incidentStatus(String value) => switch (value) {
    'open' => 'مفتوح',
    'investigating' => 'قيد التحقيق',
    'resolved' => 'تم الحل',
    'closed' => 'مغلق',
    _ => value,
  };

  static String _level(String value) => _levelLabel(value);
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(context, value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _levelLabel(value),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _levelLabel(String value) => switch (value) {
  'critical' => 'حرجة',
  'high' => 'مرتفعة',
  'medium' => 'متوسطة',
  'low' => 'منخفضة',
  _ => value,
};

Color _severityColor(BuildContext context, String value) => switch (value) {
  'critical' => const Color(0xFFDC3D4B),
  'high' => const Color(0xFFD98508),
  'medium' => Theme.of(context).colorScheme.primary,
  _ => const Color(0xFF0F9F6E),
};

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
  );
}

class _RiskEmpty extends StatelessWidget {
  const _RiskEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          const Icon(Icons.shield_outlined, size: 42),
          const SizedBox(height: 9),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
