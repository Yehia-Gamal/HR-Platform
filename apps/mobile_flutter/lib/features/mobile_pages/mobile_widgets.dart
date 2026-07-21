import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';

class MobileFilterOption {
  const MobileFilterOption(this.value, this.label, {this.icon});

  final String value;
  final String label;
  final IconData? icon;
}

class MobileFilterBar extends StatelessWidget {
  const MobileFilterBar({
    required this.searchHint,
    required this.controller,
    required this.onSearchChanged,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.resultLabel,
    this.onClear,
    super.key,
  });

  final String searchHint;
  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final List<MobileFilterOption> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final String resultLabel;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchBar(
            controller: controller,
            hintText: searchHint,
            leading: const Icon(Icons.search_rounded),
            trailing: [
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'مسح البحث',
                  onPressed: () {
                    controller.clear();
                    onSearchChanged('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
            onChanged: onSearchChanged,
          ),
          if (options.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: options
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsetsDirectional.only(end: 7),
                        child: ChoiceChip(
                          avatar: item.icon == null
                              ? null
                              : Icon(item.icon, size: 16),
                          label: Text(item.label),
                          selected: selected == item.value,
                          onSelected: (_) => onSelected(item.value),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 9),
          Row(
            children: [
              Text(
                resultLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (onClear != null)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                  label: const Text('مسح الفلاتر'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class MobileStatusPill extends StatelessWidget {
  const MobileStatusPill(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Shared status color palette (aligned with the web design tokens):
    final meta = switch (value) {
      'pending' => ('قيد المراجعة', AppColors.statusWarning),
      'manager' => ('عند المدير', AppColors.statusViolet),
      'secretary' => ('عند السكرتير', AppColors.statusInfo),
      'executive' => ('اعتماد تنفيذي', AppColors.statusWarning),
      'high' => ('مرتفعة', AppColors.statusWarning),
      'normal' => ('عادية', AppColors.statusInfo),
      'low' => ('منخفضة', scheme.onSurfaceVariant),
      'approved' => ('معتمد', AppColors.statusSuccess),
      'finalized' => ('مكتمل', AppColors.statusSuccess),
      'published' => ('منشور', AppColors.statusSuccess),
      'rejected' => ('مرفوض', AppColors.statusDanger),
      'urgent' => ('عاجل', AppColors.statusDanger),
      'decision' => ('قرار', AppColors.statusViolet),
      'announcement' => ('إعلان', AppColors.brandPrimary),
      'draft' => ('مسودة', scheme.onSurfaceVariant),
      'cancelled' => ('ملغي', scheme.onSurfaceVariant),
      'active' => ('نشط', AppColors.statusSuccess),
      // Lifecycle / employee states
      'onboarding' => ('قيد التهيئة', AppColors.statusViolet),
      'invited' => ('تمت الدعوة', AppColors.statusInfo),
      'notice_period' => ('فترة إخطار', AppColors.statusWarning),
      'suspended' => ('موقوف', AppColors.statusWarning),
      'terminated' => ('منتهي', AppColors.statusDanger),
      'archived' => ('مؤرشف', scheme.onSurfaceVariant),
      // Attendance / roster states
      'present' => ('حاضر', AppColors.statusSuccess),
      'late' => ('متأخر', AppColors.statusWarning),
      'absent' => ('غائب', AppColors.statusDanger),
      'flagged' => ('مُعلَّم', AppColors.statusWarning),
      'adjusted' => ('مُعدَّل', AppColors.statusInfo),
      'accepted' => ('مقبول', AppColors.statusSuccess),
      'on_leave' || 'leave' => ('في إجازة', AppColors.statusInfo),
      'unregistered' => ('غير مسجّل', scheme.onSurfaceVariant),
      'scheduled' => ('مجدول', AppColors.statusViolet),
      'rest' => ('راحة', scheme.onSurfaceVariant),
      'holiday' => ('عطلة', AppColors.statusInfo),
      'mission' => ('مهمة', AppColors.statusViolet),
      'overtime' => ('عمل إضافي', AppColors.statusWarning),
      // Progress / lifecycle of tasks, courses, requests, cases
      'in_progress' => ('قيد التنفيذ', AppColors.statusInfo),
      'in_review' => ('قيد المراجعة', AppColors.statusWarning),
      'submitted' => ('جديد', AppColors.statusInfo),
      'assigned' => ('تم الإسناد', AppColors.statusViolet),
      'waiting_requester' => ('بانتظار صاحب الطلب', AppColors.statusWarning),
      'completed' => ('مكتمل', AppColors.statusSuccess),
      // KPI Stages
      'goal_setting' => ('تحديد الأهداف', AppColors.statusInfo),
      'mid_year' => ('نصف سنوي', AppColors.statusViolet),
      'final_eval' => ('تقييم نهائي', AppColors.statusWarning),
      'done' => ('مكتملة', AppColors.statusSuccess),
      'resolved' => ('تم الحل', AppColors.statusSuccess),
      'closed' => ('مغلق', scheme.onSurfaceVariant),
      'enrolled' => ('مُسجَّل', AppColors.statusInfo),
      'failed' => ('فشل', AppColors.statusDanger),
      'expired' => ('منتهي الصلاحية', AppColors.statusDanger),
      'escalated' => ('مُصعّد', AppColors.statusDanger),
      'blocked' => ('محظور', AppColors.statusDanger),
      _ => (value, scheme.primary),
    };
    final color = meta.$2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        meta.$1,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class MobileSectionHeader extends StatelessWidget {
  const MobileSectionHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      if (action != null) action!,
    ],
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasis = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasis;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: emphasis ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: emphasis
                          ? scheme.primary.withValues(alpha: .12)
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: emphasis ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MetricGrid extends StatelessWidget {
  const MetricGrid({required this.cards, super.key});

  final List<(String, String, IconData, VoidCallback?)> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 680 ? 3 : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cards.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: columns == 3 ? 1.25 : 1.05,
        ),
        itemBuilder: (context, index) {
          final (label, value, icon, onTap) = cards[index];
          return MetricCard(
            label: label,
            value: value,
            icon: icon,
            emphasis: index == 0,
            onTap: onTap,
          );
        },
      );
    },
  );
}
