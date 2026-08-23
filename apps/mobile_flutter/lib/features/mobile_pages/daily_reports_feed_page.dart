import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// صفحة التقارير اليومية العامة — يراها كل المستخدمين.
/// تعرض بطاقات/فقاعات لكل تقرير مع: الصورة، الاسم، المسمى، الإدارة،
/// التاريخ، المحتوى (بارتفاع محدود + تمرير)، أزرار إعجاب وتعليق.
class DailyReportsFeedPage extends ConsumerStatefulWidget {
  const DailyReportsFeedPage({super.key});

  @override
  ConsumerState<DailyReportsFeedPage> createState() =>
      _DailyReportsFeedPageState();
}

class _DailyReportsFeedPageState extends ConsumerState<DailyReportsFeedPage> {
  final Set<String> _expanded = {};
  final Map<String, TextEditingController> _commentControllers = {};
  bool _viewsRecorded = false;
  final _searchCtrl = TextEditingController();
  String _search = '';
  /// فلتر القسم النشط — فارغ يعني «الكل». يُبنى تلقائياً من أقسام التقارير المحمّلة.
  String _deptFilter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final c in _commentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _commentCtrl(String reportId) {
    return _commentControllers.putIfAbsent(
      reportId,
      () => TextEditingController(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final feed = ref.watch(dailyReportsFeedProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير اليومية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
            onPressed: () => ref.invalidate(dailyReportsFeedProvider(null)),
          ),
        ],
      ),
      // V21: زر إضافة تقرير يومي شخصي — يفتح نموذج إنشاء مباشر داخل
      // صفحة التقارير بدل الانتقال لصفحة "تقاريري" المنفصلة (المكررة).
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('تقرير اليوم'),
        onPressed: () => _composeReport(context),
      ),
      body: Column(
        children: [
          // ── شريط البحث ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو القسم أو المسمى…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 4),
          // ── المحتوى ──
          Expanded(
            child: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dailyReportsFeedProvider(null)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 120),
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(dailyReportsFeedProvider(null)),
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
        data: (rawItems) {
          // فلتر الأقسام: يُبنى من الأقسام الظاهرة فعلياً في التقارير المحمّلة.
          final departments = <String>{
            for (final item in rawItems)
              if ((item['department'] as String? ?? '').trim().isNotEmpty)
                (item['department'] as String).trim(),
          }.toList()
            ..sort();
          final byDept = _deptFilter.isEmpty
              ? rawItems
              : rawItems
                  .where((item) =>
                      (item['department'] as String? ?? '').trim() ==
                      _deptFilter)
                  .toList(growable: false);
          final items = _search.isEmpty
              ? byDept
              : byDept.where((item) {
                  final name = (item['employeeName'] as String? ?? '').toLowerCase();
                  final dept = (item['department'] as String? ?? '').toLowerCase();
                  final job = (item['jobTitle'] as String? ?? '').toLowerCase();
                  final ach = (item['achievements'] as String? ?? '').toLowerCase();
                  return name.contains(_search) ||
                      dept.contains(_search) ||
                      job.contains(_search) ||
                      ach.contains(_search);
                }).toList(growable: false);

          if (rawItems.isNotEmpty && !_viewsRecorded) {
            _viewsRecorded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                await ref
                    .read(mobileCommandsProvider)
                    .recordDailyReportsViews(
                      rawItems.map((e) => e['id'] as String).toList(),
                    );
              } catch (_) {
                // المشاهدة تحليلية؛ فشلها لا يمنع قراءة التقارير.
              }
            });
          }
          // شريط رقائق الأقسام يظهر فقط مع أكثر من قسم حتى لا يشوّش القوائم الصغيرة.
          final Widget? deptChips = departments.length > 1
              ? _DepartmentFilterRow(
                  departments: departments,
                  selected: _deptFilter,
                  onSelect: (value) => setState(() => _deptFilter = value),
                )
              : null;
          if (items.isEmpty) {
            return Column(
              children: [
              ?deptChips,
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.article_outlined,
                            size: 64, color: scheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          _search.isNotEmpty || _deptFilter.isNotEmpty
                              ? 'لا توجد تقارير مطابقة للفلتر'
                              : 'لا توجد تقارير بعد',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _search.isNotEmpty || _deptFilter.isNotEmpty
                              ? 'جرّب قسمًا آخر أو امسح البحث.'
                              : 'عندما يرفع الموظفون تقاريرهم اليومية ستظهر هنا.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
                ?deptChips,
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(dailyReportsFeedProvider(null)),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _ReportCard(
                        item: item,
                        isExpanded: _expanded.contains(item['id']),
                        onToggleExpand: () => setState(() {
                          final id = item['id'] as String;
                          if (_expanded.contains(id)) {
                            _expanded.remove(id);
                          } else {
                            _expanded.add(id);
                          }
                        }),
                        commentController: _commentCtrl(item['id'] as String),
                        onLike: () => _onLike(item['id'] as String),
                        onComment: () => _onComment(item['id'] as String),
                        onDeleteComment: (commentId) =>
                            _onDeleteComment(commentId),
                        onShowEngagement: () =>
                            _showEngagement(item['id'] as String),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  ],
),
);
  }

  void _onLike(String reportId) async {
    final commands = ref.read(mobileCommandsProvider);
    try {
      await commands.toggleDailyReportLike(reportId);
    } catch (e, stack) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e, stack))),
        );
      }
    }
  }

  void _onComment(String reportId) async {
    final ctrl = _commentCtrl(reportId);
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    final commands = ref.read(mobileCommandsProvider);
    try {
      await commands.addDailyReportComment(reportId, text);
      ctrl.clear();
    } catch (e, stack) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e, stack))),
        );
      }
    }
  }

  void _onDeleteComment(String commentId) async {
    final commands = ref.read(mobileCommandsProvider);
    try {
      await commands.deleteDailyReportComment(commentId);
    } catch (e, stack) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e, stack))),
        );
      }
    }
  }

  /// لوحة "من شاهد ومن تفاعل؟" لتقرير يومي — القائمة الكاملة.
  void _showEngagement(String reportId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _EngagementSheet(reportId: reportId),
    );
  }

  /// نموذج إنشاء/تعديل تقرير اليوم مباشرة داخل صفحة تقارير الجميع —
  /// يبحث عن تقرير اليوم الموجود مسبقًا لتحريره بدل إنشاء تكرار.
  Future<void> _composeReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final achievements = TextEditingController();
    final blockers = TextEditingController();
    final tomorrow = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تقرير اليوم',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: achievements,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'ما تم إنجازه'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: blockers,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'المعوقات'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tomorrow,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'خطة الغد'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (achievements.text.trim().length < 3) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(
                      content: Text('اكتب الإنجازات بصورة واضحة أولًا.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(sheetContext, true);
              },
              child: const Text('حفظ التقرير'),
            ),
          ],
        ),
      ),
    );

    final done = achievements.text.trim();
    final blocked = blockers.text.trim();
    final next = tomorrow.text.trim();
    achievements.dispose();
    blockers.dispose();
    tomorrow.dispose();
    if (confirmed != true) return;

    try {
      await ref.read(mobileCommandsProvider).saveDailyReport(
            reportDate: DateTime.now(),
            achievements: done,
            blockers: blocked,
            tomorrowPlan: next,
          );
      ref.invalidate(dailyReportsFeedProvider(null));
      messenger.showSnackBar(
        const SnackBar(content: Text('تم حفظ التقرير اليومي.')),
      );
    } catch (e, stack) {
      messenger.showSnackBar(
        SnackBar(content: Text(humanizeError(e, stack))),
      );
    }
  }
}

/// بطاقة تقرير يومي واحدة.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.item,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.commentController,
    required this.onLike,
    required this.onComment,
    required this.onDeleteComment,
    required this.onShowEngagement,
  });

  final Map<String, dynamic> item;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final TextEditingController commentController;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final void Function(String commentId) onDeleteComment;
  final VoidCallback onShowEngagement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final employeeName = item['employeeName'] as String? ?? 'موظف';
    final photoUrl = item['photoUrl'] as String?;
    final jobTitle = item['jobTitle'] as String?;
    final department = item['department'] as String?;
    final reportDate = item['reportDate'] as String?;
    final achievements = item['achievements'] as String? ?? '';
    final blockers = item['blockers'] as String?;
    final tomorrowPlan = item['tomorrowPlan'] as String?;
    final managerComment = item['managerComment'] as String?;
    final likesCount = item['likesCount'] as int? ?? 0;
    final isLikedByMe = item['isLikedByMe'] as bool? ?? false;
    final viewersCount = item['viewersCount'] as int? ?? 0;
    final viewers = (item['viewers'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
            .toList() ??
        [];
    final comments =
        (item['comments'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            [];

    final dateLabel = reportDate != null
        ? _formatDate(reportDate)
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── رأس البطاقة ───
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                AppAvatar(
                  name: employeeName,
                  photoUrl: photoUrl,
                  radius: 24,
                  announceName: false,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          if (jobTitle != null)
                            _chip(jobTitle, scheme.primaryContainer,
                                scheme.onPrimaryContainer),
                          if (department != null)
                            _chip(department, scheme.surfaceContainerHighest,
                                scheme.onSurface),
                        ],
                      ),
                    ],
                  ),
                ),
                if (dateLabel.isNotEmpty)
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),

          // ─── المحتوى (بارتفاع محدود + تمرير أو موسّع) ───
          Container(
            constraints: BoxConstraints(
              maxHeight: isExpanded ? double.infinity : 180,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SingleChildScrollView(
              physics: isExpanded
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('✓ الإنجازات', scheme.primary),
                  const SizedBox(height: 4),
                  Text(achievements, style: const TextStyle(fontSize: 13, height: 1.7)),
                  if (blockers != null && blockers.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _sectionLabel('⚠ المعوقات', const Color(0xFFCC6600)),
                    const SizedBox(height: 4),
                    Text(blockers, style: const TextStyle(fontSize: 13, height: 1.7)),
                  ],
                  if (tomorrowPlan != null && tomorrowPlan.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _sectionLabel('→ خطة الغد', const Color(0xFF2E7D32)),
                    const SizedBox(height: 4),
                    Text(tomorrowPlan, style: const TextStyle(fontSize: 13, height: 1.7)),
                  ],
                ],
              ),
            ),
          ),

          // زر توسيع/طي
          InkWell(
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isExpanded ? 'طي' : 'عرض الكل',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // تعليق المدير
          if (managerComment != null && managerComment.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تعليق المدير',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(managerComment, style: const TextStyle(fontSize: 13, height: 1.6)),
                ],
              ),
            ),

          // ─── سطر المشاهدين: العداد + أول الأسماء + فتح القائمة الكاملة ───
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 2),
            child: Row(
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '$viewersCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                if (viewers.isNotEmpty)
                  Expanded(
                    child: Text(
                      'شاهده: ${viewers.map((v) => v['name'] as String? ?? '').where((n) => n.isNotEmpty).join('، ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: onShowEngagement,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 34),
                  ),
                  child: Text(
                    viewers.isEmpty ? 'من شاهد؟' : 'كل الأسماء',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // ─── شريط التفاعل ───
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Row(
              children: [
                // زر الإعجاب
                FilledButton.tonalIcon(
                  onPressed: onLike,
                  style: FilledButton.styleFrom(
                    backgroundColor: isLikedByMe
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    foregroundColor: isLikedByMe
                        ? Colors.white
                        : scheme.onSurface,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: Icon(
                    isLikedByMe ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                  ),
                  label: Text(likesCount > 0 ? '$likesCount' : 'إعجاب'),
                ),
                const SizedBox(width: 8),
                // زر التعليقات
                OutlinedButton.icon(
                  onPressed: onToggleExpand,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: Text(comments.isNotEmpty ? '${comments.length}' : 'تعليق'),
                ),
              ],
            ),
          ),

          // ─── قسم التعليقات (موسّع) ───
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'لا توجد تعليقات بعد — كن أول من يعلّق',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...comments.map((c) => _CommentBubble(
                          comment: c,
                          onDelete: () =>
                              onDeleteComment(c['id'] as String),
                        )),
                  // صندوق كتابة تعليق
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commentController,
                          decoration: InputDecoration(
                            hintText: 'اكتب تعليقًا…',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: (_) => onComment(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: onComment,
                        icon: const Icon(Icons.send_rounded, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _sectionLabel(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse('${dateStr}T00:00:00');
      return DateFormat('d MMMM', 'ar').format(date);
    } catch (_) {
      return dateStr;
    }
  }
}

/// فقاعة تعليق واحدة.
class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.comment, required this.onDelete});

  final Map<String, dynamic> comment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = comment['employeeName'] as String? ?? 'موظف';
    final text = comment['comment'] as String? ?? '';
    final createdAt = comment['createdAt'] as String?;

    String? timeLabel;
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt);
        timeLabel = DateFormat('d MMM، h:mm a', 'ar').format(dt);
      } catch (_) {
        timeLabel = createdAt;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
                  if (timeLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      timeLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded,
                  size: 16, color: scheme.error.withValues(alpha: .7)),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// لوحة "من شاهد ومن تفاعل؟" لتقرير يومي — القائمة الكاملة للأسماء.
class _EngagementSheet extends ConsumerWidget {
  const _EngagementSheet({required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final engagement = ref.watch(dailyReportEngagementProvider(reportId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: engagement.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              TextButton(
                onPressed: () => ref
                    .invalidate(dailyReportEngagementProvider(reportId)),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
          data: (data) {
            final viewers = (data['viewers'] as List<dynamic>? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
                .toList();
            final likers = (data['likers'] as List<dynamic>? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
                .toList();
            final viewersCount = data['viewersCount'] as int? ?? 0;
            final likersCount = data['likersCount'] as int? ?? 0;

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .72,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Row(
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'من شاهد التقرير؟',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      if (viewersCount > 0)
                        Text(
                          '$viewersCount',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (viewers.isEmpty)
                    _emptyNote(context, 'لم يشاهده أحد بعد.')
                  else
                    ...viewers.map(
                      (v) => _EngagementRow(
                        name: v['name'] as String? ?? 'موظف',
                        photoUrl: v['photoUrl'] as String?,
                        detail: (v['viewCount'] as int? ?? 1) > 1
                            ? '${v['viewCount']} مشاهدة'
                            : _timeLabel(v['at']),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(Icons.favorite_outline,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'من تفاعل معه؟',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      if (likersCount > 0)
                        Text(
                          '$likersCount',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (likers.isEmpty)
                    _emptyNote(context, 'لا تفاعلات بعد — كن أول من يُعجب.')
                  else
                    ...likers.map(
                      (l) => _EngagementRow(
                        name: l['name'] as String? ?? 'موظف',
                        photoUrl: l['photoUrl'] as String?,
                        detail: _timeLabel(l['at']),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _emptyNote(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  String _timeLabel(Object? value) {
    if (value == null) return '';
    try {
      final dt = DateTime.parse(value as String);
      return DateFormat('d MMM، h:mm a', 'ar').format(dt);
    } catch (_) {
      return '';
    }
  }
}

/// صف شخص واحد ضمن قوائم "من شاهد / من تفاعل".
class _EngagementRow extends StatelessWidget {
  const _EngagementRow({
    required this.name,
    required this.photoUrl,
    required this.detail,
  });

  final String name;
  final String? photoUrl;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AppAvatar(name: name, photoUrl: photoUrl, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// شريط رقائق فلتر الأقسام — يُبنى تلقائياً من الأقسام الموجودة في التقارير.
class _DepartmentFilterRow extends StatelessWidget {
  const _DepartmentFilterRow({
    required this.departments,
    required this.selected,
    required this.onSelect,
  });

  final List<String> departments;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        children: [
          for (final entry in <MapEntry<String, String>>[
            const MapEntry('الكل', ''),
            ...departments.map((d) => MapEntry(d, d)),
          ])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Material(
                color: selected == entry.value
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  onTap: () => onSelect(entry.value),
                  borderRadius: BorderRadius.circular(99),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: selected == entry.value
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
