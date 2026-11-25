part of '../mobile_request_detail_page.dart';

class _DecisionContextCard extends StatelessWidget {
  const _DecisionContextCard({required this.request});

  final MobileRequestDetail request;

  static bool hasContent(MobileRequestDetail r) =>
      r.insights != null || r.substituteName != null || r.conflicts.isNotEmpty;

  static String _units(double v) => arDays(v.round());

  String _awayLabel(String type) => switch (type) {
    'leave' => 'إجازة',
    'mission' => 'مأمورية',
    'convoy' => 'قافلة',
    'fundraising' => 'فاندي',
    _ => requestTypeLabel(type),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ins = request.insights;
    final days = requestDays(request.payload);
    final rows = <Widget>[];

    Widget row({
      required IconData icon,
      required Color color,
      required String title,
      String? subtitle,
      Widget? extra,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ?extra,
              ],
            ),
          ),
        ],
      ),
    );

    // الرصيد (للإجازات)
    if (ins?.leaveAvailable != null) {
      final available = ins!.leaveAvailable!;
      final short =
          days != null && request.status == 'pending' && available < 0;
      rows.add(
        row(
          icon: Icons.account_balance_wallet_outlined,
          color: short ? AppColors.statusDanger : AppColors.statusSuccess,
          title:
              'المتاح من ${ins.leaveName ?? 'رصيد الإجازة'}: ${_units(available < 0 ? 0 : available)}',
          subtitle: [
            'مستهلك ${fmtUnits(ins.leaveConsumed ?? 0)}',
            'محجوز ${fmtUnits(ins.leaveReserved ?? 0)}',
            if (short) 'الرصيد لا يغطي هذه المدة',
          ].join(' · '),
        ),
      );
    }

    // الزملاء خارج المقر في الفترة نفسها
    if (ins != null && requestPeriodLabel(request.payload) != null) {
      final away = ins.teamAway;
      rows.add(
        row(
          icon: away.isEmpty ? Icons.groups_rounded : Icons.group_off_rounded,
          color: away.isEmpty
              ? AppColors.statusSuccess
              : AppColors.statusWarning,
          title: away.isEmpty
              ? (ins.teamSize == 0
                    ? 'لا زملاء آخرين في إدارته'
                    : 'لا أحد من زملاء إدارته خارج الجمعية في الفترة نفسها')
              : '${arEmployees(away.length)} من إدارته خارج الجمعية في الفترة نفسها',
          subtitle: away.isEmpty
              ? (ins.teamSize == 0
                    ? null
                    : 'لا يوجد تعارض مع جدول الإدارة (متاح بالكامل)')
              : (ins.teamSize == 0
                    ? null
                    : 'من أصل ${arEmployees(ins.teamSize)} في الإدارة'),
          extra: away.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in away.take(8))
                        RequestMetaChip(
                          icon: requestTypeIcon(a.type),
                          text:
                              '${a.name} · ${_awayLabel(a.type)}${a.status == 'pending' ? ' (قيد المراجعة)' : ''}',
                          color: requestTypeColor(a.type),
                        ),
                      if (away.length > 8)
                        RequestMetaChip(
                          icon: Icons.more_horiz_rounded,
                          text: 'و${away.length - 8} آخرون',
                        ),
                    ],
                  ),
                ),
        ),
      );
    }

    // طلبات الموظف هذا الشهر
    if (ins != null) {
      final parts = [
        if (ins.monthMissions > 0)
          arCount(
            ins.monthMissions,
            one: 'مأمورية واحدة',
            two: 'مأموريتان',
            few: 'مأموريات',
            many: 'مأمورية',
            base: 'مأمورية',
          ),
        if (ins.monthLeaves > 0)
          arCount(
            ins.monthLeaves,
            one: 'إجازة واحدة',
            two: 'إجازتان',
            few: 'إجازات',
            many: 'إجازة',
            base: 'إجازة',
          ),
        if (ins.monthPermits > 0)
          arCount(
            ins.monthPermits,
            one: 'إذن واحد',
            two: 'إذنان',
            few: 'أذونات',
            many: 'إذنًا',
            base: 'إذن',
          ),
      ];
      rows.add(
        row(
          icon: Icons.insights_rounded,
          color: AppColors.statusViolet,
          title: ins.monthTotal == 0
              ? 'لا طلبات أخرى له هذا الشهر'
              : 'طلباته الأخرى هذا الشهر: ${arRequests(ins.monthTotal)}',
          subtitle: [
            if (parts.isNotEmpty) parts.join(' · '),
            if (ins.monthPending > 0) 'قيد المراجعة: ${ins.monthPending}',
            if (ins.monthRejected > 0) 'مرفوض أو مُعاد: ${ins.monthRejected}',
          ].join(' — '),
        ),
      );
    }

    // البديل والتعارضات
    if (request.type == 'leave' || request.substituteName != null) {
      rows.add(
        row(
          icon: Icons.swap_horiz_rounded,
          color: AppColors.brandPrimary,
          title: request.substituteName == null
              ? 'لم يُحدِّد بديلًا أثناء غيابه'
              : 'البديل أثناء غيابه: ${request.substituteName}',
        ),
      );
    }
    for (final conflict in request.conflicts) {
      rows.add(
        row(
          icon: Icons.warning_amber_rounded,
          color: AppColors.statusDanger,
          title: _ContextCard._humanize(conflict),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      icon: Icons.fact_check_outlined,
      title: 'سياق القرار',
      children: rows,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// البديل والتعارضات
// ═══════════════════════════════════════════════════════════════════════════

class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.request});

  final MobileRequestDetail request;

  /// «2026-10-05» داخل رسالة التعارض → «5 أكتوبر».
  static String _humanize(String text) => text
      .replaceAllMapped(RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'), (m) {
        final d = DateTime.tryParse(
          '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}',
        );
        return d == null ? m[0]! : DateFormat('d MMMM', 'ar').format(d);
      })
      .replaceAllMapped(
        RegExp(r'\(([^()]+) إلى ([^()]+)\)'),
        (m) => m[1]!.trim() == m[2]!.trim() ? '(${m[1]!.trim()})' : m[0]!,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.people_alt_outlined,
      title: 'البديل والتعارضات',
      children: [
        Row(
          children: [
            Icon(Icons.swap_horiz_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              'البديل أثناء الغياب: ',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            Expanded(
              child: Text(
                request.substituteName ?? 'لم يُحدَّد',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (request.conflicts.isEmpty)
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 18,
                color: AppColors.statusSuccess,
              ),
              const SizedBox(width: 8),
              Text(
                'لا توجد طلبات متداخلة في الفترة نفسها.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          )
        else
          for (final conflict in request.conflicts)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: AppColors.statusDanger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _humanize(conflict),
                      style: const TextStyle(
                        color: AppColors.statusDanger,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// تنفيذ المأمورية / القافلة / الفاندي
// ═══════════════════════════════════════════════════════════════════════════

