import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// صفحة التقارير اليومية العامة — يراها كل المستخدمين.
/// تعرض بطاقات/فقاعات لكل تقرير مع: الصورة، الاسم، المسمى، الإدارة،
/// التاريخ، المحتوى (مقتطع مع «عرض المزيد» للطويل فقط)، إعجاب وتعليق ومشاهدات.
class DailyReportsFeedPage extends ConsumerStatefulWidget {
  const DailyReportsFeedPage({super.key});

  @override
  ConsumerState<DailyReportsFeedPage> createState() =>
      _DailyReportsFeedPageState();
}

class _DailyReportsFeedPageState extends ConsumerState<DailyReportsFeedPage> {
  final Set<String> _expanded = {};

  /// التعليقات مفتوحة بزر التعليق وحده — كان «عرض الكل» وزر التعليق يفتحان
  /// الشيء نفسه.
  final Set<String> _commentsOpen = {};
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
    final access = ref.watch(accessContextProvider).value;
    if (access != null && access.isClinicStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('التقارير اليومية')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'التقارير اليومية غير متاحة لطاقم العيادات.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }

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
                    // 96 أسفلًا: كان زر «تقرير اليوم» العائم يغطي ذيل آخر بطاقة
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final id = item['id'] as String;
                      return _ReportCard(
                        item: item,
                        isExpanded: _expanded.contains(id),
                        onToggleExpand: () => setState(() {
                          if (!_expanded.remove(id)) _expanded.add(id);
                        }),
                        commentsOpen: _commentsOpen.contains(id),
                        onToggleComments: () => setState(() {
                          if (!_commentsOpen.remove(id)) _commentsOpen.add(id);
                        }),
                        myEmployeeId: access?.employeeId,
                        canModerate:
                            access?.permissions.contains('*') ?? false,
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

  /// يبحث عن تقرير اليوم الموجود مسبقًا لتحريره بدل البدء من فراغ: الحفظ
  /// يستبدل تقرير التاريخ نفسه على الخادم (upsert_my_daily_report)، فكان فتح
  /// نموذج فارغ ثم الحفظ يمحو ما كُتب سابقًا.
  Future<void> _composeReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final me = ref.read(accessContextProvider).value?.employeeId;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final mine = me == null
        ? null
        : ref
              .read(dailyReportsFeedProvider(null))
              .asData
              ?.value
              .where((r) => r['employeeId'] == me && r['reportDate'] == today)
              .firstOrNull;

    final draft = await showModalBottomSheet<_ReportDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _ReportComposerSheet(
        initial: mine == null ? null : _ReportDraft.fromFeed(mine),
      ),
    );
    if (draft == null) return;

    try {
      await ref
          .read(mobileCommandsProvider)
          .saveDailyReport(
            reportDate: DateTime.now(),
            achievements: draft.achievements,
            blockers: draft.blockers,
            tomorrowPlan: draft.tomorrowPlan,
          );
      ref.invalidate(dailyReportsFeedProvider(null));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            draft.isEdit ? 'تم تحديث تقرير اليوم.' : 'تم إرسال التقرير اليومي.',
          ),
        ),
      );
    } catch (e, stack) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeError(e, stack))));
    }
  }
}

/// مسودة تقرير اليوم (ناتج النموذج، أو تقرير اليوم الموجود لملئه).
class _ReportDraft {
  const _ReportDraft({
    required this.achievements,
    this.blockers = '',
    this.tomorrowPlan = '',
    this.isEdit = false,
    this.reviewed = false,
  });

  factory _ReportDraft.fromFeed(Map<String, dynamic> r) => _ReportDraft(
    achievements: (r['achievements'] as String? ?? '').trim(),
    blockers: (r['blockers'] as String? ?? '').trim(),
    tomorrowPlan: (r['tomorrowPlan'] as String? ?? '').trim(),
    isEdit: true,
    reviewed: r['reviewedAt'] != null,
  );

  final String achievements;
  final String blockers;
  final String tomorrowPlan;
  final bool isEdit;

  /// راجعه المدير — الخادم يرفض تعديله («التقرير المُراجَع لا يُعدَّل»).
  final bool reviewed;
}

/// نموذج تقرير اليوم. يملك متحكماته ويتخلص منها بعد إغلاقه بالكامل — كان
/// التخلص منها فور انتهاء await يسبق حركة الإغلاق (متحكم مُتخلَّص منه).
class _ReportComposerSheet extends ConsumerStatefulWidget {
  const _ReportComposerSheet({this.initial});

  final _ReportDraft? initial;

  @override
  ConsumerState<_ReportComposerSheet> createState() =>
      _ReportComposerSheetState();
}

class _ReportComposerSheetState extends ConsumerState<_ReportComposerSheet> {
  late final _achievements = TextEditingController(
    text: widget.initial?.achievements,
  );
  late final _blockers = TextEditingController(text: widget.initial?.blockers);
  late final _plan = TextEditingController(text: widget.initial?.tomorrowPlan);
  late bool _isEdit = widget.initial?.isEdit ?? false;
  late bool _reviewed = widget.initial?.reviewed ?? false;
  bool _loadingExisting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) _loadExisting();
  }

  @override
  void dispose() {
    _achievements.dispose();
    _blockers.dispose();
    _plan.dispose();
    super.dispose();
  }

  /// تقرير اليوم قد لا يكون ضمن أول صفحة من تقارير الجميع — نسأل «تقاريري».
  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    try {
      final mine = await ref.read(mobileDailyReportsProvider(null).future);
      final now = DateTime.now();
      final today = mine
          .where(
            (r) =>
                r.reportDate.year == now.year &&
                r.reportDate.month == now.month &&
                r.reportDate.day == now.day,
          )
          .firstOrNull;
      if (!mounted || today == null) return;
      // لا نكتب فوق ما بدأ المستخدم كتابته أثناء التحميل
      if (_achievements.text.isEmpty &&
          _blockers.text.isEmpty &&
          _plan.text.isEmpty) {
        _achievements.text = today.achievements ?? '';
        _blockers.text = today.blockers ?? '';
        _plan.text = today.tomorrowPlan ?? '';
      }
      setState(() {
        _isEdit = true;
        _reviewed = today.reviewedAt != null;
      });
    } catch (_) {
      // تعذّر جلب تقرير اليوم لا يمنع الكتابة
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  void _submit() {
    final done = _achievements.text.trim();
    if (done.length < 3) {
      setState(() => _error = 'اكتب إنجازاتك بوضوح (3 أحرف على الأقل).');
      return;
    }
    Navigator.pop(
      context,
      _ReportDraft(
        achievements: done,
        blockers: _blockers.text.trim(),
        tomorrowPlan: _plan.text.trim(),
        isEdit: _isEdit,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required IconData icon,
    required Color color,
    required String label,
    required String hint,
    required int minLines,
    required int maxLines,
    bool autofocus = false,
    String? errorText,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      readOnly: _reviewed,
      minLines: minLines,
      maxLines: maxLines,
      textInputAction: TextInputAction.newline,
      onChanged: errorText == null
          ? null
          : (_) => setState(() => _error = null),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        alignLabelWithHint: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: .35),
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
          child: Icon(icon, color: color, size: 21),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .7),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: 1.6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateLabel = DateFormat('EEEE d MMMM', 'ar').format(DateTime.now());
    final (noticeIcon, noticeColor, noticeText) = _reviewed
        ? (
            Icons.lock_outline_rounded,
            scheme.primary,
            'راجع مديرك تقرير اليوم — لا يمكن تعديله بعد المراجعة.',
          )
        : (
            Icons.history_edu_rounded,
            const Color(0xFFE08A1E),
            'أرسلت تقرير اليوم من قبل — عدّله ثم احفظ لتحديثه.',
          );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: scheme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEdit ? 'تعديل تقرير اليوم' : 'تقرير اليوم',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        dateLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_loadingExisting)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_isEdit) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: noticeColor.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(noticeIcon, size: 17, color: noticeColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        noticeText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: noticeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _field(
              controller: _achievements,
              icon: Icons.task_alt_rounded,
              color: scheme.primary,
              label: 'الإنجازات',
              hint: 'ما الذي أنجزته اليوم؟ سطر لكل إنجاز',
              minLines: 3,
              maxLines: 8,
              autofocus: !_reviewed && !_isEdit,
              errorText: _error,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _blockers,
              icon: Icons.report_problem_outlined,
              color: const Color(0xFFE08A1E),
              label: 'المعوقات',
              hint: 'ما الذي أعاقك؟ (اختياري)',
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _plan,
              icon: Icons.event_note_rounded,
              color: const Color(0xFF2FA36B),
              label: 'خطة الغد',
              hint: 'ماذا ستعمل غدًا؟ (اختياري)',
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _reviewed || _loadingExisting ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: Icon(
                _reviewed
                    ? Icons.lock_outline_rounded
                    : _isEdit
                    ? Icons.update_rounded
                    : Icons.send_rounded,
              ),
              label: Text(
                _reviewed
                    ? 'تمت مراجعته'
                    : _isEdit
                    ? 'حفظ التعديل'
                    : 'إرسال التقرير',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة تقرير يومي واحدة.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.item,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.commentsOpen,
    required this.onToggleComments,
    required this.commentController,
    required this.onLike,
    required this.onComment,
    required this.onDeleteComment,
    required this.onShowEngagement,
    required this.myEmployeeId,
    required this.canModerate,
  });

  final Map<String, dynamic> item;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final bool commentsOpen;
  final VoidCallback onToggleComments;
  final TextEditingController commentController;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final void Function(String commentId) onDeleteComment;
  final VoidCallback onShowEngagement;
  final String? myEmployeeId;

  /// full-access يحذف أي تعليق (نفس شرط delete_daily_report_comment).
  final bool canModerate;

  /// نص طويل يستحق «عرض المزيد» — وإلا يُعرض كاملًا بلا زر لا يفعل شيئًا.
  static bool _isLong(String text, {required int lines, required int chars}) =>
      '\n'.allMatches(text.trim()).length + 1 > lines ||
      text.trim().length > chars;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final employeeName = item['employeeName'] as String? ?? 'موظف';
    final photoUrl = item['photoUrl'] as String?;
    final jobTitle = (item['jobTitle'] as String?)?.trim();
    final department = (item['department'] as String?)?.trim();
    final reportDate = item['reportDate'] as String?;
    final achievements = (item['achievements'] as String? ?? '').trim();
    final blockers = (item['blockers'] as String? ?? '').trim();
    final tomorrowPlan = (item['tomorrowPlan'] as String? ?? '').trim();
    final managerComment = (item['managerComment'] as String? ?? '').trim();
    final reviewer = (item['reviewedByName'] as String?)?.trim();
    final likesCount = item['likesCount'] as int? ?? 0;
    final isLikedByMe = item['isLikedByMe'] as bool? ?? false;
    final viewersCount = item['viewersCount'] as int? ?? 0;
    final viewers =
        (item['viewers'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
            .toList() ??
        [];
    final comments =
        (item['comments'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
            .toList() ??
        [];

    final subtitle = [
      if (jobTitle != null && jobTitle.isNotEmpty) jobTitle,
      if (department != null && department.isNotEmpty) department,
    ].join(' · ');
    final long =
        _isLong(achievements, lines: 6, chars: 320) ||
        _isLong(blockers, lines: 3, chars: 160) ||
        _isLong(tomorrowPlan, lines: 3, chars: 160);
    final collapsed = long && !isExpanded;
    final viewerNames = viewers
        .map((v) => (v['name'] as String? ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── الرأس: الصورة، الاسم، المسمى · الإدارة، التاريخ ───
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                AppAvatar(
                  name: employeeName,
                  photoUrl: photoUrl,
                  radius: 22,
                  announceName: false,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (reportDate != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .6,
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _formatDate(reportDate),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ─── المحتوى: أقسام بأيقونات، بلا تمرير داخل التمرير ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReportSection(
                  icon: Icons.task_alt_rounded,
                  label: 'الإنجازات',
                  color: scheme.primary,
                  text: achievements,
                  maxLines: collapsed ? 6 : null,
                ),
                if (blockers.isNotEmpty)
                  _ReportSection(
                    icon: Icons.report_problem_outlined,
                    label: 'المعوقات',
                    color: const Color(0xFFE08A1E),
                    text: blockers,
                    maxLines: collapsed ? 2 : null,
                  ),
                if (tomorrowPlan.isNotEmpty)
                  _ReportSection(
                    icon: Icons.event_note_rounded,
                    label: 'خطة الغد',
                    color: const Color(0xFF2FA36B),
                    text: tomorrowPlan,
                    maxLines: collapsed ? 2 : null,
                  ),
              ],
            ),
          ),
          if (long)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onToggleExpand,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                ),
                label: Text(
                  isExpanded ? 'عرض أقل' : 'عرض المزيد',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),

          // ─── تعليق المدير ───
          if (managerComment.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.rate_review_outlined,
                        size: 15,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reviewer == null || reviewer.isEmpty
                              ? 'تعليق المدير'
                              : 'تعليق المدير · $reviewer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    managerComment,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),

          // ─── شريط التفاعل: إعجاب، تعليقات، مشاهدات ───
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Row(
              children: [
                _ActionPill(
                  icon: isLikedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: likesCount > 0 ? '$likesCount' : 'إعجاب',
                  color: isLikedByMe
                      ? const Color(0xFFE5484D)
                      : scheme.onSurfaceVariant,
                  active: isLikedByMe,
                  onTap: onLike,
                ),
                const SizedBox(width: 6),
                _ActionPill(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: comments.isNotEmpty ? '${comments.length}' : 'تعليق',
                  color: commentsOpen
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  active: commentsOpen,
                  onTap: onToggleComments,
                ),
                const Spacer(),
                _ActionPill(
                  icon: Icons.visibility_outlined,
                  label: '$viewersCount',
                  color: scheme.onSurfaceVariant,
                  onTap: onShowEngagement,
                  tooltip: 'من شاهد ومن تفاعل؟',
                ),
              ],
            ),
          ),
          if (viewerNames.isNotEmpty)
            InkWell(
              onTap: onShowEngagement,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  _viewersLine(viewerNames, viewersCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 10),

          // ─── التعليقات (عند فتحها) ───
          if (commentsOpen)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              color: scheme.surfaceContainerHighest.withValues(alpha: .25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
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
                    ...comments.map(
                      (c) => _CommentBubble(
                        comment: c,
                        canDelete:
                            canModerate ||
                            (myEmployeeId != null &&
                                c['employeeId'] == myEmployeeId),
                        onDelete: () => onDeleteComment(c['id'] as String),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commentController,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: 'اكتب تعليقًا…',
                            isDense: true,
                            filled: true,
                            fillColor: scheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
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
                        tooltip: 'إرسال',
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

  static String _viewersLine(List<String> names, int total) {
    final shown = names.take(3).toList();
    final rest = total - shown.length;
    final head = 'شاهده ${shown.join('، ')}';
    return rest > 0 ? '$head و$rest آخرون' : head;
  }

  /// «اليوم» و«أمس» بدل التاريخ الكامل للأيام القريبة.
  static String _formatDate(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (days == 0) return 'اليوم';
    if (days == 1) return 'أمس';
    return DateFormat('d MMMM', 'ar').format(date);
  }
}

/// قسم من التقرير (الإنجازات / المعوقات / خطة الغد) بأيقونة ولون ثابتين.
class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.icon,
    required this.label,
    required this.color,
    required this.text,
    this.maxLines,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          text,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, height: 1.7),
        ),
      ],
    ),
  );
}

/// زر تفاعل مضغوط (أيقونة + عدد) في ذيل البطاقة.
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      color: active ? color.withValues(alpha: .12) : Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// فقاعة تعليق واحدة.
class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.comment,
    required this.canDelete,
    required this.onDelete,
  });

  final Map<String, dynamic> comment;

  /// الحذف لصاحب التعليق أو full-access فقط — كان الزر يظهر على تعليقات
  /// الآخرين فيرفضه الخادم.
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = comment['employeeName'] as String? ?? 'موظف';
    final text = comment['comment'] as String? ?? '';
    final created = DateTime.tryParse(comment['createdAt'] as String? ?? '');
    // الطابع الزمني من الخادم UTC — يُعرض بتوقيت الجهاز (كان متأخرًا 3 ساعات)
    final timeLabel = created == null
        ? null
        : DateFormat('d MMM، h:mm a', 'ar').format(created.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(
            name: name,
            photoUrl: comment['photoUrl'] as String?,
            radius: 15,
            announceName: false,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (timeLabel != null)
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
                ],
              ),
            ),
          ),
          if (canDelete)
            IconButton(
              tooltip: 'حذف التعليق',
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 17,
                color: scheme.error.withValues(alpha: .75),
              ),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
        ],
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
      final dt = DateTime.parse(value as String).toLocal();
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
