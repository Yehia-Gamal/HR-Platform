/// صفحة مراجعة الأقران 360° — يعرض قائمة الزملاء المتاحين للمراجعة
/// ويتيح تقييم كل زميل بمعايير محددة مع تعليقات.
library;

import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/kpi_360_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';

class Kpi360ReviewPage extends StatefulWidget {
  const Kpi360ReviewPage({super.key});

  @override
  State<Kpi360ReviewPage> createState() => _Kpi360ReviewPageState();
}

class _Kpi360ReviewPageState extends State<Kpi360ReviewPage> {
  // TODO: استبدال البيانات الوهمية بـ RPC: get_360_peer_targets
  late final List<Kpi360PeerTarget> _peers = _mockPeers();

  @override
  Widget build(BuildContext context) {
    final completed = _peers.where((p) => p.status == ReviewStatus.completed);
    return Scaffold(
      appBar: AppBar(title: const Text('تقييم الزملاء 360°')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          // ─── ملخص التقدم ───────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MobileSectionHeader(
                    title: 'تقدّم المراجعة',
                    subtitle: 'قيّم زملاءك لإكمال دورة التقييم الشامل',
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _peers.isEmpty
                          ? 0
                          : completed.length / _peers.length,
                      minHeight: 8,
                      semanticsLabel: 'تقدم المراجعة',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${completed.length} من ${_peers.length} مراجعات مكتملة',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── قائمة الزملاء ─────────────────────────────────────
          const MobileSectionHeader(
            title: 'الزملاء المتاحون للتقييم',
          ),
          const SizedBox(height: 8),
          ..._peers.map(
            (peer) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PeerCard(
                peer: peer,
                onTap: peer.status == ReviewStatus.completed
                    ? null
                    : () => _openReviewForm(peer),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openReviewForm(Kpi360PeerTarget peer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PeerReviewFormPage(peer: peer),
      ),
    ).then((submitted) {
      if (submitted == true && mounted) {
        setState(() {
          // TODO: إعادة تحميل البيانات من الباك إند بدلاً من التحديث المحلي
          final index = _peers.indexWhere(
              (p) => p.employeeId == peer.employeeId);
          if (index != -1) {
            _peers[index] = Kpi360PeerTarget(
              employeeId: peer.employeeId,
              employeeName: peer.employeeName,
              department: peer.department,
              employeePhotoUrl: peer.employeePhotoUrl,
              status: ReviewStatus.completed,
              submittedAt: DateTime.now(),
            );
          }
        });
      }
    });
  }
}

// ─── بطاقة زميل ──────────────────────────────────────────────

class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.peer, this.onTap});

  final Kpi360PeerTarget peer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLabel = switch (peer.status) {
      ReviewStatus.pending => 'pending',
      ReviewStatus.inProgress => 'in_progress',
      ReviewStatus.completed => 'completed',
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              AppAvatar(
                name: peer.employeeName,
                photoUrl: peer.employeePhotoUrl,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.employeeName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      peer.department,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MobileStatusPill(statusLabel),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── نموذج مراجعة الزميل ─────────────────────────────────────

class _PeerReviewFormPage extends StatefulWidget {
  const _PeerReviewFormPage({required this.peer});

  final Kpi360PeerTarget peer;

  @override
  State<_PeerReviewFormPage> createState() => _PeerReviewFormPageState();
}

class _PeerReviewFormPageState extends State<_PeerReviewFormPage>
    with SingleTickerProviderStateMixin {
  // TODO: جلب المعايير من الباك إند عبر RPC: get_360_criteria
  late final List<Kpi360CriterionRating> _ratings = _mockCriteria();
  final _overallController = TextEditingController();
  String? _recommendation;
  bool _submitting = false;
  bool _submitted = false;
  late final AnimationController _successAnim;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();
    _successAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = CurvedAnimation(
      parent: _successAnim,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _overallController.dispose();
    _successAnim.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _ratings.every((r) => r.score != null && r.score! > 0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_submitted) {
      return Scaffold(
        appBar: AppBar(title: const Text('تقييم الزملاء 360°')),
        body: Center(
          child: ScaleTransition(
            scale: _successScale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 48,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'تم إرسال تقييمك بنجاح',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'شكراً لمساهمتك في تطوير ${widget.peer.employeeName}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('العودة للقائمة'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('تقييم ${widget.peer.employeeName}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          // ─── معلومات الزميل ──────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AppAvatar(
                    name: widget.peer.employeeName,
                    photoUrl: widget.peer.employeePhotoUrl,
                    radius: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.peer.employeeName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          widget.peer.department,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── معايير التقييم ──────────────────────────────────
          const MobileSectionHeader(
            title: 'معايير التقييم',
            subtitle: 'اختر تقييمك لكل معيار (1-5 نجوم)',
          ),
          const SizedBox(height: 8),
          ...List.generate(_ratings.length, (i) {
            final rating = _ratings[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rating.criterionName,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    // نجوم التقييم
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (star) {
                        final starNum = star + 1;
                        final selected =
                            rating.score != null && rating.score! >= starNum;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _ratings[i] =
                                rating.copyWith(score: starNum);
                          }),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              selected
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 36,
                              color:
                                  selected ? Colors.amber : scheme.outline,
                              semanticLabel: '$starNum نجمة',
                            ),
                          ),
                        );
                      }),
                    ),
                    if (rating.score != null) ...[
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          _ratingLabel(rating.score!),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // تعليق على المعيار
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'تعليق (اختياري)',
                        alignLabelWithHint: true,
                      ),
                      maxLines: 2,
                      textDirection: TextDirection.rtl,
                      onChanged: (value) => setState(() {
                        _ratings[i] =
                            rating.copyWith(comment: value);
                      }),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),

          // ─── تعليق عام وتوصية ──────────────────────────────
          const MobileSectionHeader(title: 'التقييم العام'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _overallController,
                    decoration: const InputDecoration(
                      labelText: 'تعليق عام على أداء الزميل',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'التوصية',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _RecommendationChip(
                        label: 'ترقية',
                        icon: Icons.trending_up_rounded,
                        selected: _recommendation == 'promote',
                        onTap: () =>
                            setState(() => _recommendation = 'promote'),
                      ),
                      _RecommendationChip(
                        label: 'تطوير',
                        icon: Icons.school_outlined,
                        selected: _recommendation == 'develop',
                        onTap: () =>
                            setState(() => _recommendation = 'develop'),
                      ),
                      _RecommendationChip(
                        label: 'استمرار',
                        icon: Icons.check_circle_outline_rounded,
                        selected: _recommendation == 'maintain',
                        onTap: () =>
                            setState(() => _recommendation = 'maintain'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ─── زر الإرسال ─────────────────────────────────────
          FilledButton.icon(
            onPressed: _isValid && !_submitting ? _submit : null,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_submitting ? 'جاري الإرسال...' : 'إرسال التقييم'),
          ),
          if (!_isValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'يرجى تقييم جميع المعايير قبل الإرسال',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  String _ratingLabel(int score) => switch (score) {
        1 => 'ضعيف',
        2 => 'دون المتوسط',
        3 => 'متوسط',
        4 => 'جيد',
        5 => 'ممتاز',
        _ => '',
      };

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      // TODO: إرسال التقييم عبر RPC: submit_360_peer_review
      // final review = Kpi360Review(
      //   id: 'new',
      //   targetEmployeeId: widget.peer.employeeId,
      //   targetEmployeeName: widget.peer.employeeName,
      //   reviewerId: currentUserId,
      //   periodMonth: DateTime.now(),
      //   ratings: _ratings,
      //   overallComment: _overallController.text.trim(),
      //   recommendation: _recommendation,
      // );
      // await ref.read(mobileCommandsProvider).submit360PeerReview(review);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _submitted = true);
      _successAnim.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إرسال التقييم: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

// ─── شريحة التوصية ───────────────────────────────────────────

class _RecommendationChip extends StatelessWidget {
  const _RecommendationChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        avatar: Icon(icon, size: 16),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      );
}

// ─── بيانات وهمية ────────────────────────────────────────────

List<Kpi360PeerTarget> _mockPeers() => [
      const Kpi360PeerTarget(
        employeeId: 'emp-001',
        employeeName: 'أحمد محمد',
        department: 'البرامج والأنشطة',
        status: ReviewStatus.pending,
      ),
      const Kpi360PeerTarget(
        employeeId: 'emp-002',
        employeeName: 'سارة علي',
        department: 'الإعلام والتواصل',
        status: ReviewStatus.pending,
      ),
      const Kpi360PeerTarget(
        employeeId: 'emp-003',
        employeeName: 'خالد يوسف',
        department: 'الموارد البشرية',
        status: ReviewStatus.completed,
        submittedAt: null,
      ),
      const Kpi360PeerTarget(
        employeeId: 'emp-004',
        employeeName: 'فاطمة حسن',
        department: 'المالية والمشتريات',
        status: ReviewStatus.pending,
      ),
    ];

List<Kpi360CriterionRating> _mockCriteria() => const [
      Kpi360CriterionRating(
        criterionId: 'teamwork',
        criterionName: 'العمل الجماعي',
      ),
      Kpi360CriterionRating(
        criterionId: 'communication',
        criterionName: 'التواصل الفعّال',
      ),
      Kpi360CriterionRating(
        criterionId: 'initiative',
        criterionName: 'المبادرة والإبداع',
      ),
      Kpi360CriterionRating(
        criterionId: 'reliability',
        criterionName: 'الاعتمادية والالتزام',
      ),
      Kpi360CriterionRating(
        criterionId: 'professionalism',
        criterionName: 'الاحترافية والسلوك',
      ),
    ];
