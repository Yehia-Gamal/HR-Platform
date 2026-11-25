part of '../my_instant_penalties_page.dart';

class _PenaltyCard extends ConsumerWidget {
  const _PenaltyCard({
    required this.item,
    this.highlighted = false,
    this.canAct = false,
    this.manage = false,
  });

  final MobileInstantPenalty item;
  final bool highlighted;

  /// غرامتي: يمكن تقديم عذر عليها.
  final bool canAct;

  /// الإدارة وHR: تأكيد السداد، الإلغاء/الإعفاء، رفع الإيقاف، مراجعة العذر.
  final bool manage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = _statusMeta(item);
    final work = DateTime.tryParse(item.workDate);
    final notes = _parseNotes(item.notes);
    final cancelReason = item.cancelledReason?.trim().isNotEmpty ?? false
        ? item.cancelledReason!.trim()
        : notes.reasons.join('، ');
    final active = _isUnpaid(item.status);
    final escalated = item.currentAmount != item.originalAmount;
    final deadline = AppTime.toCairo(item.createdAt).add(const Duration(hours: 24));
    final remaining = deadline.difference(DateTime.now());

    final cancelled = item.status == 'cancelled';
    final lateText = item.lateMinutes >= 240
        ? 'لم يسجّل بصمة الحضور'
        : 'تأخير ${_minutes(item.lateMinutes)}';
    // التأخير والمبلغ في الترويسة؛ الصفوف لما يتغيّر بحسب الحالة فقط
    final rows = <(String, String, Color?)>[
      // Escalated row – use brighter red in dark mode for readability.
      if (escalated && !cancelled)
        (
          'بعد المضاعفة',
          '${_money(item.originalAmount)} ← ${_money(item.currentAmount)}',
          // Dark mode adaption:
          Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFF87171)
              : AppColors.statusDanger,
        ),
      // Pending payment – show remaining time or mark as expired.
      if (item.status == 'pending_payment')
        (
          'آخر موعد للسداد',
          remaining.inMinutes > 0
              ? '${_dateTime(deadline)} (متبقٍ ${_duration(remaining)})'
              : '${_dateTime(deadline)} (انتهت المهلة)',
          AppColors.statusWarning,
        ),
      if (item.paidAt != null) ('تاريخ السداد', _dateTime(item.paidAt!), null),
      if (item.status == 'paid')
        ('طريقة السداد', _paymentLabel(item.paymentMethod), null),
      if (item.suspendedAt != null)
        ('تاريخ الإيقاف', _dateTime(item.suspendedAt!), AppColors.statusDanger),
      if (item.suspensionLiftedAt != null)
        ('رُفع الإيقاف', _dateTime(item.suspensionLiftedAt!), null),
      if (item.status == 'cancelled' && cancelReason.isNotEmpty)
        (
          meta.label.contains('8 ساعات')
              ? 'تعويض التأخير'
              : meta.label.contains('الوردية')
                  ? 'سبب الإلغاء'
                  : (meta.exempt ? 'سبب الإعفاء' : 'سبب الإلغاء'),
          cancelReason,
          meta.label.contains('8 ساعات')
              ? const Color(0xFF059669)
              : meta.label.contains('الوردية')
                  ? const Color(0xFF0284C7)
                  : null,
        ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlighted
              ? theme.colorScheme.primary
              : meta.color.withValues(alpha: .35),
          width: highlighted ? 2 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── الترويسة: الحالة + اليوم + التأخير | المبلغ ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(meta.icon, size: 21, color: meta.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work == null
                            ? item.workDate
                            : DateFormat('EEEE d MMMM y', 'ar').format(work),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$lateText · سُجّلت ${_registeredAt(item.createdAt, work)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(
                        cancelled ? item.originalAmount : item.currentAmount,
                      ),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: cancelled
                            ? theme.colorScheme.onSurfaceVariant
                            : meta.color,
                        decoration: cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Pill(text: meta.label, color: meta.color),
                  ],
                ),
              ],
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: .35,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (final r in rows)
                      _DetailRow(label: r.$1, value: r.$2, color: r.$3),
                  ],
                ),
              ),
            ],
            if (notes.lines.isNotEmpty) _NotesToggle(lines: notes.lines),
            if (active &&
                item.workDate ==
                    DateFormat('yyyy-MM-dd').format(DateTime.now())) ...[
              const SizedBox(height: 10),
              _TodayCompensationProposalBanner(penalty: item, compact: true),
            ],
            if (item.excuseStatus == 'submitted' && active) ...[
              const SizedBox(height: 10),
              _Notice(
                icon: Icons.hourglass_top_rounded,
                color: AppColors.statusViolet,
                text:
                    'عذر قيد مراجعة الموارد البشرية'
                    '${item.excuseText?.isNotEmpty ?? false ? ': ${item.excuseText}' : ''}',
              ),
            ] else if (item.excuseStatus == 'approved') ...[
              const SizedBox(height: 10),
              _Notice(
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.statusSuccess,
                text:
                    'قُبل العذر وأُلغيت الغرامة'
                    '${item.excuseNotes?.isNotEmpty ?? false ? ' — ${item.excuseNotes}' : ''}',
              ),
            ] else if (item.excuseStatus == 'rejected') ...[
              const SizedBox(height: 10),
              _Notice(
                icon: Icons.cancel_outlined,
                color: AppColors.statusDanger,
                text:
                    'رُفض العذر'
                    '${item.excuseNotes?.isNotEmpty ?? false ? ' — السبب: ${item.excuseNotes}' : ''}',
              ),
            ],
            if (canAct &&
                active &&
                (item.excuseStatus == 'none' ||
                    item.excuseStatus == 'rejected')) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () => _showSubmitExcuseSheet(context, ref, item),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('تقديم عذر'),
                ),
              ),
            ],
            if (manage && active) ...[
              const Divider(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (item.excuseStatus == 'submitted') ...[
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _reviewExcuse(context, ref, item, approve: true),
                      icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                      label: const Text('قبول العذر'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _reviewExcuse(context, ref, item, approve: false),
                      icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                      label: const Text('رفض العذر'),
                    ),
                  ],
                  if (active)
                    FilledButton.icon(
                      onPressed: () => _confirmPayment(context, ref, item),
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('تأكيد السداد'),
                    ),
                  if (active)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final name =
                            item.employeeName?.trim().isNotEmpty ?? false
                            ? item.employeeName!.trim()
                            : 'الزميل العزيز';
                        final work = DateTime.tryParse(item.workDate);
                        final dayDate = work != null
                            ? DateFormat('EEEE d MMMM y', 'ar').format(work)
                            : item.workDate;
                        final lateFormatted = item.lateMinutes >= 240
                            ? 'عدم تسجيل بصمة'
                            : '${item.lateMinutes} دقيقة';
                        final String text;
                        if (item.status == 'suspended') {
                          text =
                              '*إشعار هام وعاجل من إدارة الموارد البشرية (جمعية أحلى شباب)* ⚠️\n\n'
                              'السلام عليكم ورحمة الله، أستاذ *$name* 🌸\n\n'
                              'نود إحاطتكم بأنه قد تم *تعليق حسابكم مؤقتاً على السيستم* لتجاوز مهلة سداد غرامة الحضور المضاعفة (500 ج.م) ليوم *$dayDate*.\n\n'
                              '📌 *بيانات الغرامة:*\n'
                              '• التاريخ: $dayDate\n'
                              '• سبب الغرامة: $lateFormatted تأخير\n'
                              '• المبلغ المطلوب لسداد الغرامة ورفع الإيقاف: *500 ج.م*\n\n'
                              '💳 *طرق السداد المتاحة:* يمكنكم السداد نقداً لدى الإدارة المالية أو عبر إنستاباي، أو تقديم عذر رسمي عبر تطبيق المنظومة في حال وجود ظرف طارئ.\n'
                              'السداد إلى أ/ إبراهيم سلامة وإبلاغ باشمهندس يحيى بالدفع لرفع التعليق واستئناف العمل فوراً.\n\n'
                              '🤝 *تنويه هام:* جميع الغرامات المحصلة تُودع بالكامل في *صندوق الزمالة والتكافل* لدعم الزملاء والمساعدات الاجتماعية.\n\n'
                              'مع خالص التقدير والاحترام 🌺';
                        } else if (item.status == 'doubled') {
                          text =
                              '*تنبيه عاجل: غرامة حضور مضاعفة (500 ج.م)* ⚠️\n\n'
                              'السلام عليكم ورحمة الله، أستاذ *$name* 🌸\n\n'
                              'نود تذكيركم بأنه نظراً لانقضاء مهلة الـ 24 ساعة، تضاعفت غرامة الحضور ليوم *$dayDate* لتصبح *500 ج.م*.\n\n'
                              '📌 *تفاصيل الغرامة:*\n'
                              '• التاريخ: $dayDate\n'
                              '• مدة التأخير: $lateFormatted\n'
                              '• المبلغ المطلوب: *500 ج.م*\n\n'
                              '💳 *طرق السداد المتاحة:* يمكنكم السداد نقداً لدى الإدارة المالية أو عبر إنستاباي، أو تقديم عذر رسمي عبر تطبيق المنظومة في حال وجود ظرف طارئ.\n'
                              '⏰ يرجى سرعة السداد إلى أ/ إبراهيم سلامة وإبلاغ باشمهندس يحيى بالدفع لتفادي تعليق الحساب على المنظومة.\n\n'
                              '🤝 *نحيطكم علماً بأن 100% من حصيلة الغرامات تذهب لصالح صندوق الزمالة والتكافل لدعم الزملاء.*\n\n'
                              'مع تمنياتنا لكم بالتوفيق 🌺';
                        } else {
                          text =
                              '*إشعار تسجيل غرامة حضور وتأخير — جمعية أحلى شباب* ⏰\n\n'
                              'السلام عليكم ورحمة الله، أستاذ *$name* 🌸\n\n'
                              'نحيطكم علماً بأنه تم تسجيل غرامة حضور وتأخير ليوم *$dayDate*:\n'
                              '• مدة التأخير: *$lateFormatted*\n'
                              '• المبلغ المطلوب سداده: *${_money(item.currentAmount)}*\n\n'
                              '⏳ *المهلة النظامية:* متبقي على مهلة الـ 24 ساعة قبل مضاعفة الغرامة إلى 500 ج.م.\n'
                              '💳 *طرق السداد المتاحة:* يمكنكم السداد نقداً لدى الإدارة المالية أو عبر إنستاباي، أو تقديم عذر رسمي عبر تطبيق المنظومة في حال وجود ظرف طارئ.\n'
                              'السداد إلى أ/ إبراهيم سلامة وإبلاغ باشمهندس يحيى بالدفع.\n\n'
                              '🤝 *تنويه:* جميع المبالغ المحصلة تذهب لصالح صندوق الزمالة والتكافل ولا تمثل أي ربح للإدارة.\n\n'
                              'شكراً لتعاونكم وحرصكم الدائم على الانضباط 🌺';
                        }
                        final uri = Uri.parse(
                          'https://wa.me/?text=${Uri.encodeComponent(text)}',
                        );
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('إشعار واتساب'),
                    ),
                  if (manage &&
                      active &&
                      (item.currentAmount > item.originalAmount ||
                          item.status == 'doubled' ||
                          item.status == 'suspended'))
                    OutlinedButton.icon(
                      onPressed: () =>
                          _revertDoubledPenalty(context, ref, item),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: Text(
                        'إرجاع للأصل (${_money(item.originalAmount)})',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4F46E5),
                      ),
                    ),
                  if (item.status == 'suspended')
                    OutlinedButton.icon(
                      onPressed: () => _liftSuspension(context, ref, item),
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: const Text('رفع الإيقاف'),
                    ),
                  if (active)
                    OutlinedButton.icon(
                      onPressed: () => _cancelPenalty(context, ref, item),
                      icon: const Icon(
                        Icons.do_not_disturb_on_outlined,
                        size: 18,
                      ),
                      label: const Text('إلغاء أو إعفاء'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // التسمية في البداية والقيمة محاذاة للنهاية — قراءة سطر بسطر كالإيصال
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// تفاصيل الحساب (من ملاحظات الخادم) مطوية افتراضيًا — كانت تطيل كل بطاقة.
class _NotesToggle extends StatefulWidget {
  const _NotesToggle({required this.lines});

  final List<String> lines;

  @override
  State<_NotesToggle> createState() => _NotesToggleState();
}

class _NotesToggleState extends State<_NotesToggle> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notes_rounded, size: 15, color: muted),
                const SizedBox(width: 6),
                Text(
                  _open ? 'إخفاء التفاصيل' : 'التفاصيل',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: muted,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final line in widget.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $line',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ),
      ],
    );
  }
}

