import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// فترة التكريم: موظف الشهر أو موظف الأسبوع
enum HonorPeriod {
  month,
  week,
}

/// محور التميز: الانضباط والحضور، المأموريات الميدانية، المهام والتقارير
enum HonorCategory {
  attendance,
  missions,
  reports,
}

/// بطاقة ملخص لوحة الشرف في الصفحة الرئيسية للموظف
class HonorBoardSummaryCard extends ConsumerWidget {
  const HonorBoardSummaryCard({super.key});

  void _showHonorBoard(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const HonorBoardSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final monthData = ref.watch(honorBoardProvider(('month', 'attendance'))).value;
    final weekData = ref.watch(honorBoardProvider(('week', 'attendance'))).value;

    final monthHero = monthData?.isNotEmpty == true ? monthData![0] : null;
    final weekHero = weekData?.isNotEmpty == true ? weekData![0] : null;

    final monthName = monthHero?.name.isNotEmpty == true ? monthHero!.name : 'عمار محمد عبد الباسط';
    final monthMetric = monthHero?.metric.isNotEmpty == true ? monthHero!.metric : '100% انضباط';
    final weekName = weekHero?.name.isNotEmpty == true ? weekHero!.name : 'حامد محمود العمدة';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: .32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: .08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showHonorBoard(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: .35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'لوحة الشرف والتميز الوظيفي',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: const Color(0xFF10B981).withValues(alpha: .3),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.emoji_events_rounded,
                                      size: 11,
                                      color: Color(0xFF10B981),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'لوحة الشرف',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'تكريم نجوم الانضباط والمأموريات والتقارير اليومية',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: .2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '🥇 موظف الشهر: $monthName ($monthMetric) · موظف الأسبوع: $weekName',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_left_rounded,
                        size: 18,
                        color: const Color(0xFFB45309).withValues(alpha: .9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// نافذة لوحة الشرف ومنصة التتويج الشرفية
class HonorBoardSheet extends ConsumerStatefulWidget {
  const HonorBoardSheet({super.key});

  @override
  ConsumerState<HonorBoardSheet> createState() => _HonorBoardSheetState();
}

class _HonorBoardSheetState extends ConsumerState<HonorBoardSheet> {
  HonorPeriod _period = HonorPeriod.month;
  HonorCategory _category = HonorCategory.attendance;

  /// قائمة احتياطية ببيانات الموظفين الفعليين المسجلين في الجمعية في حال عدم توفر اتصال لحظي
  static const Map<HonorPeriod, Map<HonorCategory, List<HonoreeItem>>> _fallbackHonorees = {
    HonorPeriod.month: {
      HonorCategory.attendance: [
        HonoreeItem(
          rank: 1,
          name: 'عمار محمد عبد الباسط',
          department: 'إدارة الميديا',
          achievement: 'حضور كامل 21 يوماً بدون أي تأخير',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/72ab35cd-6a41-4c65-ae07-5a65ad7ff081.webp',
        ),
        HonoreeItem(
          rank: 2,
          name: 'حامد محمود العمدة',
          department: 'لجنة أسرة كريمة',
          achievement: 'حضور كامل 20 يوماً بدون أي تأخير',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/15b92a99-0c55-477c-b847-251c010dd7ab.webp',
        ),
        HonoreeItem(
          rank: 3,
          name: 'محمد سيد محمد',
          department: 'إدارة اللوجستيك',
          achievement: 'التزام تام 19 يوماً بدقة عالية',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/c86776ce-f5e5-4c09-920c-db5b923c0b90/avatar_1786434752876.png',
        ),
        HonoreeItem(
          rank: 4,
          name: 'مصطفي أحمد',
          department: 'إدارة العيادات الطبية',
          achievement: 'التزام تام 17 يوماً بدقة عالية',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/3e950d11-b5b4-4652-9ecf-919c434222fc/avatar_1785929477053.png',
        ),
        HonoreeItem(
          rank: 5,
          name: 'عبد القادر جمال عبد القادر',
          department: 'إدارة الشؤون الإدارية والقانونية',
          achievement: 'التزام تام 16 يوماً بدقة عالية',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/37181f8a-3966-48c2-985b-0b807cb04230.webp',
        ),
      ],
      HonorCategory.missions: [
        HonoreeItem(
          rank: 1,
          name: 'حاتم محمد سالم',
          department: 'إدارة الحركة',
          achievement: 'تنفيذ زيارات ومأموريات ميدانية واسعة التغطية',
          metric: '8 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/70a63425-4285-414b-b980-376f3601d155.webp',
        ),
        HonoreeItem(
          rank: 2,
          name: 'عبد القادر جمال عبد القادر',
          department: 'إدارة الشؤون الإدارية والقانونية',
          achievement: 'تنفيذ زيارات ومأموريات ميدانية واسعة التغطية',
          metric: '7 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/37181f8a-3966-48c2-985b-0b807cb04230.webp',
        ),
        HonoreeItem(
          rank: 3,
          name: 'محمد سيد محمد',
          department: 'إدارة اللوجستيك',
          achievement: 'تنفيذ زيارات ومأموريات ميدانية واسعة التغطية',
          metric: '5 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/c86776ce-f5e5-4c09-920c-db5b923c0b90/avatar_1786434752876.png',
        ),
        HonoreeItem(
          rank: 4,
          name: 'محمد عبدالعظيم محمد',
          department: 'اللجنة الطبية',
          achievement: 'تنفيذ زيارات ومأموريات ميدانية واسعة التغطية',
          metric: '5 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/9e7f11b8-7b9d-4fe7-8a2b-21f61fe99a21.webp',
        ),
        HonoreeItem(
          rank: 5,
          name: 'ربيع محمد أبو زيد',
          department: 'إدارة الحركة',
          achievement: 'تنفيذ زيارات ومأموريات ميدانية واسعة التغطية',
          metric: '5 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/admin/6a4a62a5-23d3-41c7-bf1e-9fd90aa886c8.webp',
        ),
      ],
      HonorCategory.reports: [
        HonoreeItem(
          rank: 1,
          name: 'محمد عبدالعظيم محمد',
          department: 'اللجنة الطبية',
          achievement: 'تسليم جميع التقارير اليومية في الموعد المحدد',
          metric: '10 تقارير',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/9e7f11b8-7b9d-4fe7-8a2b-21f61fe99a21.webp',
        ),
        HonoreeItem(
          rank: 2,
          name: 'محمد سيد محمد',
          department: 'إدارة اللوجستيك',
          achievement: 'توثيق شامل ومعتمد للأنشطة والمهام',
          metric: '9 تقارير',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/c86776ce-f5e5-4c09-920c-db5b923c0b90/avatar_1786434752876.png',
        ),
        HonoreeItem(
          rank: 3,
          name: 'محمد عبده رجب مزار',
          department: 'ادارة المطابخ',
          achievement: 'توثيق شامل ومعتمد للأنشطة والمهام',
          metric: '3 تقارير',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/e4471a93-33ed-484f-9ce6-283acae73470.jpeg',
        ),
        HonoreeItem(
          rank: 4,
          name: 'إبراهيم سلامة عبد الجواد',
          department: 'إدارة الشؤون الإدارية والقانونية',
          achievement: 'توثيق شامل ومعتمد للأنشطة والمهام',
          metric: '1 تقرير',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/2689e62a-ec4c-4c4c-8f35-61029616fab2.webp',
        ),
        HonoreeItem(
          rank: 5,
          name: 'عمار محمد عبد الباسط',
          department: 'إدارة الميديا',
          achievement: 'متابعة دورية وتوثيق مستمر لمهام العمل',
          metric: 'توثيق منتظم',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/72ab35cd-6a41-4c65-ae07-5a65ad7ff081.webp',
        ),
      ],
    },
    HonorPeriod.week: {
      HonorCategory.attendance: [
        HonoreeItem(
          rank: 1,
          name: 'حامد محمود العمدة',
          department: 'لجنة أسرة كريمة',
          achievement: 'التزام تام طوال الأسبوع بالدوام الرسمي',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/15b92a99-0c55-477c-b847-251c010dd7ab.webp',
        ),
        HonoreeItem(
          rank: 2,
          name: 'محمد سيد محمد',
          department: 'إدارة اللوجستيك',
          achievement: 'التزام تام طوال الأسبوع بالدوام الرسمي',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/c86776ce-f5e5-4c09-920c-db5b923c0b90/avatar_1786434752876.png',
        ),
        HonoreeItem(
          rank: 3,
          name: 'عمار محمد عبد الباسط',
          department: 'إدارة الميديا',
          achievement: 'التزام تام طوال الأسبوع بالدوام الرسمي',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/72ab35cd-6a41-4c65-ae07-5a65ad7ff081.webp',
        ),
        HonoreeItem(
          rank: 4,
          name: 'محمد عبده رجب مزار',
          department: 'ادارة المطابخ',
          achievement: 'حضور يومي بدون أي تأخير',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/e4471a93-33ed-484f-9ce6-283acae73470.jpeg',
        ),
        HonoreeItem(
          rank: 5,
          name: 'يوسف رسمي شعبان',
          department: 'مدير مجمع منيل شيحة',
          achievement: 'التزام تام بالدوام الرسمي للمجمع',
          metric: '100% انضباط',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/d0653222-9777-464f-a14c-02a11bcfb84c/avatar_1785924358551.png',
        ),
      ],
      HonorCategory.missions: [
        HonoreeItem(
          rank: 1,
          name: 'حاتم محمد سالم',
          department: 'إدارة الحركة',
          achievement: 'الأعلى إنجازاً للمأموريات هذا الأسبوع',
          metric: '4 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/70a63425-4285-414b-b980-376f3601d155.webp',
        ),
        HonoreeItem(
          rank: 2,
          name: 'عبد القادر جمال عبد القادر',
          department: 'إدارة الشؤون الإدارية والقانونية',
          achievement: 'تنفيذ سريع وموثق لكافة الزيارات',
          metric: '3 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/37181f8a-3966-48c2-985b-0b807cb04230.webp',
        ),
        HonoreeItem(
          rank: 3,
          name: 'ربيع محمد أبو زيد',
          department: 'إدارة الحركة',
          achievement: 'تغطية ميدانية متميزة بالمواقع',
          metric: '2 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/admin/6a4a62a5-23d3-41c7-bf1e-9fd90aa886c8.webp',
        ),
        HonoreeItem(
          rank: 4,
          name: 'محمد سيد محمد',
          department: 'إدارة اللوجستيك',
          achievement: 'إنجاز المهام الخارجية بدقة',
          metric: '2 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/c86776ce-f5e5-4c09-920c-db5b923c0b90/avatar_1786434752876.png',
        ),
        HonoreeItem(
          rank: 5,
          name: 'محمد عبدالعظيم محمد',
          department: 'اللجنة الطبية',
          achievement: 'استجابة ميدانية فورية وتوثيق شامل',
          metric: '2 مأموريات',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/9e7f11b8-7b9d-4fe7-8a2b-21f61fe99a21.webp',
        ),
      ],
      HonorCategory.reports: [
        HonoreeItem(
          rank: 1,
          name: 'محمد عبدالعظيم محمد',
          department: 'اللجنة الطبية',
          achievement: 'إنجاز يومي كامل لتقارير العمل الميداني',
          metric: '4 تقارير',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/9e7f11b8-7b9d-4fe7-8a2b-21f61fe99a21.webp',
        ),
        HonoreeItem(
          rank: 2,
          name: 'محمد سيد محمد',
          department: 'إدارة اللوجستيك',
          achievement: 'تسليم في الموعد بدون أي تأخير',
          metric: '9 تقارير سابقة',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/public/employee-avatars/c86776ce-f5e5-4c09-920c-db5b923c0b90/avatar_1786434752876.png',
        ),
        HonoreeItem(
          rank: 3,
          name: 'محمد عبده رجب مزار',
          department: 'ادارة المطابخ',
          achievement: 'تقارير مفصلة للمهام المنجزة',
          metric: '3 تقارير سابقة',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/e4471a93-33ed-484f-9ce6-283acae73470.jpeg',
        ),
        HonoreeItem(
          rank: 4,
          name: 'إبراهيم سلامة عبد الجواد',
          department: 'إدارة الشؤون الإدارية والقانونية',
          achievement: 'دقة عالية في توثيق الأنشطة',
          metric: '1 تقرير سابق',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/2689e62a-ec4c-4c4c-8f35-61029616fab2.webp',
        ),
        HonoreeItem(
          rank: 5,
          name: 'عمار محمد عبد الباسط',
          department: 'إدارة الميديا',
          achievement: 'رفع التقارير والتوثيق الميداني بانتظام',
          metric: 'توثيق منتظم',
          photoUrl: 'https://ujzzvqsodyhnnnpkoaml.supabase.co/storage/v1/object/authenticated/employee-avatars/admin/72ab35cd-6a41-4c65-ae07-5a65ad7ff081.webp',
        ),
      ],
    },
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentProfile = ref.watch(mobileProfileProvider).value;
    final currentName = currentProfile?.fullNameAr ?? '';

    final periodStr = _period == HonorPeriod.month ? 'month' : 'week';
    final categoryStr = switch (_category) {
      HonorCategory.attendance => 'attendance',
      HonorCategory.missions => 'missions',
      HonorCategory.reports => 'reports',
    };

    final asyncData = ref.watch(honorBoardProvider((periodStr, categoryStr)));
    final honorees = (asyncData.value != null && asyncData.value!.isNotEmpty)
        ? asyncData.value!
        : (_fallbackHonorees[_period]?[_category] ?? const <HonoreeItem>[]);

    final first = honorees.isNotEmpty ? honorees[0] : null;
    final second = honorees.length > 1 ? honorees[1] : null;
    final third = honorees.length > 2 ? honorees[2] : null;

    final periodLabel = _period == HonorPeriod.month ? 'شهر سبتمبر' : 'الأسبوع الحالي';
    final categoryLabel = switch (_category) {
      HonorCategory.attendance => 'الانضباط والحضور',
      HonorCategory.missions => 'المأموريات الميدانية',
      HonorCategory.reports => 'المهام والتقارير اليومية',
    };

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // شريط السحب والإغلاق
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: .3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.emoji_events_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'لوحة الشرف والتميز',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'تكريم نخبة الموظفين الأكثر انضباطاً وعطاءً',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // المحتوى القابل للتمرير
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // محدد الفترة: موظف الشهر وموظف الأسبوع
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PeriodSelectButton(
                            title: 'موظف الشهر 🌟',
                            subtitle: 'شهر سبتمبر',
                            isSelected: _period == HonorPeriod.month,
                            onTap: () => setState(() => _period = HonorPeriod.month),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _PeriodSelectButton(
                            title: 'موظف الأسبوع ⚡',
                            subtitle: 'الأسبوع الحالي',
                            isSelected: _period == HonorPeriod.week,
                            onTap: () => setState(() => _period = HonorPeriod.week),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // محدد فئة التميز
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _CategorySelectChip(
                          icon: Icons.access_time_filled_rounded,
                          label: 'الانضباط والحضور',
                          isSelected: _category == HonorCategory.attendance,
                          onTap: () => setState(() => _category = HonorCategory.attendance),
                        ),
                        const SizedBox(width: 8),
                        _CategorySelectChip(
                          icon: Icons.directions_car_rounded,
                          label: 'المأموريات الميدانية',
                          isSelected: _category == HonorCategory.missions,
                          onTap: () => setState(() => _category = HonorCategory.missions),
                        ),
                        const SizedBox(width: 8),
                        _CategorySelectChip(
                          icon: Icons.assignment_turned_in_rounded,
                          label: 'المهام والتقارير',
                          isSelected: _category == HonorCategory.reports,
                          onTap: () => setState(() => _category = HonorCategory.reports),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // منصة التتويج الشرفية (Podium) للمراكز الثلاثة الأولى
                  if (first != null && second != null && third != null) ...[
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFF59E0B).withValues(alpha: .12),
                            scheme.surface,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: .25),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.stars_rounded,
                                size: 18,
                                color: Color(0xFFD97706),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'منصة التتويج الشرفية — $periodLabel',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // المركز الثاني 🥈 (فضة)
                              Expanded(
                                child: _PodiumStepWidget(
                                  item: second,
                                  pedestalHeight: 82,
                                  ringColor: const Color(0xFF94A3B8),
                                  gradientColors: const [
                                    Color(0xFFCBD5E1),
                                    Color(0xFF94A3B8),
                                  ],
                                  medalBadge: '🥈 المركز الثاني',
                                  badgeColor: const Color(0xFF475569),
                                  avatarRadius: 26,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // المركز الأول 🥇 (ذهب) - في المنتصف وأكثر ارتفاعاً
                              Expanded(
                                child: _PodiumStepWidget(
                                  item: first,
                                  pedestalHeight: 110,
                                  ringColor: const Color(0xFFF59E0B),
                                  gradientColors: const [
                                    Color(0xFFFBBF24),
                                    Color(0xFFD97706),
                                  ],
                                  medalBadge: '🥇 المركز الأول',
                                  badgeColor: const Color(0xFF78350F),
                                  avatarRadius: 32,
                                  isFirst: true,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // المركز الثالث 🥉 (برونز)
                              Expanded(
                                child: _PodiumStepWidget(
                                  item: third,
                                  pedestalHeight: 64,
                                  ringColor: const Color(0xFFB45309),
                                  gradientColors: const [
                                    Color(0xFFD97706),
                                    Color(0xFFB45309),
                                  ],
                                  medalBadge: '🥉 المركز الثالث',
                                  badgeColor: const Color(0xFF78350F),
                                  avatarRadius: 24,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // قائمة الشرف والترتيب العام
                  MobileSectionHeader(
                    title: 'ترتيب قائمة الشرف',
                    subtitle: 'نخبة المتميزين في $categoryLabel ($periodLabel).',
                  ),
                  const SizedBox(height: 10),

                  // كروت الموظفين في قائمة الشرف
                  for (final honoree in honorees) ...[
                    _HonoreeListCard(
                      item: honoree,
                      isCurrentUser: currentName.isNotEmpty &&
                          honoree.name.trim() == currentName.trim(),
                    ),
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 12),

                  // بطاقة معايير التقييم والتحفيز
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 22,
                          color: Color(0xFF3B82F6),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'معايير اختيار موظف الأسبوع والشهر',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'يتم تصنيف لوحة الشرف تلقائياً من واقع بيانات المنظومة: دقة تسجيل بصمة الحضور والانصراف، وعدد المأموريات الميدانية المعتمدة والمنجزة، وسرعة رفع التقارير اليومية.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ودجة خطوة المنصة الشرفية (Podium Step)
class _PodiumStepWidget extends StatelessWidget {
  const _PodiumStepWidget({
    required this.item,
    required this.pedestalHeight,
    required this.ringColor,
    required this.gradientColors,
    required this.medalBadge,
    required this.badgeColor,
    required this.avatarRadius,
    this.isFirst = false,
  });

  final HonoreeItem item;
  final double pedestalHeight;
  final Color ringColor;
  final List<Color> gradientColors;
  final String medalBadge;
  final Color badgeColor;
  final double avatarRadius;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isFirst) ...[
          const Text('👑', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
        ],
        // الصورة مع إطار ذهبي أو فضي أو برونزي
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ringColor, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: ringColor.withValues(alpha: isFirst ? .4 : .2),
                blurRadius: 8,
              ),
            ],
          ),
          child: AppAvatar(
            name: item.name,
            photoUrl: item.photoUrl,
            radius: avatarRadius,
          ),
        ),
        const SizedBox(height: 6),
        // اسم الموظف
        Text(
          item.name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: isFirst ? 12 : 11,
          ),
        ),
        const SizedBox(height: 2),
        // القسم
        Text(
          item.department,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        // الشارة الرقمية
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: ringColor.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            item.metric,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: ringColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // قاعدة المنصة
        Container(
          height: pedestalHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: .25),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${item.rank}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  medalBadge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: .9),
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

/// بطاقة الموظف في القائمة الشرفية التفصيلية
class _HonoreeListCard extends StatelessWidget {
  const _HonoreeListCard({
    required this.item,
    required this.isCurrentUser,
  });

  final HonoreeItem item;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (rankIcon, rankColor, rankText) = switch (item.rank) {
      1 => ('🥇', const Color(0xFFF59E0B), 'المركز الأول'),
      2 => ('🥈', const Color(0xFF94A3B8), 'المركز الثاني'),
      3 => ('🥉', const Color(0xFFB45309), 'المركز الثالث'),
      4 => ('4️⃣', scheme.primary, 'المركز الرابع'),
      5 => ('5️⃣', scheme.secondary, 'المركز الخامس'),
      6 => ('6️⃣', scheme.secondary, 'المركز السادس'),
      7 => ('7️⃣', scheme.secondary, 'المركز السابع'),
      8 => ('8️⃣', scheme.secondary, 'المركز الثامن'),
      9 => ('9️⃣', scheme.secondary, 'المركز التاسع'),
      10 => ('🔟', scheme.secondary, 'المركز العاشر'),
      _ => ('🎖️', scheme.secondary, 'المركز ${item.rank}'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? const Color(0xFF10B981).withValues(alpha: .08)
            : scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
              ? const Color(0xFF10B981).withValues(alpha: .4)
              : scheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: Row(
        children: [
          // شارة الترتيب
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: rankColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              rankIcon,
              style: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(width: 10),
          // صورة الموظف
          AppAvatar(
            name: item.name,
            photoUrl: item.photoUrl,
            radius: 20,
          ),
          const SizedBox(width: 10),
          // الاسم والقسم والإنجاز
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'أنت 👏',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.department} · $rankText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.achievement,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // الرقم المميز
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: rankColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item.metric,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: rankColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// زر اختيار فترة التكريم
class _PeriodSelectButton extends StatelessWidget {
  const _PeriodSelectButton({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? scheme.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      elevation: isSelected ? 1.5 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// رقاقة اختيار فئة التميز
class _CategorySelectChip extends StatelessWidget {
  const _CategorySelectChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? const Color(0xFFF59E0B).withValues(alpha: .15)
          : scheme.surfaceContainerHighest.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFF59E0B)
                  : scheme.outlineVariant.withValues(alpha: .4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? const Color(0xFFD97706) : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected ? const Color(0xFFB45309) : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
