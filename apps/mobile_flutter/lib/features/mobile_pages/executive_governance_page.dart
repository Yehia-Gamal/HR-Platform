import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ExecutiveGovernancePage extends ConsumerStatefulWidget {
  const ExecutiveGovernancePage({super.key});

  @override
  ConsumerState<ExecutiveGovernancePage> createState() =>
      _ExecutiveGovernancePageState();
}

class _ExecutiveGovernancePageState
    extends ConsumerState<ExecutiveGovernancePage> {
  int section = 0;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(mobileExecutiveCommandCenterProvider);
    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(mobileExecutiveCommandCenterProvider),
      child: data.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 90),
            const BrandLogoMark(size: 48),
            const SizedBox(height: 16),
            Icon(
              Icons.gpp_bad_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              humanizeError(error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.invalidate(mobileExecutiveCommandCenterProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
        data: _content,
      ),
    );
  }

  Widget _content(MobileExecutiveCommandCenter data) {
    final openExecution = data.executionItems
        .where(
          (item) => !const {'completed', 'cancelled'}.contains(item.status),
        )
        .length;
    final blocked = data.executionItems
        .where((item) => item.status == 'blocked')
        .length;
    final polls = data.polls.where((item) => item.status == 'open').length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.account_balance_outlined,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الحوكمة والتنفيذ',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Theme.of(
                          context,
                        ).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تقدم تنفيذ القرارات والتصويتات والاجتماعات التنفيذية القادمة.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.45,
                        color: Theme.of(
                          context,
                        ).colorScheme.onPrimaryContainer,
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
            ('بنود مفتوحة', openExecution.toString(), Icons.route_outlined, null),
            ('بنود معطلة', blocked.toString(), Icons.block_outlined, null),
            ('تصويتات مفتوحة', polls.toString(), Icons.how_to_vote_outlined, null),
            (
              'اجتماعات قادمة',
              data.meetings.length.toString(),
              Icons.groups_2_outlined,
              null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.route_outlined),
                label: Text('التنفيذ'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.how_to_vote_outlined),
                label: Text('التصويت'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.event_outlined),
                label: Text('التقويم'),
              ),
            ],
            selected: {section},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => section = value.first),
          ),
        ),
        const SizedBox(height: 18),
        switch (section) {
          0 => _execution(data.executionItems),
          1 => _polls(data.polls),
          _ => _meetings(data.meetings),
        },
      ],
    );
  }

  Widget _execution(List<ExecutiveDecisionExecution> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const MobileSectionHeader(
        title: 'متابعة تنفيذ القرارات',
        subtitle: 'المالك ونسبة الإنجاز والمعوقات والموعد المستهدف.',
      ),
      const SizedBox(height: 10),
      if (items.isEmpty)
        const _GovernanceEmpty(
          icon: Icons.task_alt_rounded,
          message: 'لا توجد بنود تنفيذ قرارات مفتوحة.',
        )
      else
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ExecutionCard(item: item),
          ),
        ),
    ],
  );

  Widget _polls(List<ExecutiveDecisionPoll> polls) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const MobileSectionHeader(
        title: 'التصويت والنصاب',
        subtitle: 'المشاركة الحالية والحد المطلوب وقرارك المسجل.',
      ),
      const SizedBox(height: 10),
      if (polls.isEmpty)
        const _GovernanceEmpty(
          icon: Icons.how_to_vote_outlined,
          message: 'لا توجد تصويتات متاحة حاليًا.',
        )
      else
        ...polls.map(
          (poll) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PollCard(
              item: poll,
              onVote: poll.status == 'open' && poll.canVote
                  ? () => _vote(poll)
                  : null,
            ),
          ),
        ),
    ],
  );

  Widget _meetings(List<ExecutiveMeeting> meetings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const MobileSectionHeader(
        title: 'التقويم التنفيذي',
        subtitle: 'الاجتماعات القادمة ومكانها أو رابط الانضمام.',
      ),
      const SizedBox(height: 10),
      if (meetings.isEmpty)
        const _GovernanceEmpty(
          icon: Icons.event_available_outlined,
          message: 'لا توجد اجتماعات مجدولة قادمة.',
        )
      else
        ...meetings.map(
          (meeting) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  width: 50,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        meeting.scheduledAt == null
                            ? '—'
                            : DateFormat(
                                'd',
                                'ar',
                              ).format(meeting.scheduledAt!.toLocal()),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        meeting.scheduledAt == null
                            ? ''
                            : DateFormat(
                                'MMM',
                                'ar',
                              ).format(meeting.scheduledAt!.toLocal()),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
                title: Text(
                  meeting.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  [
                    if (meeting.scheduledAt != null)
                      DateFormat(
                        'EEEE، h:mm a',
                        'ar',
                      ).format(meeting.scheduledAt!.toLocal()),
                    meeting.locationOrLink,
                  ].whereType<String>().join(' · '),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Future<void> _vote(ExecutiveDecisionPoll poll) async {
    final selected = <String>{...poll.myOptionIds};
    var rating = poll.myRating ?? 3;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  poll.question,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  poll.isAnonymous
                      ? 'التصويت مجهول الهوية وفق إعدادات الاستطلاع.'
                      : 'سيتم تسجيل اختيارك في سجل التصويت المؤمّن.',
                ),
                const SizedBox(height: 16),
                if (poll.pollType == 'rating') ...[
                  Center(
                    child: Text(
                      rating.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Slider(
                    value: rating,
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: rating.toStringAsFixed(0),
                    onChanged: (value) => setModalState(() => rating = value),
                  ),
                ] else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: poll.options
                        .map((option) {
                          final isSelected = selected.contains(option.id);
                          return FilterChip(
                            label: Text(option.label),
                            selected: isSelected,
                            onSelected: (_) => setModalState(() {
                              if (poll.pollType == 'multiple_choice') {
                                isSelected
                                    ? selected.remove(option.id)
                                    : selected.add(option.id);
                              } else {
                                selected
                                  ..clear()
                                  ..add(option.id);
                              }
                            }),
                          );
                        })
                        .toList(growable: false),
                  ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    if (poll.pollType != 'rating' && selected.isEmpty) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('اختر إجابة أولًا.')),
                      );
                      return;
                    }
                    Navigator.pop(sheetContext, true);
                  },
                  icon: const Icon(Icons.how_to_vote_rounded),
                  label: Text(poll.hasVoted ? 'تحديث صوتي' : 'تسجيل صوتي'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    try {
      await ref
          .read(mobileOperationsCommandsProvider)
          .castDecisionVote(
            pollId: poll.id,
            optionIds: selected.toList(growable: false),
            rating: poll.pollType == 'rating' ? rating : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل التصويت بنجاح.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }
}

class _ExecutionCard extends StatelessWidget {
  const _ExecutionCard({required this.item});

  final ExecutiveDecisionExecution item;

  @override
  Widget build(BuildContext context) {
    final overdue =
        item.dueAt != null &&
        item.dueAt!.isBefore(DateTime.now()) &&
        !const {'completed', 'cancelled'}.contains(item.status);
    final color = item.status == 'blocked'
        ? Theme.of(context).colorScheme.error
        : overdue
        ? const Color(0xFFD98508)
        : Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.decisionTitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MobileStatusPill(
                  item.status == 'blocked'
                      ? 'urgent'
                      : item.status == 'completed'
                      ? 'finalized'
                      : 'pending',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: item.progressPercent / 100,
                minHeight: 8,
                color: color,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Text('${item.progressPercent}%'),
                const Spacer(),
                if (item.ownerName != null) Text(item.ownerName!),
                if (item.dueAt != null)
                  Text(
                    ' · ${DateFormat('d MMM', 'ar').format(item.dueAt!.toLocal())}',
                  ),
              ],
            ),
            if (item.blocker != null && item.blocker!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('المعوق: ${item.blocker}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({required this.item, required this.onVote});

  final ExecutiveDecisionPoll item;
  final VoidCallback? onVote;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.decisionTitle ?? 'تصويت تنفيذي',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              MobileStatusPill(item.status == 'open' ? 'active' : 'finalized'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.question,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (item.participationPercent / 100).clamp(0, 1),
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 7),
          Text(
            'المشاركة ${item.participationPercent.toStringAsFixed(0)}% · ${item.voteCount} من ${item.eligibleCount}',
          ),
          if (item.quorumPercent != null)
            Text('النصاب المطلوب ${item.quorumPercent!.toStringAsFixed(0)}%'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: onVote == null
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: item.hasVoted
                        ? const Icon(Icons.verified_rounded)
                        : const SizedBox.shrink(),
                    label: Text(item.hasVoted ? 'تم تسجيل صوتك' : 'للعرض فقط'),
                  )
                : FilledButton.icon(
                    onPressed: onVote,
                    icon: const Icon(Icons.how_to_vote_rounded),
                    label: Text(
                      item.hasVoted ? 'تعديل التصويت' : 'التصويت الآن',
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}

class _GovernanceEmpty extends StatelessWidget {
  const _GovernanceEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        children: [
          Icon(icon, size: 41),
          const SizedBox(height: 9),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
